import Foundation
import NookCore

let emptyCell = "-"
let columnGap = "  "

struct DiagnosticSummary: Codable, Equatable {
    let file: String
    let line: Int
    let column: Int
    let message: String
}

struct BuildSummary: Codable, Equatable {
    let id: String
    let success: Bool
    let durationSeconds: Double
    let diagnostics: [DiagnosticSummary]
    let log: String?

    init(report: BuildReport, id: String) {
        self.id = id
        self.success = report.isSuccess
        self.durationSeconds = seconds(of: report.duration)
        self.diagnostics = report.diagnostics.map {
            DiagnosticSummary(file: $0.file.path, line: $0.line, column: $0.column, message: $0.message)
        }
        self.log = report.isSuccess ? nil : report.log
    }
}

enum NookletStatus: String, Codable {
    case running
    case stopped
    case broken
}

struct NookletSummary: Codable, Equatable {
    let id: String?
    let name: String?
    let directory: String
    let status: NookletStatus
    let pid: Int32?
    let memoryBytes: UInt64?
    let lastBuildSucceeded: Bool?
    let problem: String?
}

func formatBuildReport(_ report: BuildReport, id: String) -> String {
    let duration = String(format: "%.1f s", seconds(of: report.duration))
    guard !report.isSuccess else {
        return "build succeeded for \(id) (\(duration))"
    }
    let details = report.diagnostics.isEmpty
        ? report.log
        : report.diagnostics.map { "\($0.file.path):\($0.line):\($0.column): error: \($0.message)" }.joined(separator: "\n")
    return details + "\nbuild failed for \(id) (\(duration))"
}

func formatList(_ rows: [NookletSummary]) -> String {
    guard !rows.isEmpty else {
        return "no nooklets yet: create one with `nookctl new <folder> --name <name>`"
    }
    let cells = rows.map { [$0.status.rawValue, $0.id ?? emptyCell, $0.name ?? emptyCell, $0.directory] }
    let widths = (0..<3).map { column in cells.map { $0[column].count }.max() ?? 0 }
    return zip(rows, cells).map { row, cell in
        let padded = (0..<3).map { cell[$0].padding(toLength: widths[$0], withPad: " ", startingAt: 0) }
        let line = (padded + [cell[3]]).joined(separator: columnGap)
        return row.problem.map { line + columnGap + "(\($0))" } ?? line
    }.joined(separator: "\n")
}

let emptyJSONArray = Data("[]".utf8)

func encodeJSON<Value: Encodable>(_ value: Value) throws -> Data {
    if let array = value as? [any Encodable], array.isEmpty {
        return emptyJSONArray
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}

func seconds(of duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}
