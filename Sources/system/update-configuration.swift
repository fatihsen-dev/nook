import Foundation
import NookCore

let updateFeedVariable = "NOOK_UPDATE_FEED"
let updateFeedInfoKey = "NookUpdateFeed"
let bundleVersionInfoKey = "CFBundleShortVersionString"
let updateArchiveName = "Nook.zip"
let releaseHighlightLimit = 4
let updateStagingDirectoryName = "nook-update"
let dittoExecutable = URL(filePath: "/usr/bin/ditto")
let shellExecutable = URL(filePath: "/bin/sh")
let openExecutable = URL(filePath: "/usr/bin/open")
let relaunchPollSeconds = "0.2"

public struct UpdateConfiguration: Sendable {
    public let feed: URL
    public let currentVersion: AppVersion
    public let appBundle: URL
    public let bundleIdentifier: String

    public static func load(environment: [String: String], bundle: Bundle) throws -> UpdateConfiguration? {
        let info = bundle.infoDictionary ?? [:]
        guard let feedText = nonEmpty(environment[updateFeedVariable]) ?? nonEmpty(info[updateFeedInfoKey] as? String) else {
            return nil
        }
        guard let feed = URL(string: feedText), feed.scheme != nil else {
            throw UpdateConfigurationError.invalidFeed(feedText)
        }
        let versionText = info[bundleVersionInfoKey] as? String ?? ""
        guard let currentVersion = AppVersion(versionText) else {
            throw UpdateConfigurationError.invalidVersion(versionText)
        }
        guard let bundleIdentifier = bundle.bundleIdentifier else {
            throw UpdateConfigurationError.missingBundleIdentifier(bundle.bundleURL.path)
        }
        return UpdateConfiguration(feed: feed, currentVersion: currentVersion, appBundle: bundle.bundleURL, bundleIdentifier: bundleIdentifier)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

public enum UpdateConfigurationError: Error, Equatable, LocalizedError {
    case invalidFeed(String)
    case invalidVersion(String)
    case missingBundleIdentifier(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFeed(let text):
            "The update feed \(text) (\(updateFeedVariable) or \(updateFeedInfoKey)) is not a URL."
        case .invalidVersion(let text):
            "The app's \(bundleVersionInfoKey) \"\(text)\" is not a version number, so updates cannot be compared."
        case .missingBundleIdentifier(let path):
            "The app bundle at \(path) has no bundle identifier."
        }
    }
}

public func makeAppUpdater(configuration: UpdateConfiguration) -> AppUpdater {
    AppUpdater(
        currentVersion: configuration.currentVersion,
        source: GitHubReleaseSource(feed: configuration.feed, archiveName: updateArchiveName, highlightLimit: releaseHighlightLimit),
        downloader: URLSessionUpdateDownloader(stagingDirectory: FileManager.default.temporaryDirectory.appending(path: updateStagingDirectoryName)),
        replacer: InPlaceAppBundleReplacer(appBundle: configuration.appBundle, bundleIdentifier: configuration.bundleIdentifier, ditto: dittoExecutable))
}

public func currentAppSigningTeam() -> String? {
    currentSigningTeam()
}

public func scheduleRelaunch(of appBundle: URL) throws {
    let process = Process()
    process.executableURL = shellExecutable
    process.arguments = [
        "-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep \(relaunchPollSeconds); done; \"$2\" \"$3\"",
        "relaunch", String(ProcessInfo.processInfo.processIdentifier), openExecutable.path, appBundle.path,
    ]
    try process.run()
}
