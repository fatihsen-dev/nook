import Foundation
import Testing
@testable import NookSystem

struct JSONNookKitSyncStoreTests {
    @Test func savedVersionsLoadBackAndAMissingFileIsEmpty() throws {
        let store = JSONNookKitSyncStore(file: try makeScratchDirectory().appending(path: "nook/nookkit-versions.json"))
        #expect(try store.load().isEmpty)
        try store.save(["com.example.clock": "0.1.6"])
        #expect(try store.load() == ["com.example.clock": "0.1.6"])
    }

    @Test func corruptFileIsReportedWithItsPath() throws {
        let file = try makeScratchDirectory().appending(path: "nookkit-versions.json")
        try Data("nope".utf8).write(to: file)
        #expect(throws: JSONNookKitSyncStoreError.self) { try JSONNookKitSyncStore(file: file).load() }
    }
}
