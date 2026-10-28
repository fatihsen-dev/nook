import Foundation
import NookCore

let reportFileExtension = "json"

public struct JSONBuildReportStore: BuildReportStore {
    let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func load(nookletID: String) throws -> BuildReport? {
        let file = reportFile(for: nookletID)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(BuildReport.self, from: Data(contentsOf: file))
        } catch {
            throw JSONBuildReportStoreError.unreadable(file.path)
        }
    }

    public func save(_ report: BuildReport, nookletID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(report).write(to: reportFile(for: nookletID), options: .atomic)
    }

    public func delete(nookletID: String) throws {
        let file = reportFile(for: nookletID)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return
        }
        try FileManager.default.removeItem(at: file)
    }

    private func reportFile(for nookletID: String) -> URL {
        directory.appending(path: nookletID).appendingPathExtension(reportFileExtension)
    }
}

public enum JSONBuildReportStoreError: Error, Equatable, LocalizedError {
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            "Saved build report \(path) could not be read."
        }
    }
}
