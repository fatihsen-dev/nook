import Foundation
import Testing
@testable import NookCore

struct NookKitUpdaterTests {
    let store = InMemoryLibraryStore()
    let builder = RecordingBuilder()
    let controller = RecordingServiceController()
    let syncStore = InMemorySyncStore()
    let url = URL(string: "https://github.com/me/nook")!
    let binaries = FileManager.default.temporaryDirectory.appending(path: "nook-bin-\(UUID().uuidString)")

    func makeManager(version: String = "0.1.6") -> NookletManager {
        NookletManager(
            store: store, builder: builder, controller: controller, inspector: FixedProcessInspector(), reportStore: InMemoryBuildReportStore(),
            logsDirectory: URL(filePath: "/tmp/nook-logs"), binariesDirectory: binaries,
            kitUpdater: NookKitUpdater(url: url, version: AppVersion(version)!, builder: builder, store: syncStore))
    }

    func addRemoteNooklet(_ id: String, dependencyLine: String? = nil) throws -> InstalledNooklet {
        let directory = try makeNookletFolder(id: id, name: id)
        let line = dependencyLine ?? #".package(url: "https://github.com/me/nook", branch: "main")"#
        try Data("let package = Package(dependencies: [\(line)])\n".utf8).write(to: directory.appending(path: "Package.swift"))
        try store.saveDirectories(store.directories + [directory])
        return InstalledNooklet(directory: directory, manifest: try readManifest(in: directory))
    }

    @Test func nookletNeverSyncedWithThisVersionIsOutdated() throws {
        let nooklet = try addRemoteNooklet("com.example.clock")
        #expect(try makeManager().isNookKitOutdated(nooklet))
        syncStore.versions = ["com.example.clock": "0.1.6"]
        #expect(try !makeManager().isNookKitOutdated(nooklet))
    }

    @Test func nookletWithALocalNookKitIsNeverOutdated() throws {
        let nooklet = try addRemoteNooklet("com.example.clock", dependencyLine: #".package(path: "/Users/me/nook")"#)
        #expect(try !makeManager().isNookKitOutdated(nooklet))
    }

    @Test func runUpdatesAnOutdatedNookletFirstAndPinsItsDependency() async throws {
        let nooklet = try addRemoteNooklet("com.example.clock")
        _ = try await makeManager().run(nooklet)
        #expect(builder.dependencyUpdates == [nooklet.directory])
        let package = try String(contentsOf: nooklet.directory.appending(path: "Package.swift"), encoding: .utf8)
        #expect(package.contains(#".package(url: "https://github.com/me/nook", from: "0.1.6")"#))
        #expect(syncStore.versions["com.example.clock"] == "0.1.6")
    }

    @Test func runOfAnUpToDateNookletSkipsTheUpdate() async throws {
        let nooklet = try addRemoteNooklet("com.example.clock")
        syncStore.versions = ["com.example.clock": "0.1.6"]
        _ = try await makeManager().run(nooklet)
        #expect(builder.dependencyUpdates.isEmpty)
    }

    @Test func failedUpdateStopsTheRunAndIsNotRecorded() async throws {
        let nooklet = try addRemoteNooklet("com.example.clock")
        builder.updateFailure = NookletLibraryError.unknownNooklet("offline")
        await #expect(throws: NookletLibraryError.unknownNooklet("offline")) {
            _ = try await makeManager().run(nooklet)
        }
        #expect(builder.builtProducts.isEmpty)
        #expect(syncStore.versions["com.example.clock"] == nil)
    }

    @Test func createdNookletStartsUpToDate() throws {
        let directory = try makeTemporaryDirectory()
        let nooklet = try makeManager().createNooklet(named: "Clock", id: "com.example.clock", in: directory, dependency: .remote(url, version: AppVersion("0.1.6")!))
        #expect(try !makeManager().isNookKitOutdated(nooklet))
    }

    @Test func removedNookletIsForgotten() async throws {
        let nooklet = try addRemoteNooklet("com.example.clock")
        syncStore.versions = ["com.example.clock": "0.1.6"]
        try await makeManager().remove(nooklet.directory)
        #expect(syncStore.versions["com.example.clock"] == nil)
    }
}

final class InMemorySyncStore: NookKitSyncStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: String] = [:]

    var versions: [String: String] {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func load() throws -> [String: String] { versions }
    func save(_ versions: [String: String]) throws { self.versions = versions }
}
