import Foundation
import Testing
@testable import NookCore

struct NookletManagerTests {
    let store = InMemoryLibraryStore()
    let builder = RecordingBuilder()
    let controller = RecordingServiceController()
    let inspector = FixedProcessInspector()
    let reportStore = InMemoryBuildReportStore()
    let logsDirectory = URL(filePath: "/tmp/nook-logs")
    let binariesDirectory = FileManager.default.temporaryDirectory.appending(path: "nook-bin-\(UUID().uuidString)")

    var manager: NookletManager {
        NookletManager(store: store, builder: builder, controller: controller, inspector: inspector, reportStore: reportStore, logsDirectory: logsDirectory, binariesDirectory: binariesDirectory)
    }

    @Test func addingFolderRegistersItAndReturnsManifest() throws {
        let directory = try makeNookletFolder(id: "com.example.clock", name: "Clock")
        let nooklet = try manager.addNooklet(at: directory)
        #expect(nooklet.manifest.id == "com.example.clock")
        #expect(store.directories == [directory])
    }

    @Test func addingFolderWithoutManifestFails() throws {
        let directory = try makeTemporaryDirectory()
        #expect(throws: NookletLibraryError.missingManifest(directory.path)) {
            try manager.addNooklet(at: directory)
        }
        #expect(store.directories.isEmpty)
    }

    @Test func addingSecondNookletWithSameIdentifierFails() throws {
        try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        let duplicate = try makeNookletFolder(id: "com.example.clock", name: "Other Clock")
        #expect(throws: NookletLibraryError.duplicateIdentifier("com.example.clock")) {
            try manager.addNooklet(at: duplicate)
        }
    }

    @Test func listingReportsFolderWhoseManifestDisappeared() throws {
        let directory = try makeNookletFolder(id: "com.example.clock", name: "Clock")
        try manager.addNooklet(at: directory)
        try FileManager.default.removeItem(at: directory.appending(path: manifestFileName))
        let entries = try manager.libraryEntries()
        guard case .broken(let brokenDirectory, _) = entries.first else {
            Issue.record("expected a broken entry, got \(entries)")
            return
        }
        #expect(brokenDirectory == directory)
    }

    @Test func creatingNookletScaffoldsFolderWithDerivedProductAndRegistersIt() throws {
        let directory = try makeTemporaryDirectory()
        let nooklet = try manager.createNooklet(
            named: "Now Playing", id: "com.example.now-playing", in: directory, dependency: .localPath("/n"))
        #expect(nooklet.manifest == NookletManifest(id: "com.example.now-playing", name: "Now Playing", product: "NowPlaying"))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "Package.swift").path))
        #expect(store.directories == [directory])
    }

    @Test func creatingNookletWithInvalidIdentifierWritesNothing() throws {
        let directory = try makeTemporaryDirectory()
        #expect(throws: NookletManifestError.invalidIdentifier("Clock")) {
            try manager.createNooklet(named: "Clock", id: "Clock", in: directory, dependency: .localPath("/n"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func runningBuildsThenStartsServiceForExecutable() async throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        let report = try await manager.run(nooklet)
        #expect(report.isSuccess)
        #expect(report.log == "Build complete!")
        #expect(builder.builtProducts == ["Clock"])
        let installed = binariesDirectory.appending(path: "com.example.clock/Clock")
        #expect(controller.started == [
            BackgroundService(
                label: "dev.nook.nooklet.com.example.clock",
                executable: installed,
                logFile: logsDirectory.appending(path: "com.example.clock.log"))
        ])
        #expect(try Data(contentsOf: installed) == Data("binary for Clock".utf8))
    }

    @Test func runningCopiesResourceBundlesNextToInstalledExecutable() async throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        builder.resourceBundleName = "Clock_Clock.bundle"
        _ = try await manager.run(nooklet)
        let bundle = binariesDirectory.appending(path: "com.example.clock/Clock_Clock.bundle/asset.txt")
        #expect(FileManager.default.fileExists(atPath: bundle.path))
    }

    @Test func rebuildingReplacesInstalledExecutable() async throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        _ = try await manager.run(nooklet)
        builder.binaryContents = "second build"
        _ = try await manager.run(nooklet)
        let installed = binariesDirectory.appending(path: "com.example.clock/Clock")
        #expect(try Data(contentsOf: installed) == Data("second build".utf8))
    }

    @Test func failedBuildIsReportedWithDiagnosticsAndStartsNothing() async throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        builder.failureLog = "/a/app.swift:2:5: error: boom"
        let report = try await manager.run(nooklet)
        #expect(!report.isSuccess)
        #expect(report.diagnostics == [BuildDiagnostic(file: URL(filePath: "/a/app.swift"), line: 2, column: 5, message: "boom")])
        #expect(controller.started.isEmpty)
    }

    @Test func buildingCompilesAndRecordsReportWithoutInstallingOrStarting() async throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        let report = try await manager.build(nooklet)
        #expect(report.isSuccess)
        #expect(builder.builtProducts == ["Clock"])
        #expect(controller.started.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: binariesDirectory.appending(path: "com.example.clock").path))
        #expect(try manager.lastBuildReport(of: nooklet) == report)
    }

    @Test func failedBuildReportsDiagnostics() async throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        builder.failureLog = "/a/app.swift:2:5: error: boom"
        let report = try await manager.build(nooklet)
        #expect(!report.isSuccess)
        #expect(report.diagnostics == [BuildDiagnostic(file: URL(filePath: "/a/app.swift"), line: 2, column: 5, message: "boom")])
    }

    @Test func findingNookletByIdentifier() throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        #expect(try manager.nooklet(matching: "com.example.clock", workingDirectory: URL(filePath: "/")) == nooklet)
    }

    @Test func findingNookletByAbsoluteOrRelativeFolder() throws {
        let directory = try makeNookletFolder(id: "com.example.clock", name: "Clock")
        let nooklet = try manager.addNooklet(at: directory)
        #expect(try manager.nooklet(matching: directory.path, workingDirectory: URL(filePath: "/")) == nooklet)
        let parent = directory.deletingLastPathComponent()
        #expect(try manager.nooklet(matching: directory.lastPathComponent + "/", workingDirectory: parent) == nooklet)
        #expect(try manager.nooklet(matching: ".", workingDirectory: directory) == nooklet)
    }

    @Test func findingUnknownNookletFails() throws {
        try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        #expect(throws: NookletLibraryError.unknownNooklet("com.example.timer")) {
            try manager.nooklet(matching: "com.example.timer", workingDirectory: URL(filePath: "/"))
        }
    }

    @Test func findingBrokenNookletReportsWhy() throws {
        let directory = try makeNookletFolder(id: "com.example.clock", name: "Clock")
        try manager.addNooklet(at: directory)
        try FileManager.default.removeItem(at: directory.appending(path: manifestFileName))
        #expect(throws: NookletLibraryError.brokenNooklet(directory.path, reason: NookletLibraryError.missingManifest(directory.path).localizedDescription)) {
            try manager.nooklet(matching: directory.path, workingDirectory: URL(filePath: "/"))
        }
        #expect(try manager.libraryDirectory(matching: directory.path, workingDirectory: URL(filePath: "/")) == directory)
    }

    @Test func stoppingStopsServiceLabel() async throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        try await manager.stop(nooklet)
        #expect(controller.stopped == ["dev.nook.nooklet.com.example.clock"])
    }

    @Test func removingStopsServiceAndUnregistersFolder() async throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        try await manager.remove(nooklet.directory)
        #expect(controller.stopped == ["dev.nook.nooklet.com.example.clock"])
        #expect(store.directories.isEmpty)
    }

    @Test func stoppedServiceHasNoRuntimeDetails() async throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        #expect(try await manager.runtime(of: nooklet) == .stopped)
    }

    @Test func runningServiceReportsProcessMetrics() async throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        controller.states = ["dev.nook.nooklet.com.example.clock": .running(pid: 42)]
        let metrics = ProcessMetrics(memoryBytes: 14_000_000, startDate: Date(timeIntervalSince1970: 100))
        inspector.metricsByPID = [42: metrics]
        #expect(try await manager.runtime(of: nooklet) == .running(pid: 42, metrics: metrics))
    }

    @Test func recentLogReadsNookletLogFile() async throws {
        let logs = try makeTemporaryDirectory()
        let nooklet = try NookletManager(store: store, builder: builder, controller: controller, inspector: inspector, reportStore: reportStore, logsDirectory: logs, binariesDirectory: binariesDirectory)
            .addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        try Data("a\nb\n".utf8).write(to: logs.appending(path: "com.example.clock.log"))
        let reader = NookletManager(store: store, builder: builder, controller: controller, inspector: inspector, reportStore: reportStore, logsDirectory: logs, binariesDirectory: binariesDirectory)
        #expect(try reader.recentLog(of: nooklet, lineLimit: 5) == ["a", "b"])
    }

    @Test func lastBuildReportSurvivesNewManagerInstance() async throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        builder.failureLog = "/a/app.swift:2:5: error: boom"
        let report = try await manager.run(nooklet)
        let restarted = NookletManager(store: store, builder: builder, controller: controller, inspector: inspector, reportStore: reportStore, logsDirectory: logsDirectory, binariesDirectory: binariesDirectory)
        #expect(try restarted.lastBuildReport(of: nooklet) == report)
    }

    @Test func nookletWithoutBuildHasNoReport() throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        #expect(try manager.lastBuildReport(of: nooklet) == nil)
    }

    @Test func removingNookletDeletesItsBuildReport() async throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        _ = try await manager.run(nooklet)
        try await manager.remove(nooklet.directory)
        #expect(reportStore.reports.isEmpty)
    }

    @Test func removingNookletDeletesItsLogAndInstalledBinary() async throws {
        let logs = try makeTemporaryDirectory()
        let manager = NookletManager(store: store, builder: builder, controller: controller, inspector: inspector, reportStore: reportStore, logsDirectory: logs, binariesDirectory: binariesDirectory)
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        _ = try await manager.run(nooklet)
        try Data("old line\n".utf8).write(to: logs.appending(path: "com.example.clock.log"))
        try await manager.remove(nooklet.directory)
        #expect(!FileManager.default.fileExists(atPath: logs.appending(path: "com.example.clock.log").path))
        #expect(!FileManager.default.fileExists(atPath: binariesDirectory.appending(path: "com.example.clock").path))
    }

    @Test func removingNookletKeepsItsSourceFolder() async throws {
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        try await manager.remove(nooklet.directory)
        #expect(FileManager.default.fileExists(atPath: nooklet.directory.appending(path: manifestFileName).path))
    }

    @Test func clearingLogEmptiesNookletLogFile() async throws {
        let logs = try makeTemporaryDirectory()
        let manager = NookletManager(store: store, builder: builder, controller: controller, inspector: inspector, reportStore: reportStore, logsDirectory: logs, binariesDirectory: binariesDirectory)
        let nooklet = try manager.addNooklet(at: makeNookletFolder(id: "com.example.clock", name: "Clock"))
        try Data("a\nb\n".utf8).write(to: logs.appending(path: "com.example.clock.log"))
        try manager.clearLog(of: nooklet)
        #expect(try manager.recentLog(of: nooklet, lineLimit: 5).isEmpty)
    }
}

