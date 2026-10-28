import Foundation
import NookCore
import Testing
@testable import NookSystem

struct LaunchAgentPropertyListTests {
    let service = BackgroundService(
        label: "dev.nook.nooklet.com.example.clock",
        executable: URL(filePath: "/tmp/clock/.build/release/Clock"),
        logFile: URL(filePath: "/tmp/logs/com.example.clock.log"))

    func decodedPropertyList() throws -> [String: Any] {
        let data = try makeLaunchAgentPropertyList(for: service)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func usesServiceLabel() throws {
        #expect(try decodedPropertyList()["Label"] as? String == "dev.nook.nooklet.com.example.clock")
    }

    @Test func runsExecutableWithoutArguments() throws {
        #expect(try decodedPropertyList()["ProgramArguments"] as? [String] == ["/tmp/clock/.build/release/Clock"])
    }

    @Test func startsAtLogin() throws {
        #expect(try decodedPropertyList()["RunAtLoad"] as? Bool == true)
    }

    @Test func restartsOnlyAfterUnsuccessfulExit() throws {
        let keepAlive = try #require(try decodedPropertyList()["KeepAlive"] as? [String: Bool])
        #expect(keepAlive == ["SuccessfulExit": false])
    }

    @Test func writesOutputAndErrorsToLogFile() throws {
        let propertyList = try decodedPropertyList()
        #expect(propertyList["StandardOutPath"] as? String == "/tmp/logs/com.example.clock.log")
        #expect(propertyList["StandardErrorPath"] as? String == "/tmp/logs/com.example.clock.log")
    }
}

struct LaunchctlStateTests {
    @Test func runningStateCarriesPID() {
        #expect(parseServiceState("gui/501/dev.nook.nooklet.x = {\n\tactive count = 1\n\tstate = running\n\tpid = 42\n}") == .running(pid: 42))
    }

    @Test func notRunningStateIsStopped() {
        #expect(parseServiceState("gui/501/dev.nook.nooklet.x = {\n\tstate = not running\n}") == .stopped)
    }

    @Test func runningWithoutPIDIsStopped() {
        #expect(parseServiceState("gui/501/dev.nook.nooklet.x = {\n\tstate = running\n}") == .stopped)
    }

    @Test func nestedStateLinesDoNotCount() {
        #expect(parseServiceState("x = {\n\tstate = not running\n\tendpoints = {\n\t\tstate = active\n\t}\n}") == .stopped)
    }
}

struct TerminalStylingTests {
    @Test func removesColourCodesFromCompilerOutput() {
        let styled = "/a/app.swift:8:18: \u{1B}[1;31merror: \u{1B}[1;39mcannot find 'x' in scope\u{1B}[0;0m"
        #expect(removeTerminalStyling(styled) == "/a/app.swift:8:18: error: cannot find 'x' in scope")
    }

    @Test func leavesPlainTextUntouched() {
        #expect(removeTerminalStyling("Build complete!") == "Build complete!")
    }
}

struct SwiftVersionTests {
    @Test func extractsVersionFromSwiftVersionOutput() {
        let output = "swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)\nTarget: arm64-apple-macosx27.0.0"
        #expect(parseSwiftVersion(output) == "6.4")
    }

    @Test func returnsNilForUnrelatedOutput() {
        #expect(parseSwiftVersion("xcrun: error: unable to find utility") == nil)
    }
}

struct JSONLibraryStoreTests {
    @Test func missingFileMeansEmptyLibrary() throws {
        let store = JSONLibraryStore(fileURL: try makeScratchDirectory().appending(path: "library.json"))
        #expect(try store.loadDirectories().isEmpty)
    }

    @Test func savedDirectoriesLoadBack() throws {
        let store = JSONLibraryStore(fileURL: try makeScratchDirectory().appending(path: "nested/library.json"))
        let directories = [URL(filePath: "/tmp/clock"), URL(filePath: "/tmp/dock")]
        try store.saveDirectories(directories)
        #expect(try store.loadDirectories() == directories)
    }

    @Test func corruptFileIsReportedWithItsPath() throws {
        let fileURL = try makeScratchDirectory().appending(path: "library.json")
        try Data("not json".utf8).write(to: fileURL)
        #expect(throws: JSONLibraryStoreError.unreadable(fileURL.path)) {
            try JSONLibraryStore(fileURL: fileURL).loadDirectories()
        }
    }
}

func makeScratchDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: "nook-system-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
