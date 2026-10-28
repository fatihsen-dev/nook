import Foundation

let versionTagPrefix = "v"
let versionComponentCount = 3
let preReleaseSeparator: Character = "-"
let releaseNoteBulletPrefixes = ["- ", "* "]

public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let numbers: [Int]
    let preRelease: String?

    public init?(_ text: String) {
        let trimmed = text.hasPrefix(versionTagPrefix) ? String(text.dropFirst(versionTagPrefix.count)) : text
        let parts = trimmed.split(separator: preReleaseSeparator, maxSplits: 1)
        guard let core = parts.first else { return nil }
        let components = core.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = components.compactMap { Int($0) }
        guard components.count == versionComponentCount, numbers.count == versionComponentCount else {
            return nil
        }
        self.numbers = numbers
        self.preRelease = parts.count > 1 ? String(parts[1]) : nil
    }

    public var description: String {
        let core = numbers.map(String.init).joined(separator: ".")
        return preRelease.map { "\(core)\(preReleaseSeparator)\($0)" } ?? core
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.numbers != rhs.numbers {
            return lhs.numbers.lexicographicallyPrecedes(rhs.numbers)
        }
        switch (lhs.preRelease, rhs.preRelease) {
        case (.some(let left), .some(let right)): return left.compare(right, options: .numeric) == .orderedAscending
        case (.some, nil): return true
        default: return false
        }
    }
}

public struct ReleaseArchive: Equatable, Sendable {
    public let url: URL
    public let checksumURL: URL

    public init(url: URL, checksumURL: URL) {
        self.url = url
        self.checksumURL = checksumURL
    }
}

public struct AppRelease: Equatable, Sendable {
    public let version: AppVersion
    public let highlights: [String]
    public let page: URL
    public let archive: ReleaseArchive

    public init(version: AppVersion, highlights: [String], page: URL, archive: ReleaseArchive) {
        self.version = version
        self.highlights = highlights
        self.page = page
        self.archive = archive
    }
}

public struct DownloadProgress: Equatable, Sendable {
    public let receivedBytes: Int64
    public let totalBytes: Int64?

    public init(receivedBytes: Int64, totalBytes: Int64?) {
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
    }

    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(totalBytes))
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate
    case skipped
    case available(AppRelease)
}

public enum AppUpdateError: Error, Equatable, LocalizedError {
    case notReplaceableInPlace
    case checksumMismatch(expected: String, actual: String)
    case unreadableChecksum(String)
    case missingAsset(String)
    case invalidReleaseVersion(String)
    case downloadFailed(String, Int)
    case unsignedCurrentCopy
    case untrustedSignature(String)
    case missingAppInArchive(String)
    case unpackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notReplaceableInPlace:
            "Nook is running from a location it cannot replace itself in."
        case .checksumMismatch(let expected, let actual):
            "The download does not match its checksum (expected \(expected), got \(actual))."
        case .unreadableChecksum(let text):
            "The release checksum file is not a SHA-256 value: \(text)"
        case .missingAsset(let name):
            "The latest release has no \(name) file."
        case .invalidReleaseVersion(let tag):
            "The latest release tag \(tag) is not a version number."
        case .downloadFailed(let url, let status):
            "Downloading \(url) failed with HTTP status \(status)."
        case .unsignedCurrentCopy:
            "This copy of Nook is not signed with a Developer ID, so it cannot verify updates."
        case .untrustedSignature(let reason):
            "The download is not signed by the Nook developer: \(reason)"
        case .missingAppInArchive(let name):
            "The download does not contain \(name)."
        case .unpackFailed(let output):
            "The download could not be unpacked: \(output)"
        }
    }
}

public protocol ReleaseSource: Sendable {
    func latestRelease() async throws -> AppRelease
}

public protocol UpdateDownloader: Sendable {
    func download(_ archive: ReleaseArchive, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL
}

public protocol AppBundleReplacer: Sendable {
    var canReplaceInPlace: Bool { get }
    func replace(withArchive archive: URL) async throws
}

public func releaseHighlights(in body: String, limit: Int) -> [String] {
    let bullets = body.split(whereSeparator: \.isNewline).compactMap { line -> String? in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let prefix = releaseNoteBulletPrefixes.first(where: trimmed.hasPrefix) else { return nil }
        let text = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
    return Array(bullets.prefix(limit))
}

public struct AppUpdater: Sendable {
    public let currentVersion: AppVersion
    let source: ReleaseSource
    let downloader: UpdateDownloader
    let replacer: AppBundleReplacer

    public init(currentVersion: AppVersion, source: ReleaseSource, downloader: UpdateDownloader, replacer: AppBundleReplacer) {
        self.currentVersion = currentVersion
        self.source = source
        self.downloader = downloader
        self.replacer = replacer
    }

    public var canReplaceInPlace: Bool { replacer.canReplaceInPlace }

    public func check(skipping skippedVersion: AppVersion?) async throws -> UpdateCheckResult {
        let release = try await source.latestRelease()
        guard release.version > currentVersion else { return .upToDate }
        guard release.version != skippedVersion else { return .skipped }
        return .available(release)
    }

    public func install(_ release: AppRelease, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        guard replacer.canReplaceInPlace else { throw AppUpdateError.notReplaceableInPlace }
        let archive = try await downloader.download(release.archive, progress: progress)
        try Task.checkCancellation()
        try await replacer.replace(withArchive: archive)
    }
}
