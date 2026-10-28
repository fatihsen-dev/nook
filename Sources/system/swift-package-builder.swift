import Foundation
import NookCore

public struct SwiftPackageBuilder: NookletBuilder {
    let xcrun: URL

    public init(xcrun: URL) {
        self.xcrun = xcrun
    }

    public func build(product: String, packageDirectory: URL) async throws -> BuildOutcome {
        let buildArguments = ["swift", "build", "--configuration", "release", "--package-path", packageDirectory.path]
        let build = try await runProcess(xcrun, arguments: buildArguments + ["--product", product])
        let log = removeTerminalStyling(build.text)
        guard build.isSuccess else {
            return .failed(log: log)
        }
        let binPath = try await runProcess(xcrun, arguments: buildArguments + ["--show-bin-path"])
        guard binPath.isSuccess else {
            throw SwiftPackageBuildError.binPathUnavailable(packageDirectory.path, binPath.text)
        }
        let binDirectory = binPath.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return .succeeded(executable: URL(filePath: binDirectory).appending(path: product), log: log)
    }

    public func toolchainVersion() async throws -> String {
        let output = try await runProcess(xcrun, arguments: ["swift", "--version"])
        guard output.isSuccess, let version = parseSwiftVersion(output.text) else {
            throw SwiftPackageBuildError.toolchainUnavailable(output.text)
        }
        return version
    }
}

// Matches "Swift version 6.4" in swift --version output, capturing the dotted version number.
nonisolated(unsafe) private let swiftVersionPattern = /Swift version ([0-9]+(?:\.[0-9]+)*)/

// Matches an ANSI SGR escape sequence such as "\u{1B}[1;31m" (ESC, "[", digits and semicolons, "m").
nonisolated(unsafe) private let terminalStylingPattern = /\x{1B}\[[0-9;]*m/

func removeTerminalStyling(_ text: String) -> String {
    text.replacing(terminalStylingPattern, with: "")
}

func parseSwiftVersion(_ output: String) -> String? {
    output.firstMatch(of: swiftVersionPattern).map { String($0.1) }
}

public enum SwiftPackageBuildError: Error, LocalizedError {
    case binPathUnavailable(String, String)
    case toolchainUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .binPathUnavailable(let path, let output):
            "Could not find the build output folder of \(path):\n\(output)"
        case .toolchainUnavailable(let output):
            "No Swift toolchain found. Install Xcode or the Command Line Tools (xcode-select --install).\n\(output)"
        }
    }
}
