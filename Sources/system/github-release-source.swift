import Foundation
import NookCore

let checksumFileSuffix = ".sha256"
let successfulHTTPStatus = 200

struct GitHubReleaseSource: ReleaseSource {
    let feed: URL
    let archiveName: String
    let highlightLimit: Int

    func latestRelease() async throws -> AppRelease {
        let data = try await fetch(feed)
        return try parseRelease(data)
    }

    func parseRelease(_ data: Data) throws -> AppRelease {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let version = AppVersion(release.tagName) else {
            throw AppUpdateError.invalidReleaseVersion(release.tagName)
        }
        let checksumName = archiveName + checksumFileSuffix
        guard let archive = release.assets.first(where: { $0.name == archiveName }) else {
            throw AppUpdateError.missingAsset(archiveName)
        }
        guard let checksum = release.assets.first(where: { $0.name == checksumName }) else {
            throw AppUpdateError.missingAsset(checksumName)
        }
        return AppRelease(
            version: version,
            highlights: releaseHighlights(in: release.body ?? "", limit: highlightLimit),
            page: release.htmlURL,
            archive: ReleaseArchive(url: archive.downloadURL, checksumURL: checksum.downloadURL))
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let htmlURL: URL
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let downloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
    }
}

func fetch(_ url: URL) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(from: url)
    try requireSuccess(response, for: url)
    return data
}

func requireSuccess(_ response: URLResponse, for url: URL) throws {
    guard let http = response as? HTTPURLResponse else { return }
    guard http.statusCode == successfulHTTPStatus else {
        throw AppUpdateError.downloadFailed(url.absoluteString, http.statusCode)
    }
}
