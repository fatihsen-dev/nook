import CryptoKit
import Foundation
import NookCore

let downloadChunkSize = 64 * 1024
let checksumLength = 64

struct URLSessionUpdateDownloader: UpdateDownloader {
    let stagingDirectory: URL

    func download(_ archive: ReleaseArchive, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        let expected = try await expectedChecksum(at: archive.checksumURL)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let destination = stagingDirectory.appending(path: archive.url.lastPathComponent)
        let actual = try await save(archive.url, to: destination, progress: progress)
        guard actual == expected else {
            try FileManager.default.removeItem(at: destination)
            throw AppUpdateError.checksumMismatch(expected: expected, actual: actual)
        }
        return destination
    }

    private func expectedChecksum(at url: URL) async throws -> String {
        let text = String(decoding: try await fetch(url), as: UTF8.self)
        let value = text.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased() ?? ""
        guard value.count == checksumLength, value.allSatisfy(\.isHexDigit) else {
            throw AppUpdateError.unreadableChecksum(text)
        }
        return value
    }

    private func save(_ url: URL, to destination: URL, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> String {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        try requireSuccess(response, for: url)
        let total = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        var hasher = SHA256()
        var buffer = Data(capacity: downloadChunkSize)
        var received: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            guard buffer.count == downloadChunkSize else { continue }
            received += Int64(buffer.count)
            try write(&buffer, to: handle, hasher: &hasher)
            progress(DownloadProgress(receivedBytes: received, totalBytes: total))
        }
        received += Int64(buffer.count)
        try write(&buffer, to: handle, hasher: &hasher)
        try handle.close()
        progress(DownloadProgress(receivedBytes: received, totalBytes: total ?? received))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func write(_ buffer: inout Data, to handle: FileHandle, hasher: inout SHA256) throws {
        hasher.update(data: buffer)
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}
