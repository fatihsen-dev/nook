import Foundation
import NookCore

public struct LaunchdServiceController: BackgroundServiceController {
    let launchctl: URL
    let launchAgentsDirectory: URL
    let userID: UInt32

    public init(launchctl: URL, launchAgentsDirectory: URL, userID: UInt32) {
        self.launchctl = launchctl
        self.launchAgentsDirectory = launchAgentsDirectory
        self.userID = userID
    }

    public func start(_ service: BackgroundService) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: service.logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        let propertyListURL = propertyListURL(for: service.label)
        try makeLaunchAgentPropertyList(for: service).write(to: propertyListURL)
        try await unload(label: service.label)
        try await runLaunchctl(["bootstrap", domainTarget, propertyListURL.path])
    }

    public func stop(label: String) async throws {
        try await unload(label: label)
        let propertyListURL = propertyListURL(for: label)
        if FileManager.default.fileExists(atPath: propertyListURL.path) {
            try FileManager.default.removeItem(at: propertyListURL)
        }
    }

    public func state(label: String) async throws -> ServiceState {
        let output = try await runProcess(launchctl, arguments: ["print", serviceTarget(for: label)])
        guard output.isSuccess else {
            return .stopped
        }
        return parseServiceState(output.text)
    }

    private var domainTarget: String { "gui/\(userID)" }

    private func serviceTarget(for label: String) -> String { "\(domainTarget)/\(label)" }

    private func propertyListURL(for label: String) -> URL {
        launchAgentsDirectory.appending(path: label).appendingPathExtension(propertyListExtension)
    }

    private func unload(label: String) async throws {
        guard try await isLoaded(label: label) else { return }
        try await runLaunchctl(["bootout", serviceTarget(for: label)])
        let deadline = ContinuousClock.now + unloadTimeout
        while try await isLoaded(label: label) {
            guard ContinuousClock.now < deadline else {
                throw LaunchdServiceError.unloadTimedOut(label)
            }
            try await Task.sleep(for: unloadPollInterval)
        }
    }

    private func isLoaded(label: String) async throws -> Bool {
        try await runProcess(launchctl, arguments: ["print", serviceTarget(for: label)]).isSuccess
    }

    private func runLaunchctl(_ arguments: [String]) async throws {
        let output = try await runProcess(launchctl, arguments: arguments)
        guard output.isSuccess else {
            throw LaunchdServiceError.commandFailed(arguments.joined(separator: " "), output.status, output.text)
        }
    }
}

let propertyListExtension = "plist"
let unloadTimeout: Duration = .seconds(5)
let unloadPollInterval: Duration = .milliseconds(100)

func makeLaunchAgentPropertyList(for service: BackgroundService) throws -> Data {
    let propertyList: [String: Any] = [
        "Label": service.label,
        "ProgramArguments": [service.executable.path],
        "RunAtLoad": true,
        "KeepAlive": ["SuccessfulExit": false],
        "StandardOutPath": service.logFile.path,
        "StandardErrorPath": service.logFile.path,
    ]
    return try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
}

// Matches a top-level "\tkey = value" line of launchctl print output (exactly one leading tab), capturing key and value.
nonisolated(unsafe) private let topLevelPropertyPattern = /^\t([a-z ]+) = (.+)$/

func parseServiceState(_ printOutput: String) -> ServiceState {
    let properties = printOutput.split(separator: "\n").reduce(into: [String: String]()) { properties, line in
        guard let match = String(line).wholeMatch(of: topLevelPropertyPattern) else { return }
        properties[String(match.1)] = String(match.2)
    }
    guard properties["state"] == "running", let pid = properties["pid"].flatMap({ Int32($0) }) else {
        return .stopped
    }
    return .running(pid: pid)
}

public enum LaunchdServiceError: Error, LocalizedError {
    case commandFailed(String, Int32, String)
    case unloadTimedOut(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let status, let output):
            "launchctl \(command) failed with status \(status): \(output)"
        case .unloadTimedOut(let label):
            "launchd did not unload \(label) within \(unloadTimeout)."
        }
    }
}
