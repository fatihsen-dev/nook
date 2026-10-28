import AppKit
import Foundation
import NookCore
import NookSystem

let automaticUpdateInterval: Duration = .seconds(24 * 60 * 60)
let skippedVersionDefaultsKey = "update.skipped-version"
let restartPause: Duration = .milliseconds(800)

enum UpdatePhase: Equatable {
    case available(AppRelease)
    case downloading(AppRelease, DownloadProgress?)
    case installing(AppRelease)
    case upToDate
    case failed(AppRelease?, String)
    case needsMove(AppRelease)
}

@MainActor
@Observable
final class UpdateModel {
    private(set) var phase: UpdatePhase?
    let currentVersion: AppVersion
    let signingTeam: String?
    private let updater: AppUpdater
    private let appBundle: URL
    private let defaults: UserDefaults
    private var installTask: Task<Void, Never>?

    init(configuration: UpdateConfiguration, defaults: UserDefaults = .standard) {
        self.updater = makeAppUpdater(configuration: configuration)
        self.currentVersion = configuration.currentVersion
        self.appBundle = configuration.appBundle
        self.signingTeam = currentAppSigningTeam()
        self.defaults = defaults
    }

    func checkPeriodically() async {
        while !Task.isCancelled {
            await check(isManual: false)
            do {
                try await Task.sleep(for: automaticUpdateInterval)
            } catch {
                return
            }
        }
    }

    func checkNow() {
        Task { await check(isManual: true) }
    }

    func skip(_ release: AppRelease) {
        defaults.set(release.version.description, forKey: skippedVersionDefaultsKey)
        phase = nil
    }

    func close() {
        installTask?.cancel()
        installTask = nil
        phase = nil
    }

    func install(_ release: AppRelease) {
        guard updater.canReplaceInPlace else {
            phase = .needsMove(release)
            return
        }
        phase = .downloading(release, nil)
        installTask = Task { await runInstall(release) }
    }

    func openReleasePage(_ release: AppRelease?) {
        guard let release else { return }
        NSWorkspace.shared.open(release.page)
    }

    private func check(isManual: Bool) async {
        guard phase == nil || isManual else { return }
        let skipped = isManual ? nil : defaults.string(forKey: skippedVersionDefaultsKey).flatMap(AppVersion.init)
        do {
            switch try await updater.check(skipping: skipped) {
            case .available(let release):
                phase = .available(release)
            case .upToDate:
                if isManual { phase = .upToDate }
            case .skipped:
                break
            }
        } catch {
            guard isManual else {
                reportBackgroundFailure(error)
                return
            }
            phase = .failed(nil, error.localizedDescription)
        }
    }

    private func runInstall(_ release: AppRelease) async {
        do {
            try await updater.install(release) { [weak self] progress in
                Task { @MainActor in self?.showProgress(progress, for: release) }
            }
            phase = .installing(release)
            try scheduleRelaunch(of: appBundle)
            try await Task.sleep(for: restartPause)
            NSApplication.shared.terminate(nil)
        } catch is CancellationError {
            phase = nil
        } catch {
            phase = .failed(release, error.localizedDescription)
        }
    }

    private func showProgress(_ progress: DownloadProgress, for release: AppRelease) {
        guard case .downloading = phase else { return }
        phase = .downloading(release, progress)
    }

    private func reportBackgroundFailure(_ error: Error) {
        FileHandle.standardError.write(Data("Nook update check failed: \(error.localizedDescription)\n".utf8))
    }
}
