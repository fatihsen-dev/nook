import Foundation

struct ProcessOutput: Sendable {
    let status: Int32
    let text: String

    var isSuccess: Bool { status == 0 }
}

func runProcess(_ executable: URL, arguments: [String]) async throws -> ProcessOutput {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                continuation.resume(returning: try runProcessBlocking(executable, arguments: arguments))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private func runProcessBlocking(_ executable: URL, arguments: [String]) throws -> ProcessOutput {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
    } catch {
        throw ProcessRunnerError.launchFailed(executable.path, error.localizedDescription)
    }
    let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()
    return ProcessOutput(status: process.terminationStatus, text: String(decoding: data, as: UTF8.self))
}

enum ProcessRunnerError: Error, LocalizedError {
    case launchFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let path, let reason):
            "Could not launch \(path): \(reason)"
        }
    }
}
