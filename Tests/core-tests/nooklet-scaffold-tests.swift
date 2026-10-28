import Foundation
import Testing
@testable import NookCore

struct ProductNameTests {
    @Test(arguments: [
        ("Clock", "Clock"),
        ("now playing", "NowPlaying"),
        ("my-dock 2", "MyDock2"),
        ("Spotify Mini!", "SpotifyMini"),
    ])
    func derivesProductNameFromDisplayName(displayName: String, expected: String) throws {
        #expect(try makeProductName(from: displayName) == expected)
    }

    @Test func rejectsDisplayNameWithoutLetters() {
        #expect(throws: NookletScaffoldError.unusableName(" -- ")) {
            try makeProductName(from: " -- ")
        }
    }

    @Test func rejectsDisplayNameStartingWithDigit() {
        #expect(throws: NookletScaffoldError.unusableName("2fa codes")) {
            try makeProductName(from: "2fa codes")
        }
    }
}

struct NookKitDependencyTests {
    @Test func parsesAbsolutePathAsLocalPackage() throws {
        #expect(try NookKitDependency.parse("/Users/me/nook", version: nil) == .localPath("/Users/me/nook"))
    }

    @Test func parsesHTTPSURLAsRemotePackageFromTheAppVersion() throws {
        let url = try #require(URL(string: "https://github.com/me/nook.git"))
        let version = try #require(AppVersion("0.1.6"))
        #expect(try NookKitDependency.parse("https://github.com/me/nook.git", version: version) == .remote(url, version: version))
    }

    @Test func remotePackageWithoutAnAppVersionIsRejected() {
        #expect(throws: NookletScaffoldError.missingNookKitVersion("https://github.com/me/nook.git")) {
            try NookKitDependency.parse("https://github.com/me/nook.git", version: nil)
        }
    }

    @Test(arguments: ["", "relative/nook", "ftp://example.com/nook"])
    func rejectsValuesThatAreNeitherAbsolutePathsNorHTTPSURLs(value: String) {
        #expect(throws: NookletScaffoldError.invalidNookKitDependency(value)) {
            try NookKitDependency.parse(value, version: AppVersion("0.1.6"))
        }
    }
}

struct NookletTemplateTests {
    let manifest = NookletManifest(id: "com.example.now-playing", name: "Now Playing", product: "NowPlaying")

    @Test func packageManifestDependsOnLocalNookKit() {
        let files = makeTemplateFiles(for: manifest, dependency: .localPath("/Users/me/nook"))
        let packageFile = files["Package.swift"] ?? ""
        #expect(packageFile.contains(#".package(path: "/Users/me/nook")"#))
        #expect(packageFile.contains(#".product(name: "NookKit", package: "nook")"#))
        #expect(packageFile.contains(#".executableTarget(name: "NowPlaying""#))
    }

    @Test func packageManifestDependsOnRemoteNookKitFromTheAppVersion() throws {
        let url = try #require(URL(string: "https://github.com/me/nook.git"))
        let dependency = NookKitDependency.remote(url, version: try #require(AppVersion("0.1.6")))
        let packageFile = makeTemplateFiles(for: manifest, dependency: dependency)["Package.swift"] ?? ""
        #expect(packageFile.contains(#".package(url: "https://github.com/me/nook.git", from: "0.1.6")"#))
    }

    @Test func mainBranchLineWrittenByTheTemplateIsPinnedToTheVersion() throws {
        let url = try #require(URL(string: "https://github.com/me/nook.git"))
        let old = #"    dependencies: [.package(url: "https://github.com/me/nook.git", branch: "main")],"#
        let pinned = pinNookKitDependency(in: old, url: url, version: try #require(AppVersion("0.1.6")))
        #expect(pinned == #"    dependencies: [.package(url: "https://github.com/me/nook.git", from: "0.1.6")],"#)
    }

    @Test func handEditedDependencyIsLeftAlone() throws {
        let url = try #require(URL(string: "https://github.com/me/nook.git"))
        let edited = #"    dependencies: [.package(url: "https://github.com/me/nook.git", revision: "abc")],"#
        #expect(pinNookKitDependency(in: edited, url: url, version: try #require(AppVersion("0.1.6"))) == nil)
    }

    @Test func entryFileDeclaresNookletNamedAfterProduct() {
        let entryFile = makeTemplateFiles(for: manifest, dependency: .localPath("/n"))["Sources/app.swift"] ?? ""
        #expect(entryFile.contains("@main"))
        #expect(entryFile.contains("struct NowPlaying: Nooklet"))
    }

    @Test func manifestFileRoundTrips() throws {
        let manifestFile = makeTemplateFiles(for: manifest, dependency: .localPath("/n"))[manifestFileName] ?? ""
        #expect(try NookletManifest.decode(from: Data(manifestFile.utf8)) == manifest)
    }

    @Test func ignoresBuildDirectory() {
        let ignoreFile = makeTemplateFiles(for: manifest, dependency: .localPath("/n"))[".gitignore"] ?? ""
        #expect(ignoreFile.contains(".build/"))
    }
}

struct ScaffoldNookletTests {
    let manifest = NookletManifest(id: "com.example.clock", name: "Clock", product: "Clock")

    @Test func writesTemplateFilesIntoDirectory() throws {
        let directory = try makeTemporaryDirectory()
        try scaffoldNooklet(manifest, dependency: .localPath("/n"), in: directory)
        for path in ["Package.swift", "Sources/app.swift", manifestFileName, ".gitignore"] {
            #expect(FileManager.default.fileExists(atPath: directory.appending(path: path).path))
        }
    }

    @Test func refusesDirectoryThatAlreadyHoldsAPackage() throws {
        let directory = try makeTemporaryDirectory()
        try Data().write(to: directory.appending(path: "Package.swift"))
        #expect(throws: NookletScaffoldError.directoryNotEmpty(directory.path)) {
            try scaffoldNooklet(manifest, dependency: .localPath("/n"), in: directory)
        }
    }
}

func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: "nook-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
