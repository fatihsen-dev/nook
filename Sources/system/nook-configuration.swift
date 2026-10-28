import Foundation
import NookCore

let nookKitPackageVariable = "NOOK_KIT_PACKAGE"
let nookKitPackageInfoKey = "NookKitPackage"
let supportDirectoryName = "Nook"
let launchAgentsDirectoryName = "LaunchAgents"
let libraryFileName = "library.json"
let logsDirectoryName = "logs"
let binariesDirectoryName = "bin"
let buildsDirectoryName = "builds"
let xcrunExecutable = URL(filePath: "/usr/bin/xcrun")
let launchctlExecutable = URL(filePath: "/bin/launchctl")

public struct NookConfiguration: Sendable {
    public let nookKitDependency: NookKitDependency
    public let supportDirectory: URL
    public let launchAgentsDirectory: URL

    public static func load(environment: [String: String], bundleInfo: [String: Any]) throws -> NookConfiguration {
        guard let nookKitPackage = nonEmpty(environment[nookKitPackageVariable]) ?? nonEmpty(bundleInfo[nookKitPackageInfoKey] as? String) else {
            throw ConfigurationError.missingNookKitPackage
        }
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let library = try fileManager.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return NookConfiguration(
            nookKitDependency: try NookKitDependency.parse(nookKitPackage),
            supportDirectory: applicationSupport.appending(path: supportDirectoryName),
            launchAgentsDirectory: library.appending(path: launchAgentsDirectoryName))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

public enum ConfigurationError: Error, LocalizedError {
    case missingNookKitPackage

    public var errorDescription: String? {
        switch self {
        case .missingNookKitPackage:
            "No NookKit source is configured. Set the \(nookKitPackageVariable) environment variable to the absolute path of a nook checkout or to its https git URL, or run Nook from its app bundle, whose Info.plist sets \(nookKitPackageInfoKey)."
        }
    }
}

public func makeCodeEditor() -> CodeEditor {
    XcodeEditor(xcrun: xcrunExecutable)
}

public func makeNookletManager(configuration: NookConfiguration) -> NookletManager {
    NookletManager(
        store: JSONLibraryStore(fileURL: configuration.supportDirectory.appending(path: libraryFileName)),
        builder: SwiftPackageBuilder(xcrun: xcrunExecutable),
        controller: LaunchdServiceController(
            launchctl: launchctlExecutable,
            launchAgentsDirectory: configuration.launchAgentsDirectory,
            userID: getuid()),
        inspector: LibprocProcessInspector(),
        reportStore: JSONBuildReportStore(directory: configuration.supportDirectory.appending(path: buildsDirectoryName)),
        logsDirectory: configuration.supportDirectory.appending(path: logsDirectoryName),
        binariesDirectory: configuration.supportDirectory.appending(path: binariesDirectoryName))
}
