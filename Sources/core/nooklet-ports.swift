import Foundation

public protocol NookletLibraryStore: Sendable {
    func loadDirectories() throws -> [URL]
    func saveDirectories(_ directories: [URL]) throws
}

public enum BuildOutcome: Equatable, Sendable {
    case succeeded(executable: URL, log: String)
    case failed(log: String)
}

public protocol NookletBuilder: Sendable {
    func build(product: String, packageDirectory: URL) async throws -> BuildOutcome
    func toolchainVersion() async throws -> String
    func updateDependency(_ identity: String, packageDirectory: URL) async throws
}

public protocol NookKitSyncStore: Sendable {
    func load() throws -> [String: String]
    func save(_ versions: [String: String]) throws
}

public struct BackgroundService: Equatable, Sendable {
    public let label: String
    public let executable: URL
    public let logFile: URL

    public init(label: String, executable: URL, logFile: URL) {
        self.label = label
        self.executable = executable
        self.logFile = logFile
    }
}

public enum ServiceState: Equatable, Sendable {
    case stopped
    case running(pid: Int32)
}

public protocol BackgroundServiceController: Sendable {
    func start(_ service: BackgroundService) async throws
    func stop(label: String) async throws
    func state(label: String) async throws -> ServiceState
}

public struct ProcessMetrics: Equatable, Sendable {
    public let memoryBytes: UInt64
    public let startDate: Date

    public init(memoryBytes: UInt64, startDate: Date) {
        self.memoryBytes = memoryBytes
        self.startDate = startDate
    }
}

public protocol ProcessInspector: Sendable {
    func metrics(pid: Int32) throws -> ProcessMetrics?
}

public protocol CodeEditor: Sendable {
    func openPackage(at directory: URL) async throws
    func open(file: URL, line: Int) async throws
}

public protocol BuildReportStore: Sendable {
    func load(nookletID: String) throws -> BuildReport?
    func save(_ report: BuildReport, nookletID: String) throws
    func delete(nookletID: String) throws
}
