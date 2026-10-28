import Foundation

let defaultLogLines = 50
let helpFlags: Set<String> = ["--help", "-h"]

enum Command: Equatable {
    case help
    case version
    case list(json: Bool)
    case new(folder: String, name: String, id: String?, shouldRun: Bool)
    case add(folder: String)
    case build(nooklet: String, json: Bool)
    case run(nooklet: String, json: Bool)
    case stop(nooklet: String)
    case remove(nooklet: String)
    case logs(nooklet: String, lines: Int, follow: Bool)
}

enum CommandLineError: Error, Equatable, LocalizedError {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message): "\(message)\nRun `nookctl help` for usage."
        }
    }
}

let usageText = """
    nookctl: build, run and inspect nooklets from the terminal

    usage:
      nookctl list [--json]                                   list the nooklets in the library
      nookctl new <folder> --name <name> [--id <id>] [--run]  create a nooklet and add it to the library
      nookctl add <folder>                                    add an existing nooklet folder
      nookctl build <nooklet> [--json]                        compile without installing or starting
      nookctl run <nooklet> [--json]                          build, install and start (or restart)
      nookctl stop <nooklet>                                  stop a running nooklet
      nookctl logs <nooklet> [--lines <n>] [--follow]         print the nooklet's log
      nookctl remove <nooklet>                                stop it and remove it from the library; keeps the source folder
      nookctl --version
    nookctl help                                            this text (also --help or -h after any command)

    <nooklet> is a nooklet id (com.you.clock) or its folder (. for the current directory).
    Build failures print compiler diagnostics as <file>:<line>:<column>: error: <message> and exit with status 1.
    The Nook app shows changes made here within a few seconds.
    """

func parseCommand(_ arguments: [String]) throws -> Command {
    guard let name = arguments.first, !arguments.contains(where: helpFlags.contains) else {
        return .help
    }
    var parser = ArgumentParser(command: name, arguments: Array(arguments.dropFirst()))
    let command: Command
    switch name {
    case "help":
        command = .help
    case "--version", "version":
        command = .version
    case "list":
        command = .list(json: parser.takeFlag("--json"))
    case "new":
        let nookletName = try parser.takeValue(of: "--name")
        let id = try parser.takeValue(of: "--id")
        let shouldRun = parser.takeFlag("--run")
        let folder = try parser.takePositional(named: "a folder")
        guard let nookletName else {
            throw CommandLineError.usage("new needs --name <name>")
        }
        command = .new(folder: folder, name: nookletName, id: id, shouldRun: shouldRun)
    case "add":
        command = .add(folder: try parser.takePositional(named: "a folder"))
    case "build":
        command = .build(nooklet: try parser.takeNooklet(), json: parser.takeFlag("--json"))
    case "run":
        command = .run(nooklet: try parser.takeNooklet(), json: parser.takeFlag("--json"))
    case "stop":
        command = .stop(nooklet: try parser.takeNooklet())
    case "remove":
        command = .remove(nooklet: try parser.takeNooklet())
    case "logs":
        let lines = try parser.takePositiveNumber(of: "--lines") ?? defaultLogLines
        let follow = parser.takeFlag("--follow")
        command = .logs(nooklet: try parser.takeNooklet(), lines: lines, follow: follow)
    default:
        throw CommandLineError.usage("unknown command \"\(name)\"")
    }
    try parser.ensureEverythingWasUsed()
    return command
}

struct ArgumentParser {
    let command: String
    private var remaining: [String]

    init(command: String, arguments: [String]) {
        self.command = command
        self.remaining = arguments
    }

    mutating func takeFlag(_ flag: String) -> Bool {
        guard let index = remaining.firstIndex(of: flag) else {
            return false
        }
        remaining.remove(at: index)
        return true
    }

    mutating func takeValue(of option: String) throws -> String? {
        guard let index = remaining.firstIndex(of: option) else {
            return nil
        }
        guard index + 1 < remaining.count, !remaining[index + 1].hasPrefix("--") else {
            throw CommandLineError.usage("\(option) needs a value")
        }
        let value = remaining[index + 1]
        remaining.removeSubrange(index...(index + 1))
        return value
    }

    mutating func takePositiveNumber(of option: String) throws -> Int? {
        guard let text = try takeValue(of: option) else {
            return nil
        }
        guard let number = Int(text), number > 0 else {
            throw CommandLineError.usage("\(option) needs a positive number, got \"\(text)\"")
        }
        return number
    }

    mutating func takePositional(named description: String) throws -> String {
        guard let index = remaining.firstIndex(where: { !$0.hasPrefix("--") }) else {
            throw CommandLineError.usage("\(command) needs \(description)")
        }
        return remaining.remove(at: index)
    }

    mutating func takeNooklet() throws -> String {
        try takePositional(named: "a nooklet id or folder")
    }

    func ensureEverythingWasUsed() throws {
        guard let extra = remaining.first else {
            return
        }
        let kind = extra.hasPrefix("--") ? "option" : "argument"
        throw CommandLineError.usage("unknown \(kind) \"\(extra)\" for \(command)")
    }
}
