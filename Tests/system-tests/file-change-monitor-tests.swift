import Foundation
import Testing
@testable import NookSystem

struct FileChangeMonitorTests {
    @Test func reportsAppendedLines() async throws {
        let file = try makeScratchDirectory().appending(path: "nooklet.log")
        try Data("first\n".utf8).write(to: file)
        try await confirmation(expectedCount: 1...) { changed in
            let monitor = try FileChangeMonitor(file: file, queue: .global()) { changed() }
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("second\n".utf8))
            try handle.close()
            try await Task.sleep(for: .milliseconds(300))
            withExtendedLifetime(monitor) {}
        }
    }

    @Test func missingFileIsReportedWithItsPath() throws {
        let file = try makeScratchDirectory().appending(path: "missing.log")
        #expect(throws: FileChangeMonitorError.cannotOpen(file.path)) {
            try FileChangeMonitor(file: file, queue: .global()) {}
        }
    }
}
