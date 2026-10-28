import Foundation

public let manifestFileName = "nook.json"

public struct NookletManifest: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let product: String

    public init(id: String, name: String, product: String) {
        self.id = id
        self.name = name
        self.product = product
    }

    public static func decode(from data: Data) throws -> NookletManifest {
        let manifest: NookletManifest
        do {
            manifest = try JSONDecoder().decode(NookletManifest.self, from: data)
        } catch {
            throw NookletManifestError.malformed(String(describing: error))
        }
        try manifest.validate()
        return manifest
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public func validate() throws {
        guard id.wholeMatch(of: reverseDomainIdentifierPattern) != nil else {
            throw NookletManifestError.invalidIdentifier(id)
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NookletManifestError.blankName
        }
        guard product.wholeMatch(of: swiftTypeNamePattern) != nil else {
            throw NookletManifestError.invalidProduct(product)
        }
    }
}

// Matches lowercase reverse-DNS identifiers with at least two dot-separated segments, such as "com.example.clock".
nonisolated(unsafe) private let reverseDomainIdentifierPattern = /[a-z0-9]+(\.[a-z0-9][a-z0-9-]*)+/

// Matches a Swift type name: an ASCII letter followed by ASCII letters or digits, such as "NowPlaying".
nonisolated(unsafe) let swiftTypeNamePattern = /[A-Za-z][A-Za-z0-9]*/

public enum NookletManifestError: Error, Equatable, LocalizedError {
    case malformed(String)
    case invalidIdentifier(String)
    case blankName
    case invalidProduct(String)

    public var errorDescription: String? {
        switch self {
        case .malformed(let reason):
            "\(manifestFileName) is not valid JSON with the fields id, name and product: \(reason)"
        case .invalidIdentifier(let id):
            "Nooklet id \"\(id)\" must be lowercase reverse-DNS, such as \"com.example.clock\"."
        case .blankName:
            "Nooklet name must not be blank."
        case .invalidProduct(let product):
            "Nooklet product \"\(product)\" must start with a letter and contain only letters and digits."
        }
    }
}