func makeNookletFolder(id: String, name: String) throws -> URL {
    let directory = try makeTemporaryDirectory()
    let manifest = NookletManifest(id: id, name: name, product: try makeProductName(from: name))
    try manifest.encoded().write(to: directory.appending(path: manifestFileName))
    return directory
}

final class InMemoryLibraryStore: NookletLibraryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedDirectories: [URL] = []

    var directories: [URL] { lock.withLock { storedDirectories } }

    func loadDirectories() throws -> [URL] { directories }

    func saveDirectories(_ directories: [URL]) throws {
        lock.withLock { storedDirectories = directories }
    }
}

final class RecordingBuilder: NookletBuilder, @unchecked Sendable {
    private let lock = NSLock()
    private var products: [String] = []
    private var storedFailureLog: String?
    private var storedContents: String?
    private var storedBundleName: String?

    var builtProducts: [String] { lock.withLock { products } }
    var failureLog: String? {
        get { lock.withLock { storedFailureLog } }
        set { lock.withLock { storedFailureLog = newValue } }
    }
    var binaryContents: String? {
        get { lock.withLock { storedContents } }
        set { lock.withLock { storedContents = newValue } }
    }
    var resourceBundleName: String? {
        get { lock.withLock { storedBundleName } }
        set { lock.withLock { storedBundleName = newValue } }
    }

