import Foundation
import NookCore
import NookSystem

let usageExitCode: Int32 = 64
let failureExitCode: Int32 = 1
let logPollInterval: Duration = .milliseconds(300)
let developmentVersion = "development"
let versionInfoKey = "CFBundleShortVersionString"
let appBundleContentsDirectory = "Contents"

@main
struct NookCtl {
    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 0)
        do {
            let command = try parseCommand(Array(CommandLine.arguments.dropFirst()))
            exit(try await execute(command))
        } catch let error as CommandLineError {
            printError(error.localizedDescription)
            exit(usageExitCode)
        } catch {
            printError(error.localizedDescription)
            exit(failureExitCode)
        }
    }

    static func execute(_ command: Command) async throws -> Int32 {
        let bundleInfo = enclosingAppBundle()?.infoDictionary ?? [:]
        switch command {
        case .help:
            print(usageText)
            return EXIT_SUCCESS
        case .version:
            print(bundleInfo[versionInfoKey] as? String ?? developmentVersion)
            return EXIT_SUCCESS
        default:
            let configuration = try NookConfiguration.load(environment: ProcessInfo.processInfo.environment, bundleInfo: bundleInfo)
            let session = Session(manager: makeNookletManager(configuration: configuration), configuration: configuration)
            return try await session.execute(command)
        }
    }

    static func enclosingAppBundle() -> Bundle? {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            return nil
        }
        let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
        guard contents.lastPathComponent == appBundleContentsDirectory else {
            return nil
        }
        return Bundle(url: contents.deletingLastPathComponent())
    }
}

struct Session {
    let manager: NookletManager
    let configuration: NookConfiguration
    let workingDirectory = URL(filePath: FileManager.default.currentDirectoryPath)

    func execute(_ command: Command) async throws -> Int32 {
        switch command {
        case .help, .version:
            preconditionFailure("\(command) is handled before the library is opened")
        case .list(let json):
            let rows = try await summarizeLibrary()
            print(json ? String(decoding: try encodeJSON(rows), as: UTF8.self) : formatList(rows))
            return EXIT_SUCCESS
        case .new(let folder, let name, let id, let shouldRun):
            let directory = resolve(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let identifier = id ?? suggestIdentifier(forName: name, owner: NSUserName())
            let nooklet = try manager.createNooklet(named: name, id: identifier, in: directory, dependency: configuration.nookKitDependency)
            print("created \(nooklet.manifest.id) in \(directory.path)")
            return shouldRun ? try report(try await manager.run(nooklet), for: nooklet, json: false) : EXIT_SUCCESS
        case .add(let folder):
            let nooklet = try manager.addNooklet(at: resolve(folder))
            print("added \(nooklet.manifest.id) from \(nooklet.directory.path)")
            return EXIT_SUCCESS
        case .build(let reference, let json):
            let nooklet = try find(reference)
            return try report(try await manager.build(nooklet), for: nooklet, json: json)
        case .run(let reference, let json):
            let nooklet = try find(reference)
            let exitCode = try report(try await manager.run(nooklet), for: nooklet, json: json)
            if exitCode == EXIT_SUCCESS && !json {
                print("running; follow its output with `nookctl logs \(nooklet.manifest.id) --follow`")
            }
            return exitCode
        case .stop(let reference):
            let nooklet = try find(reference)
            try await manager.stop(nooklet)
            print("stopped \(nooklet.manifest.id)")
            return EXIT_SUCCESS
        case .remove(let reference):
            let directory = try manager.libraryDirectory(matching: reference, workingDirectory: workingDirectory)
            try await manager.remove(directory)
            print("removed \(directory.path) from the library; the folder itself is untouched")
            return EXIT_SUCCESS
        case .logs(let reference, let lines, let follow):
            let nooklet = try find(reference)
            try manager.recentLog(of: nooklet, lineLimit: lines).forEach { print($0) }
            if follow {
                try await followLog(manager.logFile(of: nooklet))
            }
            return EXIT_SUCCESS
        }
    }

    private func find(_ reference: String) throws -> InstalledNooklet {
        try manager.nooklet(matching: reference, workingDirectory: workingDirectory)
    }

    private func resolve(_ folder: String) -> URL {
        folder.hasPrefix("/") ? URL(filePath: folder) : workingDirectory.appending(path: folder)
    }

    private func report(_ buildReport: BuildReport, for nooklet: InstalledNooklet, json: Bool) throws -> Int32 {
        let id = nooklet.manifest.id
        print(json ? String(decoding: try encodeJSON(BuildSummary(report: buildReport, id: id)), as: UTF8.self) : formatBuildReport(buildReport, id: id))
        return buildReport.isSuccess ? EXIT_SUCCESS : failureExitCode
    }

    private func summarizeLibrary() async throws -> [NookletSummary] {
        var rows: [NookletSummary] = []
        for entry in try manager.libraryEntries() {
            switch entry {
            case .broken(let directory, let reason):
                rows.append(NookletSummary(id: nil, name: nil, directory: directory.path, status: .broken, pid: nil, memoryBytes: nil, lastBuildSucceeded: nil, problem: reason))
            case .ready(let nooklet):
                rows.append(try await summarize(nooklet))
            }
        }
        return rows
    }

    private func summarize(_ nooklet: InstalledNooklet) async throws -> NookletSummary {
        let lastBuild = try manager.lastBuildReport(of: nooklet)
        let problem = lastBuild.flatMap { $0.isSuccess ? nil : "last build failed" }
        let base = (id: nooklet.manifest.id, name: nooklet.manifest.name, directory: nooklet.directory.path)
        switch try await manager.runtime(of: nooklet) {
        case .stopped:
            return NookletSummary(id: base.id, name: base.name, directory: base.directory, status: .stopped, pid: nil, memoryBytes: nil, lastBuildSucceeded: lastBuild?.isSuccess, problem: problem)
        case .running(let pid, let metrics):
            return NookletSummary(id: base.id, name: base.name, directory: base.directory, status: .running, pid: pid, memoryBytes: metrics?.memoryBytes, lastBuildSucceeded: lastBuild?.isSuccess, problem: problem)
        }
    }

    private func followLog(_ file: URL) async throws {
        var offset = try fileSize(of: file)
        while !Task.isCancelled {
            try await Task.sleep(for: logPollInterval)
            let size = try fileSize(of: file)
            if size < offset {
                offset = 0
            }
            guard size > offset else { continue }
            let handle = try FileHandle(forReadingFrom: file)
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            try handle.close()
            FileHandle.standardOutput.write(data)
            offset += UInt64(data.count)
        }
    }

    private func fileSize(of file: URL) throws -> UInt64 {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return 0
        }
        return (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64) ?? 0
    }
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data(("nookctl: " + message + "\n").utf8))
}
