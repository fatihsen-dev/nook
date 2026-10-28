import Foundation
import Testing
@testable import NookCore

struct BuildDiagnosticsTests {
    @Test func extractsErrorWithFileLineAndColumn() {
        let log = """
        Building for production...
        /Users/me/clock/Sources/app.swift:14:17: error: cannot find 'batteryLevel' in scope
            Ring(progress: batteryLevel)
        """
        #expect(parseBuildDiagnostics(log) == [
            BuildDiagnostic(file: URL(filePath: "/Users/me/clock/Sources/app.swift"), line: 14, column: 17, message: "cannot find 'batteryLevel' in scope")
        ])
    }

    @Test func ignoresWarningsAndPlainErrors() {
        let log = """
        /Users/me/clock/Sources/app.swift:3:1: warning: unused variable
        error: fatalError
        """
        #expect(parseBuildDiagnostics(log).isEmpty)
    }

    @Test func keepsEveryErrorInOrder() {
        let log = """
        /a/one.swift:1:2: error: first
        /a/two.swift:3:4: error: second
        """
        #expect(parseBuildDiagnostics(log).map(\.message) == ["first", "second"])
    }
}

struct IdentifierSuggestionTests {
    @Test func combinesOwnerAndKebabCaseName() {
        #expect(suggestIdentifier(forName: "Now Playing", owner: "fatih") == "com.fatih.now-playing")
    }

    @Test func dropsCharactersThatAreNotAllowedInIdentifiers() {
        #expect(suggestIdentifier(forName: "Spotify Mini!", owner: "Fatih Şen") == "com.fatihen.spotify-mini")
    }

    @Test func returnsEmptyWhenNameHasNoUsableCharacters() {
        #expect(suggestIdentifier(forName: " !! ", owner: "fatih") == "")
    }

    @Test func suggestionPassesManifestValidation() throws {
        let identifier = suggestIdentifier(forName: "Mini Dock 2", owner: "fatih")
        try NookletManifest(id: identifier, name: "Mini Dock 2", product: "MiniDock2").validate()
    }
}

struct LogTailTests {
    @Test func returnsLastLinesOfFile() throws {
        let file = try makeTemporaryDirectory().appending(path: "x.log")
        try Data("one\ntwo\nthree\nfour\n".utf8).write(to: file)
        #expect(try readLastLines(of: file, limit: 2) == ["three", "four"])
    }

    @Test func missingFileHasNoLines() throws {
        let file = try makeTemporaryDirectory().appending(path: "missing.log")
        #expect(try readLastLines(of: file, limit: 10).isEmpty)
    }
}
