import Foundation

let nookKitPackageIdentity = "nook"
let nookKitProductName = "NookKit"
let nookKitRemoteBranch = "main"
let packageManifestFileName = "Package.swift"
let entryFilePath = "Sources/app.swift"
let gitIgnoreFileName = ".gitignore"
let minimumMacOSVersion = "v14"

public enum NookKitDependency: Equatable, Sendable {
    case localPath(String)
    case remote(URL)

    public static func parse(_ value: String) throws -> NookKitDependency {
        if value.hasPrefix("/") {
            return .localPath(value)
        }
        guard let url = URL(string: value), url.scheme == "https", url.host() != nil else {
            throw NookletScaffoldError.invalidNookKitDependency(value)
        }
        return .remote(url)
    }

    var packageDeclaration: String {
        switch self {
        case .localPath(let path):
            ".package(path: \(swiftStringLiteral(path)))"
        case .remote(let url):
            ".package(url: \(swiftStringLiteral(url.absoluteString)), branch: \(swiftStringLiteral(nookKitRemoteBranch)))"
        }
    }
}

public func makeProductName(from displayName: String) throws -> String {
    let words = displayName.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
    let productName = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    guard productName.wholeMatch(of: swiftTypeNamePattern) != nil else {
        throw NookletScaffoldError.unusableName(displayName)
    }
    return productName
}

public func makeTemplateFiles(for manifest: NookletManifest, dependency: NookKitDependency) -> [String: String] {
    [
        manifestFileName: makeManifestFile(for: manifest),
        packageManifestFileName: makePackageManifestFile(for: manifest, dependency: dependency),
        entryFilePath: makeEntryFile(for: manifest),
        gitIgnoreFileName: ".build/\n.swiftpm/\n.DS_Store\n",
    ]
}

public func scaffoldNooklet(_ manifest: NookletManifest, dependency: NookKitDependency, in directory: URL) throws {
    let fileManager = FileManager.default
    let occupiedPaths = [manifestFileName, packageManifestFileName].map { directory.appending(path: $0).path }
    guard !occupiedPaths.contains(where: fileManager.fileExists(atPath:)) else {
        throw NookletScaffoldError.directoryNotEmpty(directory.path)
    }
    for (relativePath, contents) in makeTemplateFiles(for: manifest, dependency: dependency) {
        let fileURL = directory.appending(path: relativePath)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: fileURL)
    }
}

private func makeManifestFile(for manifest: NookletManifest) -> String {
    let fields = [("id", manifest.id), ("name", manifest.name), ("product", manifest.product)]
    let lines = fields.map { "  \(swiftStringLiteral($0.0)): \(swiftStringLiteral($0.1))" }
    return "{\n" + lines.joined(separator: ",\n") + "\n}\n"
}

private func makePackageManifestFile(for manifest: NookletManifest, dependency: NookKitDependency) -> String {
    let product = swiftStringLiteral(manifest.product)
    return """
    // swift-tools-version: 6.0
    import PackageDescription

    let package = Package(
        name: \(product),
        platforms: [.macOS(.\(minimumMacOSVersion))],
        dependencies: [\(dependency.packageDeclaration)],
        targets: [
            .executableTarget(name: \(product), dependencies: [.product(name: \(swiftStringLiteral(nookKitProductName)), package: \(swiftStringLiteral(nookKitPackageIdentity)))], path: "Sources"),
        ]
    )

    """
}

private func makeEntryFile(for manifest: NookletManifest) -> String {
    """
    import NookKit
    import SwiftUI

    @main
    struct \(manifest.product): Nooklet {
        var body: some NookScene {
            FloatingPanel {
                Text(\(swiftStringLiteral(manifest.name)))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    """
}

private func swiftStringLiteral(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
}

public enum NookletScaffoldError: Error, Equatable, LocalizedError {
    case unusableName(String)
    case invalidNookKitDependency(String)
    case directoryNotEmpty(String)

    public var errorDescription: String? {
        switch self {
        case .unusableName(let name):
            "Nooklet name \"\(name)\" must start with an ASCII letter to become a Swift type name."
        case .invalidNookKitDependency(let value):
            "NookKit package location \"\(value)\" must be an absolute path or an https git URL."
        case .directoryNotEmpty(let path):
            "\(path) already contains \(manifestFileName) or \(packageManifestFileName); choose an empty folder."
        }
    }
}
