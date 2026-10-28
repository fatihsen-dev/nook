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
        #expect(try NookKitDependency.parse("/Users/me/nook") == .localPath("/Users/me/nook"))
    }

    @Test func parsesHTTPSURLAsRemotePackage() throws {
        let url = try #require(URL(string: "https://github.com/me/nook.git"))
        #expect(try NookKitDependency.parse("https://github.com/me/nook.git") == .remote(url))
    }

    @Test(arguments: ["", "relative/nook", "ftp://example.com/nook"])
    func rejectsValuesThatAreNeitherAbsolutePathsNorHTTPSURLs(value: String) {
        #expect(throws: NookletScaffoldError.invalidNookKitDependency(value)) {
            try NookKitDependency.parse(value)
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

    @Test func packageManifestDependsOnRemoteNookKitMainBranch() throws {
        let url = try #require(URL(string: "https://github.com/me/nook.git"))
        let packageFile = makeTemplateFiles(for: manifest, dependency: .remote(url))["Package.swift"] ?? ""
        #expect(packageFile.contains(#".package(url: "https://github.com/me/nook.git", branch: "main")"#))
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
