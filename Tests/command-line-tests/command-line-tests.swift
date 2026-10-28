import Foundation
import NookCore
import Testing
@testable import NookCommandLine

struct CommandParsingTests {
    @Test func noArgumentsShowsHelp() throws {
        #expect(try parseCommand([]) == .help)
        #expect(try parseCommand(["--help"]) == .help)
        #expect(try parseCommand(["help"]) == .help)
    }

    @Test func helpFlagAfterACommandShowsHelp() throws {
        #expect(try parseCommand(["new", "--help"]) == .help)
        #expect(try parseCommand(["build", ".", "-h"]) == .help)
    }

    @Test func emptyJSONListIsCompact() throws {
        #expect(String(decoding: try encodeJSON([NookletSummary]()), as: UTF8.self) == "[]")
    }

    @Test func listAcceptsJSONFlag() throws {
        #expect(try parseCommand(["list"]) == .list(json: false))
        #expect(try parseCommand(["list", "--json"]) == .list(json: true))
    }

    @Test func newNeedsFolderAndName() throws {
        #expect(try parseCommand(["new", "clock", "--name", "Clock"]) == .new(folder: "clock", name: "Clock", id: nil, shouldRun: false))
        #expect(try parseCommand(["new", "clock", "--name", "Clock", "--id", "com.me.clock", "--run"])
            == .new(folder: "clock", name: "Clock", id: "com.me.clock", shouldRun: true))
        #expect(throws: CommandLineError.usage("new needs --name <name>")) {
            try parseCommand(["new", "clock"])
        }
    }

    @Test func nookletCommandsTakeOneReference() throws {
        #expect(try parseCommand(["build", "com.me.clock", "--json"]) == .build(nooklet: "com.me.clock", json: true))
        #expect(try parseCommand(["run", "."]) == .run(nooklet: ".", json: false))
        #expect(try parseCommand(["stop", "com.me.clock"]) == .stop(nooklet: "com.me.clock"))
        #expect(try parseCommand(["remove", "com.me.clock"]) == .remove(nooklet: "com.me.clock"))
        #expect(throws: CommandLineError.usage("build needs a nooklet id or folder")) {
            try parseCommand(["build"])
        }
    }

    @Test func logsDefaultsAndOptions() throws {
        #expect(try parseCommand(["logs", "."]) == .logs(nooklet: ".", lines: defaultLogLines, follow: false))
        #expect(try parseCommand(["logs", ".", "--lines", "20", "--follow"]) == .logs(nooklet: ".", lines: 20, follow: true))
        #expect(throws: CommandLineError.usage("--lines needs a positive number, got \"many\"")) {
            try parseCommand(["logs", ".", "--lines", "many"])
        }
    }

    @Test func unknownCommandOrOptionIsRejected() throws {
        #expect(throws: CommandLineError.usage("unknown command \"deploy\"")) {
            try parseCommand(["deploy"])
        }
        #expect(throws: CommandLineError.usage("unknown option \"--fast\" for build")) {
            try parseCommand(["build", ".", "--fast"])
        }
    }
}

struct OutputFormattingTests {
    let failure = BuildReport(
        isSuccess: false, log: "Compiling\n/a/app.swift:2:5: error: boom",
        diagnostics: [BuildDiagnostic(file: URL(filePath: "/a/app.swift"), line: 2, column: 5, message: "boom")],
        duration: .milliseconds(1500), finishedAt: Date(timeIntervalSince1970: 0))

    @Test func failedBuildPrintsCompilerStyleDiagnostics() {
        #expect(formatBuildReport(failure, id: "com.me.clock") == """
            /a/app.swift:2:5: error: boom
            build failed for com.me.clock (1.5 s)
            """)
    }

    @Test func failedBuildWithoutDiagnosticsPrintsTheLog() {
        let linkerFailure = BuildReport(isSuccess: false, log: "ld: symbol not found", diagnostics: [], duration: .seconds(2), finishedAt: Date())
        #expect(formatBuildReport(linkerFailure, id: "com.me.clock") == """
            ld: symbol not found
            build failed for com.me.clock (2.0 s)
            """)
    }

    @Test func successfulBuildIsOneLine() {
        let success = BuildReport(isSuccess: true, log: "Build complete!", diagnostics: [], duration: .milliseconds(4200), finishedAt: Date())
        #expect(formatBuildReport(success, id: "com.me.clock") == "build succeeded for com.me.clock (4.2 s)")
    }

    @Test func buildJSONCarriesDiagnostics() throws {
        let summary = BuildSummary(report: failure, id: "com.me.clock")
        let object = try JSONSerialization.jsonObject(with: try encodeJSON(summary)) as? [String: Any]
        #expect(object?["id"] as? String == "com.me.clock")
        #expect(object?["success"] as? Bool == false)
        let diagnostics = object?["diagnostics"] as? [[String: Any]]
        #expect(diagnostics?.first?["file"] as? String == "/a/app.swift")
        #expect(diagnostics?.first?["line"] as? Int == 2)
        #expect(object?["log"] as? String == failure.log)
    }

    @Test func listShowsStatusIdentifierAndFolder() {
        let rows = [
            NookletSummary(id: "com.me.clock", name: "Clock", directory: "/n/clock", status: .running, pid: 42, memoryBytes: 9_000_000, lastBuildSucceeded: true, problem: nil),
            NookletSummary(id: nil, name: nil, directory: "/n/old", status: .broken, pid: nil, memoryBytes: nil, lastBuildSucceeded: nil, problem: "no nook.json"),
        ]
        #expect(formatList(rows) == """
            running  com.me.clock  Clock  /n/clock
            broken   -             -      /n/old  (no nook.json)
            """)
    }

    @Test func emptyListExplainsHowToStart() {
        #expect(formatList([]) == "no nooklets yet: create one with `nookctl new <folder> --name <name>`")
    }
}
