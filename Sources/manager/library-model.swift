import AppKit
import Foundation
import NookCore
import NookSystem
import Observation

let refreshInterval: Duration = .seconds(2)
let minimumLoadingDuration: Duration = .milliseconds(400)
let logLineLimit = 300

struct ErrorReport: Identifiable {
    let id = UUID()
    let title: String
    var summary: String?
    let details: String
}

enum OutputTab: String, CaseIterable {
    case log = "Log"
    case build = "Build"
}

enum ToolchainState: Equatable {
    case checking
    case found(version: String)
    case missing(reason: String)
}

struct NookletStatus {
    let tone: StatusTone
    let title: String
    let memory: String?
}

@MainActor
@Observable
final class LibraryModel {
    private(set) var entries: [NookletLibraryEntry] = []
    private(set) var runtimes: [String: NookletRuntime] = [:]
    private(set) var buildReports: [String: BuildReport] = [:]
    private(set) var buildingIdentifiers: Set<String> = []
    private(set) var busyDirectories: Set<URL> = []
    private(set) var logLines: [String] = []
    private(set) var toolchain: ToolchainState = .checking
    private(set) var hasLoaded = false
    private(set) var selectedDirectory: URL?
    var outputTab: OutputTab = .log
    var errorReport: ErrorReport?

    let nookKitDependency: NookKitDependency
    let identifierOwner: String
    let manager: NookletManager
    private let editor: CodeEditor
    private var logMonitor: FileChangeMonitor?
    private var monitoredLogFile: URL?
    private(set) var outdatedIdentifiers: Set<String> = []
    var nookKitRebuild: NookKitRebuild?
    var dismissedNookKitVersion: String?

    init(manager: NookletManager, editor: CodeEditor, nookKitDependency: NookKitDependency, identifierOwner: String) {
        self.manager = manager
        self.dismissedNookKitVersion = UserDefaults.standard.string(forKey: dismissedNookKitVersionKey)
        self.editor = editor
        self.nookKitDependency = nookKitDependency
        self.identifierOwner = identifierOwner
    }

    var selectedEntry: NookletLibraryEntry? {
        entries.first { $0.directory == selectedDirectory }
    }

    func select(_ directory: URL) {
        guard directory != selectedDirectory else { return }
        selectedDirectory = directory
        outputTab = .log
        refreshLog()
    }

    func monitor() async {
        let clock = ContinuousClock()
        let loadingStarted = clock.now
        await refresh()
        let remaining = minimumLoadingDuration - (clock.now - loadingStarted)
        if remaining > .zero {
            do {
                try await Task.sleep(for: remaining)
            } catch {
                return
            }
        }
        hasLoaded = true
        await checkToolchain()
        while !Task.isCancelled {
            await refresh()
            do {
                try await Task.sleep(for: refreshInterval)
            } catch {
                return
            }
        }
    }

    func refresh() async {
        do {
            entries = try manager.libraryEntries()
            forgetRemovedNooklets()
            var updated: [String: NookletRuntime] = [:]
            var outdated: Set<String> = []
            for case .ready(let nooklet) in entries {
                updated[nooklet.manifest.id] = try await manager.runtime(of: nooklet)
                if try manager.isNookKitOutdated(nooklet) { outdated.insert(nooklet.manifest.id) }
                if !buildingIdentifiers.contains(nooklet.manifest.id), let saved = try manager.lastBuildReport(of: nooklet), saved != buildReports[nooklet.manifest.id] {
                    buildReports[nooklet.manifest.id] = saved
                }
            }
            runtimes = updated
            if outdated != outdatedIdentifiers { outdatedIdentifiers = outdated }
        } catch {
            report(error, title: "Could not refresh nooklets")
        }
        if selectedEntry == nil {
            selectedDirectory = entries.first?.directory
        }
        refreshLog()
    }

    func status(of nooklet: InstalledNooklet) -> NookletStatus {
        let id = nooklet.manifest.id
        if buildingIdentifiers.contains(id) {
            return NookletStatus(tone: .busy, title: "Building…", memory: nil)
        }
        if let report = buildReports[id], !report.isSuccess {
            return NookletStatus(tone: .failed, title: "Build failed", memory: nil)
        }
        guard case .running(_, let metrics) = runtimes[id] else {
            return NookletStatus(tone: .stopped, title: "Stopped", memory: nil)
        }
        return NookletStatus(tone: .running, title: "Running", memory: metrics.map { formatMemory($0.memoryBytes) })
    }

    func run(_ nooklet: InstalledNooklet) async {
        let id = nooklet.manifest.id
        buildingIdentifiers.insert(id)
        do {
            let report = try await manager.run(nooklet)
            buildReports[id] = report
            if !report.isSuccess && selectedDirectory == nooklet.directory {
                outputTab = .build
            }
        } catch {
            report(error, title: "Could not run \(nooklet.manifest.name)")
        }
        buildingIdentifiers.remove(id)
        await refresh()
    }

