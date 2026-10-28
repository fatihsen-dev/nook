import Foundation
import NookCore

public struct JSONLibraryStore: NookletLibraryStore {
    let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadDirectories() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let paths = try JSONDecoder().decode([String].self, from: Data(contentsOf: fileURL))
            return paths.map { URL(filePath: $0) }
        } catch {
            throw JSONLibraryStoreError.unreadable(fileURL.path)
        }
    }

    public func saveDirectories(_ directories: [URL]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(directories.map(\.path)).write(to: fileURL, options: .atomic)
    }
}

public enum JSONLibraryStoreError: Error, Equatable, LocalizedError {
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            "Nook library file \(path) is not a JSON list of folder paths."
        }
    }
}
