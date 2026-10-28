import Foundation
import NookCore

public struct XcodeEditor: CodeEditor {
    let xcrun: URL

    public init(xcrun: URL) {
        self.xcrun = xcrun
    }

    public func openPackage(at directory: URL) async throws {
        try await runXed([directory.path])
    }

    public func open(file: URL, line: Int) async throws {
        try await runXed(["--line", String(line), file.path])
    }

    private func runXed(_ arguments: [String]) async throws {
        let output = try await runProcess(xcrun, arguments: ["xed"] + arguments)
        guard output.isSuccess else {
            throw XcodeEditorError.openFailed(arguments.joined(separator: " "), output.text)
        }
    }
}

public enum XcodeEditorError: Error, LocalizedError {
    case openFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let arguments, let output):
            "Could not open Xcode with xed \(arguments): \(output)"
        }
    }
}