    func stop(_ nooklet: InstalledNooklet) async {
        await perform(on: nooklet.directory, title: "Could not stop \(nooklet.manifest.name)") {
            try await self.manager.stop(nooklet)
        }
    }

    func remove(_ directory: URL) async {
        await perform(on: directory, title: "Could not remove \(directory.lastPathComponent)") {
            try await self.manager.remove(directory)
        }
        if selectedDirectory == directory {
            selectedDirectory = entries.first?.directory
        }
    }

    func addFolder(_ directory: URL) async {
        do {
            try manager.addNooklet(at: directory)
            selectedDirectory = directory
        } catch {
            report(error, title: "Could not add \(directory.lastPathComponent)")
        }
        await refresh()
    }

    func create(name: String, id: String, in directory: URL) throws -> InstalledNooklet {
        let nooklet = try manager.createNooklet(named: name, id: id, in: directory, dependency: nookKitDependency)
        selectedDirectory = directory
        return nooklet
    }

    func openPackage(_ nooklet: InstalledNooklet) async {
        do {
            try await editor.openPackage(at: nooklet.directory)
        } catch {
            report(error, title: "Could not open \(nooklet.manifest.name) in Xcode")
        }
    }

    func open(_ diagnostic: BuildDiagnostic) async {
        do {
            try await editor.open(file: diagnostic.file, line: diagnostic.line)
        } catch {
            report(error, title: "Could not open \(diagnostic.file.lastPathComponent)")
        }
    }

    func showInFinder(_ directory: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func copyOutput(_ lines: [String]) {
        copyToPasteboard(lines.joined(separator: "\n"))
    }

    func copyIdentifier(of nooklet: InstalledNooklet) {
        copyToPasteboard(nooklet.manifest.id)
    }

    func copyPath(of directory: URL) {
        copyToPasteboard(directory.path)
    }

    func clearLog(of nooklet: InstalledNooklet) {
        do {
            try manager.clearLog(of: nooklet)
        } catch {
            report(error, title: "Could not clear the log of \(nooklet.manifest.name)")
        }
        refreshLog()
    }

    func suggestedIdentifier(forName name: String) -> String {
        suggestIdentifier(forName: name, owner: identifierOwner)
    }

    private func forgetRemovedNooklets() {
        let identifiers = Set(entries.compactMap { entry -> String? in
            guard case .ready(let nooklet) = entry else { return nil }
            return nooklet.manifest.id
        })
        buildReports = buildReports.filter { identifiers.contains($0.key) }
    }

    private func checkToolchain() async {
        do {
            toolchain = .found(version: try await manager.toolchainVersion())
        } catch {
            toolchain = .missing(reason: error.localizedDescription)
        }
    }

    private func refreshLog() {
        guard case .ready(let nooklet) = selectedEntry else {
            logLines = []
            stopWatchingLog()
            return
        }
        watchLog(of: nooklet)
        do {
            let lines = try manager.recentLog(of: nooklet, lineLimit: logLineLimit)
            if lines != logLines { logLines = lines }
        } catch {
            report(error, title: "Could not read the log of \(nooklet.manifest.name)")
        }
    }

    private func watchLog(of nooklet: InstalledNooklet) {
        let file = manager.logFile(of: nooklet)
        guard file != monitoredLogFile || logMonitor == nil else { return }
        stopWatchingLog()
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            logMonitor = try FileChangeMonitor(file: file, queue: .main) { [weak self] in
                MainActor.assumeIsolated { self?.handleLogChange() }
            }
            monitoredLogFile = file
        } catch {
            report(error, title: "Could not follow the log of \(nooklet.manifest.name)")
        }
    }

    private func handleLogChange() {
        if logMonitor?.isFileGone == true {
            stopWatchingLog()
        }
        refreshLog()
    }

    private func stopWatchingLog() {
        logMonitor = nil
        monitoredLogFile = nil
    }

    private func perform(on directory: URL, title: String, action: @escaping () async throws -> Void) async {
        busyDirectories.insert(directory)
        do {
            try await action()
        } catch {
            report(error, title: title)
        }
        busyDirectories.remove(directory)
        await refresh()
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func report(_ error: Error, title: String) {
        errorReport = ErrorReport(title: title, details: error.localizedDescription)
    }
}

func formatMemory(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
}

func formatUptime(since start: Date, now: Date) -> String {
    let seconds = max(Int(now.timeIntervalSince(start)), 0)
    let (hours, minutes) = (seconds / 3600, (seconds % 3600) / 60)
    if hours > 0 { return "\(hours)h \(minutes)m" }
    if minutes > 0 { return "\(minutes)m" }
    return "\(seconds)s"
}

func formatBuild(_ report: BuildReport, now: Date) -> String {
    let seconds = Double(report.duration.components.seconds) + Double(report.duration.components.attoseconds) / 1e18
    let relative = RelativeDateTimeFormatter().localizedString(for: report.finishedAt, relativeTo: now)
    return String(format: "%.1f s · ", seconds) + relative
}
