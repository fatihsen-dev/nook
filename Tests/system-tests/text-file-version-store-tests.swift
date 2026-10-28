import Foundation
import Testing
@testable import NookSystem

struct TextFileVersionStoreTests {
    @Test func savedVersionLoadsBackAndMissingFileIsNil() throws {
        let store = TextFileVersionStore(file: try makeScratchDirectory().appending(path: "nook/nookkit-version"))
        #expect(try store.load() == nil)
        try store.save("0.1.5")
        #expect(try store.load() == "0.1.5")
    }
}
