import Foundation
import Testing
@testable import NookCore

struct NookletManifestTests {
    @Test func decodesValidManifest() throws {
        let json = #"{"id": "com.example.clock", "name": "Clock", "product": "Clock"}"#
        let manifest = try NookletManifest.decode(from: Data(json.utf8))
        #expect(manifest == NookletManifest(id: "com.example.clock", name: "Clock", product: "Clock"))
    }

    @Test func rejectsIdentifierWithoutReverseDomainSegments() {
        let json = #"{"id": "clock", "name": "Clock", "product": "Clock"}"#
        #expect(throws: NookletManifestError.invalidIdentifier("clock")) {
            try NookletManifest.decode(from: Data(json.utf8))
        }
    }

    @Test func rejectsUppercaseIdentifier() {
        let json = #"{"id": "com.Example.clock", "name": "Clock", "product": "Clock"}"#
        #expect(throws: NookletManifestError.invalidIdentifier("com.Example.clock")) {
            try NookletManifest.decode(from: Data(json.utf8))
        }
    }

    @Test func rejectsBlankName() {
        let json = #"{"id": "com.example.clock", "name": "  ", "product": "Clock"}"#
        #expect(throws: NookletManifestError.blankName) {
            try NookletManifest.decode(from: Data(json.utf8))
        }
    }

    @Test func rejectsProductThatIsNotASwiftIdentifier() {
        let json = #"{"id": "com.example.clock", "name": "Clock", "product": "my-clock"}"#
        #expect(throws: NookletManifestError.invalidProduct("my-clock")) {
            try NookletManifest.decode(from: Data(json.utf8))
        }
    }

    @Test func reportsMalformedJSON() {
        #expect(throws: NookletManifestError.self) {
            try NookletManifest.decode(from: Data("{".utf8))
        }
    }

    @Test func encodingRoundTrips() throws {
        let manifest = NookletManifest(id: "com.example.clock", name: "Clock", product: "Clock")
        #expect(try NookletManifest.decode(from: manifest.encoded()) == manifest)
    }
}
