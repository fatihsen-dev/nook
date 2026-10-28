import Foundation

let serviceLabelPrefix = "dev.nook.nooklet."
let resourceBundleExtension = "bundle"
let stagingSuffix = ".staging"
let logFileExtension = "log"

public struct InstalledNooklet: Equatable, Sendable {
    public let directory: URL
    public let manifest: NookletManifest

    var serviceLabel: String { serviceLabelPrefix + manifest.id }
}

public struct BuildReport: Codable, Equatable, Sendable {
    public let isSuccess: Bool
    public let log: String
    public let diagnostics: [BuildDiagnostic]
    public let duration: Duration
    public let finishedAt: Date

    public init(isSuccess: Bool, log: String, diagnostics: [BuildDiagnostic], duration: Duration, finishedAt: Date) {
        self.isSuccess = isSuccess
        self.log = log
        self.diagnostics = diagnostics
        self.duration = duration
        self.finishedAt = finishedAt
    }
}

public enum NookletRuntime: Equatable, Sendable {
    case stopped
    case running(pid: Int32, metrics: ProcessMetrics?)
}

public enum NookletLibraryEntry: Equatable, Sendable {
    case ready(InstalledNooklet)
    case broken(directory: URL, reason: String)

    public var directory: URL {
        switch self {
        case .ready(let nooklet): nooklet.directory
        case .broken(let directory, _): directory
        }
    }
}

public struct NookletManager: Sendable {
    let store: NookletLibraryStore
    let builder: NookletBuilder
    let controller: BackgroundServiceController
    let inspector: ProcessInspector
    let reportStore: BuildReportStore
    let logsDirectory: URL
    let binariesDirectory: URL

    public init(
        store: NookletLibraryStore, builder: NookletBuilder, controller: BackgroundServiceController,
        inspector: ProcessInspector, reportStore: BuildReportStore, logsDirectory: URL, binariesDirectory: URL
    ) {
        self.store = store
        self.builder = builder
        self.controller = controller
        self.inspector = inspector
        self.reportStore = reportStore
        self.logsDirectory = logsDirectory
        self.binariesDirectory = binariesDirectory
    }

    public func libraryEntries() throws -> [NookletLibraryEntry] {
        try store.loadDirectories().map(makeLibraryEntry(for:))
    }

    @discardableResult
    public func addNooklet(at directory: URL) throws -> InstalledNooklet {
        let nooklet = InstalledNooklet(directory: directory, manifest: try readManifest(in: directory))
        try ensureIdentifierIsFree(nooklet.manifest.id)
        try store.saveDirectories(store.loadDirectories() + [directory])
        return nooklet
    }

    @discardableResult
    public func createNooklet(named name: String, id: String, in directory: URL, dependency: NookKitDependency) throws -> InstalledNooklet {
        let manifest = NookletManifest(id: id, name: name, product: try makeProductName(from: name))
        try manifest.validate()
        try ensureIdentifierIsFree(id)
        try scaffoldNooklet(manifest, dependency: dependency, in: directory)
        return try addNooklet(at: directory)
    }

    public func run(_ nooklet: InstalledNooklet) async throws -> BuildReport {
        let (outcome, report) = try await buildAndRecord(nooklet)
        if case .succeeded(let executable, _) = outcome {
            let installed = try install(executable, for: nooklet)
            try await controller.start(BackgroundService(label: nooklet.serviceLabel, executable: installed, logFile: logFile(of: nooklet)))
        }
        return report
    }

    public func build(_ nooklet: InstalledNooklet) async throws -> BuildReport {
        try await buildAndRecord(nooklet).report
    }

    public func libraryDirectory(matching reference: String, workingDirectory: URL) throws -> URL {
        let entries = try libraryEntries()
        for case .ready(let nooklet) in entries where nooklet.manifest.id == reference {
            return nooklet.directory
        }
        let candidate = reference.hasPrefix("/") ? URL(filePath: reference) : workingDirectory.appending(path: reference)
        let wanted = comparablePath(of: candidate)
        guard let byFolder = entries.map(\.directory).first(where: { comparablePath(of: $0) == wanted }) else {
            throw NookletLibraryError.unknownNooklet(reference)
        }
        return byFolder
    }

    public func nooklet(matching reference: String, workingDirectory: URL) throws -> InstalledNooklet {
        switch makeLibraryEntry(for: try libraryDirectory(matching: reference, workingDirectory: workingDirectory)) {
        case .ready(let nooklet):
            return nooklet
        case .broken(let directory, let reason):
            throw NookletLibraryError.brokenNooklet(directory.path, reason: reason)
        }
    }