    func build(product: String, packageDirectory: URL) async throws -> BuildOutcome {
        if let failureLog { return .failed(log: failureLog) }
        lock.withLock { products.append(product) }
        let binDirectory = packageDirectory.appending(path: ".build/release")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let executable = binDirectory.appending(path: product)
        try Data((binaryContents ?? "binary for \(product)").utf8).write(to: executable)
        if let resourceBundleName {
            let bundle = binDirectory.appending(path: resourceBundleName)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data("asset".utf8).write(to: bundle.appending(path: "asset.txt"))
        }
        return .succeeded(executable: executable, log: "Build complete!")
    }

    func toolchainVersion() async throws -> String { "6.4" }
}

final class RecordingServiceController: BackgroundServiceController, @unchecked Sendable {
    private let lock = NSLock()
    private var startedServices: [BackgroundService] = []
    private var stoppedLabels: [String] = []
    private var storedStates: [String: ServiceState] = [:]

    var started: [BackgroundService] { lock.withLock { startedServices } }
    var stopped: [String] { lock.withLock { stoppedLabels } }
    var states: [String: ServiceState] {
        get { lock.withLock { storedStates } }
        set { lock.withLock { storedStates = newValue } }
    }

    func start(_ service: BackgroundService) async throws {
        lock.withLock { startedServices.append(service) }
    }

    func stop(label: String) async throws {
        lock.withLock { stoppedLabels.append(label) }
    }

    func state(label: String) async throws -> ServiceState {
        states[label] ?? .stopped
    }
}

final class FixedProcessInspector: ProcessInspector, @unchecked Sendable {
    private let lock = NSLock()
    private var storedMetrics: [Int32: ProcessMetrics] = [:]

    var metricsByPID: [Int32: ProcessMetrics] {
        get { lock.withLock { storedMetrics } }
        set { lock.withLock { storedMetrics = newValue } }
    }

    func metrics(pid: Int32) throws -> ProcessMetrics? { metricsByPID[pid] }
}

final class InMemoryBuildReportStore: BuildReportStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedReports: [String: BuildReport] = [:]

    var reports: [String: BuildReport] { lock.withLock { storedReports } }

    func load(nookletID: String) throws -> BuildReport? { reports[nookletID] }

    func save(_ report: BuildReport, nookletID: String) throws {
        lock.withLock { storedReports[nookletID] = report }
    }

    func delete(nookletID: String) throws {
        lock.withLock { storedReports[nookletID] = nil }
    }
}
