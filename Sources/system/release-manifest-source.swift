import Foundation
import NookCore

let successfulHTTPStatus = 200
let rateLimitStatuses: Set<Int> = [403, 429]

struct ReleaseManifestSource: ReleaseSource {
    let feed: URL
    let highlightLimit: Int

    func latestRelease() async throws -> AppRelease {
        try parseManifest(try await fetch(feed))
    }

    func parseManifest(_ data: Data) throws -> AppRelease {
        let manifest: ReleaseManifest
        do {
            manifest = try JSONDecoder().decode(ReleaseManifest.self, from: data)
        } catch {
            throw AppUpdateError.unreadableManifest(feed.absoluteString, error.localizedDescription)
        }
        guard let version = AppVersion(manifest.version) else {
            throw AppUpdateError.invalidReleaseVersion(manifest.version)
        }
        return AppRelease(
            version: version,
            highlights: releaseHighlights(in: manifest.notes, limit: highlightLimit),
            page: manifest.page,
            archive: ReleaseArchive(url: manifest.archive, checksumURL: manifest.checksum))
    }
}

private struct ReleaseManifest: Decodable {
    let version: String
    let notes: String
    let page: URL
    let archive: URL
    let checksum: URL
}

func fetch(_ url: URL) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(from: url)
    try requireSuccess(response, for: url)
    return data
}

func requireSuccess(_ response: URLResponse, for url: URL) throws {
    guard let http = response as? HTTPURLResponse else { return }
    guard http.statusCode == successfulHTTPStatus else {
        if rateLimitStatuses.contains(http.statusCode) {
            throw AppUpdateError.rateLimited(url.host() ?? url.absoluteString)
        }
        throw AppUpdateError.downloadFailed(url.absoluteString, http.statusCode)
    }
}