    private func buildAndRecord(_ nooklet: InstalledNooklet) async throws -> (outcome: BuildOutcome, report: BuildReport) {
        let clock = ContinuousClock()
        let started = clock.now
        let outcome = try await builder.build(product: nooklet.manifest.product, packageDirectory: nooklet.directory)
        let duration = clock.now - started
        let report = switch outcome {
        case .failed(let log):
            BuildReport(isSuccess: false, log: log, diagnostics: parseBuildDiagnostics(log), duration: duration, finishedAt: Date())
        case .succeeded(_, let log):
            BuildReport(isSuccess: true, log: log, diagnostics: [], duration: duration, finishedAt: Date())
        }
        try reportStore.save(report, nookletID: nooklet.manifest.id)
        return (outcome, report)
    }

    public func stop(_ nooklet: InstalledNooklet) async throws {
        try await controller.stop(label: nooklet.serviceLabel)
    }

    public func remove(_ directory: URL) async throws {
        if case .ready(let nooklet) = makeLibraryEntry(for: directory) {
            try await stop(nooklet)
            try deleteGeneratedFiles(of: nooklet)
        }
        try store.saveDirectories(store.loadDirectories().filter { $0 != directory })
    }

    public func runtime(of nooklet: InstalledNooklet) async throws -> NookletRuntime {
        guard case .running(let pid) = try await controller.state(label: nooklet.serviceLabel) else {
            return .stopped
        }
        return .running(pid: pid, metrics: try inspector.metrics(pid: pid))
    }

    public func recentLog(of nooklet: InstalledNooklet, lineLimit: Int) throws -> [String] {
        try readLastLines(of: logFile(of: nooklet), limit: lineLimit)
    }

    public func clearLog(of nooklet: InstalledNooklet) throws {
        let file = logFile(of: nooklet)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return
        }
        try Data().write(to: file)
    }

    private func deleteGeneratedFiles(of nooklet: InstalledNooklet) throws {
        try reportStore.delete(nookletID: nooklet.manifest.id)
        let fileManager = FileManager.default
        for item in [logFile(of: nooklet), binariesDirectory.appending(path: nooklet.manifest.id)] where fileManager.fileExists(atPath: item.path) {
            try fileManager.removeItem(at: item)
        }
    }

    private func install(_ executable: URL, for nooklet: InstalledNooklet) throws -> URL {
        let fileManager = FileManager.default
        let destination = binariesDirectory.appending(path: nooklet.manifest.id)
        let staging = binariesDirectory.appending(path: nooklet.manifest.id + stagingSuffix)
        if fileManager.fileExists(atPath: staging.path) {
            try fileManager.removeItem(at: staging)
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let buildDirectory = executable.deletingLastPathComponent()
        let bundles = try fileManager.contentsOfDirectory(at: buildDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == resourceBundleExtension }
        for item in [executable] + bundles {
            try fileManager.copyItem(at: item, to: staging.appending(path: item.lastPathComponent))
        }
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
        return destination.appending(path: executable.lastPathComponent)
    }

    public func logFile(of nooklet: InstalledNooklet) -> URL {
        logsDirectory.appending(path: nooklet.manifest.id).appendingPathExtension(logFileExtension)
    }

    public func lastBuildReport(of nooklet: InstalledNooklet) throws -> BuildReport? {
        try reportStore.load(nookletID: nooklet.manifest.id)
    }

    public func toolchainVersion() async throws -> String {
        try await builder.toolchainVersion()
    }

    private func makeLibraryEntry(for directory: URL) -> NookletLibraryEntry {
        do {
            return .ready(InstalledNooklet(directory: directory, manifest: try readManifest(in: directory)))
        } catch {
            return .broken(directory: directory, reason: error.localizedDescription)
        }
    }

    private func ensureIdentifierIsFree(_ id: String) throws {
        let isTaken = try libraryEntries().contains { entry in
            guard case .ready(let nooklet) = entry else { return false }
            return nooklet.manifest.id == id
        }
        guard !isTaken else {
            throw NookletLibraryError.duplicateIdentifier(id)
        }
    }
}

func comparablePath(of url: URL) -> String {
    let path = url.absoluteURL.standardizedFileURL.resolvingSymlinksInPath().path
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
}

func readManifest(in directory: URL) throws -> NookletManifest {
    let manifestURL = directory.appending(path: manifestFileName)
    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
        throw NookletLibraryError.missingManifest(directory.path)
    }
    return try NookletManifest.decode(from: Data(contentsOf: manifestURL))
}

public enum NookletLibraryError: Error, Equatable, LocalizedError {
    case missingManifest(String)
    case duplicateIdentifier(String)
    case unknownNooklet(String)
    case brokenNooklet(String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .missingManifest(let path):
            "\(path) has no \(manifestFileName); it is not a nooklet folder."
        case .duplicateIdentifier(let id):
            "A nooklet with id \"\(id)\" is already in the library."
        case .unknownNooklet(let reference):
            "No nooklet in the library has the id or folder \"\(reference)\"."
        case .brokenNooklet(let path, let reason):
            "The nooklet at \(path) cannot be used: \(reason)"
        }
    }
}
