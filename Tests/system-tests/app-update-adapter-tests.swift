import CryptoKit
import Foundation
import NookCore
import Testing
@testable import NookSystem

struct ReleaseManifestSourceTests {
    let source = ReleaseManifestSource(feed: URL(filePath: "/unused"), highlightLimit: 4)

    func manifestJSON(version: String = "0.1.6") throws -> Data {
        let manifest: [String: Any] = [
            "version": version,
            "notes": "## What's new\n\n- Add nookctl\n- Fix a crash\n\n**Full changelog**: x",
            "page": "https://example.com/r/v0.1.6",
            "archive": "https://example.com/d/Nook.zip",
            "checksum": "https://example.com/d/Nook.zip.sha256",
        ]
        return try JSONSerialization.data(withJSONObject: manifest)
    }

    @Test func readsVersionNotesAndArchive() throws {
        let release = try source.parseManifest(try manifestJSON())
        #expect(release.version == AppVersion("0.1.6"))
        #expect(release.highlights == ["Add nookctl", "Fix a crash"])
        #expect(release.page == URL(string: "https://example.com/r/v0.1.6"))
        #expect(release.archive == ReleaseArchive(
            url: URL(string: "https://example.com/d/Nook.zip")!,
            checksumURL: URL(string: "https://example.com/d/Nook.zip.sha256")!))
    }

    @Test func versionThatIsNotAVersionNumberIsRejected() {
        #expect(throws: AppUpdateError.invalidReleaseVersion("nightly")) {
            try source.parseManifest(try manifestJSON(version: "nightly"))
        }
    }

    @Test func manifestWithoutAnArchiveIsRejected() {
        #expect(throws: AppUpdateError.self) {
            try source.parseManifest(Data(#"{"version":"0.1.6","notes":"","page":"https://example.com"}"#.utf8))
        }
    }
}

struct HTTPStatusTests {
    let url = URL(string: "https://example.com/latest.json")!

    func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    @Test func rateLimitStatusesSayTheServerIsLimitingRequests() {
        #expect(throws: AppUpdateError.rateLimited(url.host() ?? "")) { try requireSuccess(response(403), for: url) }
        #expect(throws: AppUpdateError.rateLimited(url.host() ?? "")) { try requireSuccess(response(429), for: url) }
    }

    @Test func otherFailuresNameTheStatus() {
        #expect(throws: AppUpdateError.downloadFailed(url.absoluteString, 404)) { try requireSuccess(response(404), for: url) }
    }
}

struct URLSessionUpdateDownloaderTests {
    @Test func downloadMatchingItsChecksumIsSaved() async throws {
        let (archive, contents) = try makeServedArchive(checksumMatches: true)
        let staging = try makeScratchDirectory()
        let progress = ProgressRecorder()
        let saved = try await URLSessionUpdateDownloader(stagingDirectory: staging).download(archive, progress: progress.record)
        #expect(try Data(contentsOf: saved) == contents)
        #expect(progress.last == DownloadProgress(receivedBytes: Int64(contents.count), totalBytes: Int64(contents.count)))
    }

    @Test func downloadNotMatchingItsChecksumIsDeletedAndRejected() async throws {
        let (archive, _) = try makeServedArchive(checksumMatches: false)
        let staging = try makeScratchDirectory()
        await #expect(throws: AppUpdateError.self) {
            try await URLSessionUpdateDownloader(stagingDirectory: staging).download(archive, progress: { _ in })
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
    }

    func makeServedArchive(checksumMatches: Bool) throws -> (ReleaseArchive, Data) {
        let directory = try makeScratchDirectory()
        let contents = Data((0..<200_000).map { UInt8($0 % 251) })
        let archiveURL = directory.appending(path: "Nook.zip")
        try contents.write(to: archiveURL)
        let digest = SHA256.hash(data: checksumMatches ? contents : Data("other".utf8)).map { String(format: "%02x", $0) }.joined()
        let checksumURL = directory.appending(path: "Nook.zip.sha256")
        try Data("\(digest)\n".utf8).write(to: checksumURL)
        return (ReleaseArchive(url: archiveURL, checksumURL: checksumURL), contents)
    }
}

struct AppBundleReplacerTests {
    @Test func appleSignedAppIsNotTrustedAsAnUpdate() {
        #expect(throws: AppUpdateError.self) {
            try verifySignature(of: URL(filePath: "/System/Applications/Calculator.app"), bundleIdentifier: "dev.nook.manager", team: "VWY82MA6G6")
        }
    }

    @Test func appOnAReadOnlyOrMissingLocationIsNotReplaceable() throws {
        let replacer = InPlaceAppBundleReplacer(appBundle: URL(filePath: "/System/Applications/Calculator.app"), bundleIdentifier: "com.apple.calculator", ditto: dittoExecutable)
        #expect(!replacer.canReplaceInPlace)
    }

    @Test func translocatedAppIsNotReplaceable() throws {
        let replacer = InPlaceAppBundleReplacer(appBundle: URL(filePath: "/private/var/folders/x/AppTranslocation/ABC/d/Nook.app"), bundleIdentifier: "dev.nook.manager", ditto: dittoExecutable)
        #expect(!replacer.canReplaceInPlace)
    }

    @Test func appInAWritableFolderIsReplaceable() throws {
        let directory = try makeScratchDirectory()
        let replacer = InPlaceAppBundleReplacer(appBundle: directory.appending(path: "Nook.app"), bundleIdentifier: "dev.nook.manager", ditto: dittoExecutable)
        #expect(replacer.canReplaceInPlace)
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [DownloadProgress] = []

    var last: DownloadProgress? { lock.withLock { values.last } }

    func record(_ progress: DownloadProgress) {
        lock.withLock { values.append(progress) }
    }
}
