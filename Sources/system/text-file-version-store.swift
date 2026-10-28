import Foundation
import NookCore

struct TextFileVersionStore: NookKitVersionStore {
    let file: URL

    func load() throws -> String? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func save(_ version: String) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("\(version)\n".utf8).write(to: file, options: .atomic)
    }
}
