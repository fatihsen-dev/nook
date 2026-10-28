import Foundation
import Testing
@testable import NookCore

struct NookKitRefresherTests {
    let store = InMemoryLibraryStore()
    let builder = RecordingBuilder()
    let controller = RecordingServiceController()
    let versionStore = InMemoryVersionStore()

    var refresher: NookKitRefresher {
        let manager = NookletManager(
            store: store, builder: builder, controller: controller, inspector: FixedProcessInspector(), reportStore: InMemoryBuildReportStore(),
            logsDirectory: URL(filePath: "/tmp/nook-logs"),
            binariesDirectory: FileManager.default.temporaryDirectory.appending(path: "nook-bin-\(UUID().uuidString)"))
        return NookKitRefresher(manager: manager, builder: builder, versionStore: versionStore)
    }

    func addNooklet(_ id: String, isRunning: Bool) throws -> URL {
        let directory = try makeNookletFolder(id: id, name: id)
        try store.saveDirectories(store.directories + [directory])
        if isRunning { controller.states[serviceLabelPrefix + id] = .running(pid: 42) }
        return directory
    }

    @Test func newAppVersionUpdatesEveryNookletAndRestartsTheRunningOnes() async throws {
        let running = try addNooklet("com.example.clock", isRunning: true)
        let stopped = try addNooklet("com.example.dock", isRunning: false)
        let failures = try await refresher.refreshIfNeeded(appVersion: "0.1.5")
        #expect(failures.isEmpty)
        #expect(Set(builder.dependencyUpdates) == [running, stopped])
        #expect(controller.started.map(\.label) == [serviceLabelPrefix + "com.example.clock"])
        #expect(versionStore.version == "0.1.5")
    }

    @Test func sameAppVersionDoesNothing() async throws {
        _ = try addNooklet("com.example.clock", isRunning: true)
        versionStore.version = "0.1.5"
        _ = try await refresher.refreshIfNeeded(appVersion: "0.1.5")
        #expect(builder.dependencyUpdates.isEmpty)
        #expect(controller.started.isEmpty)
    }

    @Test func failedDependencyUpdateIsReportedAndRetriedNextLaunch() async throws {
        _ = try addNooklet("com.example.clock", isRunning: true)
        builder.updateFailure = NookletLibraryError.unknownNooklet("offline")
        let failures = try await refresher.refreshIfNeeded(appVersion: "0.1.5")
        #expect(failures.map(\.nookletID) == ["com.example.clock"])
        #expect(versionStore.version == nil)
        #expect(controller.started.isEmpty)
    }

    @Test func failedRebuildIsReportedButNotRetried() async throws {
        _ = try addNooklet("com.example.clock", isRunning: true)
        builder.failureLog = "error: boom"
        let failures = try await refresher.refreshIfNeeded(appVersion: "0.1.5")
        #expect(failures.map(\.nookletID) == ["com.example.clock"])
        #expect(versionStore.version == "0.1.5")
    }
}

final class InMemoryVersionStore: NookKitVersionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var version: String? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func load() throws -> String? { version }
    func save(_ version: String) throws { self.version = version }
}
