import Foundation
import NookCore

struct JSONNookKitSyncStore: NookKitSyncStore {
    let file: URL

    func load() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        do {
            return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
        } catch {
            throw JSONNookKitSyncStoreError.unreadable(file.path, error.localizedDescription)
        }
    }

    func save(_ versions: [String: String]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(versions).write(to: file, options: .atomic)
    }
}

enum JSONNookKitSyncStoreError: Error, Equatable, LocalizedError {
    case unreadable(String, String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let path, let reason):
            "The NookKit version list at \(path) could not be read: \(reason)"
        }
    }
}
