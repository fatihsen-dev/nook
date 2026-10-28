import Foundation

let identifierDomainPrefix = "com"
let newline: Character = "\n"

public struct BuildDiagnostic: Codable, Equatable, Sendable {
    public let file: URL
    public let line: Int
    public let column: Int
    public let message: String

    public init(file: URL, line: Int, column: Int, message: String) {
        self.file = file
        self.line = line
        self.column = column
        self.message = message
    }
}

// Matches a compiler error line "<path>:<line>:<column>: error: <message>", capturing the four parts.
nonisolated(unsafe) private let compilerErrorPattern = /^(.+?):(\d+):(\d+): error: (.+)$/

public func parseBuildDiagnostics(_ log: String) -> [BuildDiagnostic] {
    log.split(separator: newline).compactMap { line in
        guard let match = String(line).wholeMatch(of: compilerErrorPattern),
              let lineNumber = Int(match.2),
              let column = Int(match.3) else {
            return nil
        }
        return BuildDiagnostic(file: URL(filePath: String(match.1)), line: lineNumber, column: column, message: String(match.4))
    }
}

public func suggestIdentifier(forName name: String, owner: String) -> String {
    let nameSegment = makeIdentifierSegment(from: name, separator: "-")
    let ownerSegment = makeIdentifierSegment(from: owner, separator: "")
    guard !nameSegment.isEmpty, !ownerSegment.isEmpty else {
        return ""
    }
    return [identifierDomainPrefix, ownerSegment, nameSegment].joined(separator: ".")
}

private func makeIdentifierSegment(from text: String, separator: String) -> String {
    let kept = text.lowercased().filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0.isWhitespace || $0 == "-" }
    return kept.split { $0.isWhitespace || $0 == "-" }.joined(separator: separator)
}

func readLastLines(of file: URL, limit: Int) throws -> [String] {
    guard FileManager.default.fileExists(atPath: file.path) else {
        return []
    }
    let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
    return text.split(separator: newline, omittingEmptySubsequences: true).suffix(limit).map(String.init)
}
