import Foundation
import Testing
@testable import NookCore

struct AppVersionTests {
    @Test func parsesTagsWithAndWithoutPrefix() {
        #expect(AppVersion("v0.1.3") == AppVersion("0.1.3"))
        #expect(AppVersion("v0.1.3")?.description == "0.1.3")
        #expect(AppVersion("1.2") == nil)
        #expect(AppVersion("v1.x.3") == nil)
    }

    @Test func comparesNumericallyNotAlphabetically() throws {
        #expect(try #require(AppVersion("0.1.10")) > #require(AppVersion("0.1.9")))
        #expect(try #require(AppVersion("1.0.0")) > #require(AppVersion("0.9.9")))
    }

    @Test func preReleaseComesBeforeTheRelease() throws {
        #expect(try #require(AppVersion("1.0.0-beta.1")) < #require(AppVersion("1.0.0")))
    }
}

struct ReleaseNotesTests {
    @Test func takesBulletLinesOnly() {
        let body = """
        ## What's new
        - Add nookctl to build nooklets from the terminal
        * Fix a crash when a folder is renamed

        **Full Changelog**: https://example.com/compare/v1...v2
        """
        #expect(releaseHighlights(in: body, limit: 4) == [
            "Add nookctl to build nooklets from the terminal",
            "Fix a crash when a folder is renamed",
        ])
    }

    @Test func stopsAtTheLimit() {
        #expect(releaseHighlights(in: "- a\n- b\n- c", limit: 2) == ["a", "b"])
    }

    @Test func emptyBodyHasNoHighlights() {
        #expect(releaseHighlights(in: "", limit: 4).isEmpty)
    }
}

struct AppUpdaterTests {
    let source = FixedReleaseSource()
    let downloader = RecordingDownloader()
    let replacer = RecordingReplacer()

    func makeUpdater(current: String = "0.1.3") throws -> AppUpdater {
        AppUpdater(currentVersion: try #require(AppVersion(current)), source: source, downloader: downloader, replacer: replacer)
    }

    @Test func newerReleaseIsOffered() async throws {
        source.release = makeRelease("0.1.4")
        #expect(try await makeUpdater().check(skipping: nil) == .available(makeRelease("0.1.4")))
    }

    @Test func sameOrOlderReleaseIsUpToDate() async throws {
        source.release = makeRelease("0.1.3")
        #expect(try await makeUpdater().check(skipping: nil) == .upToDate)
        source.release = makeRelease("0.1.2")
        #expect(try await makeUpdater().check(skipping: nil) == .upToDate)
    }

    @Test func skippedVersionIsNotOfferedButANewerOneIs() async throws {
        source.release = makeRelease("0.1.4")
        #expect(try await makeUpdater().check(skipping: AppVersion("0.1.4")) == .skipped)
        source.release = makeRelease("0.1.5")
        #expect(try await makeUpdater().check(skipping: AppVersion("0.1.4")) == .available(makeRelease("0.1.5")))
    }

    @Test func installDownloadsThenReplacesWithTheDownloadedArchive() async throws {
        let release = makeRelease("0.1.4")
        try await makeUpdater().install(release, progress: { _ in })
        #expect(downloader.requests == [release.archive])
        #expect(replacer.archives == [downloader.output])
    }

    @Test func installRefusesWhenTheAppCannotBeReplacedInPlace() async throws {
        replacer.canReplace = false
        await #expect(throws: AppUpdateError.notReplaceableInPlace) {
            try await makeUpdater().install(makeRelease("0.1.4"), progress: { _ in })
        }
        #expect(downloader.requests.isEmpty)
    }

    @Test func failedDownloadNeverReachesTheReplacer() async throws {
        downloader.failure = AppUpdateError.checksumMismatch(expected: "a", actual: "b")
        await #expect(throws: AppUpdateError.checksumMismatch(expected: "a", actual: "b")) {
            try await makeUpdater().install(makeRelease("0.1.4"), progress: { _ in })
        }
        #expect(replacer.archives.isEmpty)
    }
}

func makeRelease(_ version: String) -> AppRelease {
    AppRelease(
        version: AppVersion(version)!,
        highlights: ["Something new"],
        page: URL(string: "https://example.com/releases/v\(version)")!,
        archive: ReleaseArchive(
            url: URL(string: "https://example.com/v\(version)/Nook.zip")!,
            checksumURL: URL(string: "https://example.com/v\(version)/Nook.zip.sha256")!))
}

final class FixedReleaseSource: ReleaseSource, @unchecked Sendable {
    var release = makeRelease("0.1.3")

    func latestRelease() async throws -> AppRelease {
        release
    }
}

final class RecordingDownloader: UpdateDownloader, @unchecked Sendable {
    var requests: [ReleaseArchive] = []
    var failure: Error?
    let output = URL(filePath: "/tmp/nook-update/Nook.zip")

    func download(_ archive: ReleaseArchive, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        requests.append(archive)
        if let failure { throw failure }
        return output
    }
}

final class RecordingReplacer: AppBundleReplacer, @unchecked Sendable {
    var canReplace = true
    var archives: [URL] = []

    var canReplaceInPlace: Bool { canReplace }

    func replace(withArchive archive: URL) async throws {
        archives.append(archive)
    }
}
