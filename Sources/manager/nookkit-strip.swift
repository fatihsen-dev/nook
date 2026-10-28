import Foundation
import NookCore
import SwiftUI

let dismissedNookKitVersionKey = "nookkit-strip.dismissed-version"
let stripProgressWidth: CGFloat = 120
let stripProgressHeight: CGFloat = 4
let stripButtonHeight: CGFloat = 30
let buildErrorMarker = "error:"

struct NookKitRebuildFailure: Equatable {
    let name: String
    let reason: String
}

enum NookKitRebuild: Equatable {
    case running(done: Int, total: Int)
    case finished(rebuilt: Int, failures: [NookKitRebuildFailure])
}

enum NookKitStripState: Equatable {
    case ready(version: String)
    case rebuilding(version: String, done: Int, total: Int)
    case failed(rebuilt: Int, failures: [NookKitRebuildFailure])
}

extension LibraryModel {
    var nookKitVersion: String? {
        guard case .remote(_, let version) = nookKitDependency else { return nil }
        return version.description
    }

    var nookKitStrip: NookKitStripState? {
        guard let version = nookKitVersion else { return nil }
        switch nookKitRebuild {
        case .running(let done, let total):
            return .rebuilding(version: version, done: done, total: total)
        case .finished(let rebuilt, let failures) where !failures.isEmpty:
            return .failed(rebuilt: rebuilt, failures: failures)
        case .finished, nil:
            guard !outdatedIdentifiers.isEmpty, dismissedNookKitVersion != version else { return nil }
            return .ready(version: version)
        }
    }

    func dismissNookKitStrip() {
        nookKitRebuild = nil
        guard let version = nookKitVersion else { return }
        dismissedNookKitVersion = version
        UserDefaults.standard.set(version, forKey: dismissedNookKitVersionKey)
    }

    func showNookKitFailures(_ failures: [NookKitRebuildFailure]) {
        errorReport = ErrorReport(
            title: "Some nooklets did not rebuild",
            summary: "Their previous builds keep running. Open a nooklet to see its build errors.",
            details: failures.map { "\($0.name): \($0.reason)" }.joined(separator: "\n\n"))
    }

    func rebuildOutdatedNooklets() async {
        let targets = entries.compactMap { entry -> InstalledNooklet? in
            guard case .ready(let nooklet) = entry, outdatedIdentifiers.contains(nooklet.manifest.id) else { return nil }
            return nooklet
        }
        var failures: [NookKitRebuildFailure] = []
        nookKitRebuild = .running(done: 0, total: targets.count)
        for (index, nooklet) in targets.enumerated() {
            if let failure = await rebuildOnNewNookKit(nooklet) {
                failures.append(failure)
            }
            nookKitRebuild = .running(done: index + 1, total: targets.count)
        }
        await refresh()
        nookKitRebuild = .finished(rebuilt: targets.count - failures.count, failures: failures)
    }

    private func rebuildOnNewNookKit(_ nooklet: InstalledNooklet) async -> NookKitRebuildFailure? {
        let name = nooklet.manifest.name
        do {
            guard case .running = runtimes[nooklet.manifest.id] else {
                try await manager.updateNookKit(nooklet)
                return nil
            }
            let report = try await manager.run(nooklet)
            guard report.isSuccess else {
                return NookKitRebuildFailure(name: name, reason: describeBuildFailure(report))
            }
            return nil
        } catch {
            return NookKitRebuildFailure(name: name, reason: error.localizedDescription)
        }
    }
}

struct NookKitStrip: View {
    let model: LibraryModel
    let state: NookKitStripState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isFailure ? Theme.danger : Theme.lime)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                if let body = message {
                    Text(body).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(isFailure ? Theme.dangerSoft : Theme.limeSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isFailure ? Theme.dangerLine : Theme.limeOutline))
    }

    private var isFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    private var icon: String {
        switch state {
        case .ready: "shippingbox"
        case .rebuilding: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var title: String {
        switch state {
        case .ready(let version):
            "NookKit \(version) is ready for your nooklets"
        case .rebuilding(let version, let done, let total):
            "Rebuilding nooklets with NookKit \(version)… \(min(done + 1, total)) of \(total)"
        case .failed(let rebuilt, let failures):
            "\(rebuilt) \(rebuilt == 1 ? "nooklet" : "nooklets") rebuilt, \(failures.count) did not"
        }
    }

    private var message: String? {
        switch state {
        case .ready:
            "Rebuild them to get its fixes. Nooklets you run later pick it up on their own."
        case .rebuilding:
            nil
        case .failed(_, let failures):
            failures.count == 1 ? "\(failures[0].name) did not rebuild; its previous build keeps running." : "Their previous builds keep running."
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .ready:
            Button("Rebuild all") { Task { await model.rebuildOutdatedNooklets() } }
                .buttonStyle(NookButtonStyle(kind: .primary, height: stripButtonHeight))
            closeButton
        case .rebuilding(_, let done, let total):
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised)
                Capsule().fill(Theme.lime).frame(width: stripProgressWidth * CGFloat(done) / CGFloat(max(total, 1)))
            }
            .frame(width: stripProgressWidth, height: stripProgressHeight)
            .animation(.easeOut(duration: 0.2), value: done)
            .padding(.trailing, 4)
        case .failed(_, let failures):
            Button("Details") { model.showNookKitFailures(failures) }
                .buttonStyle(NookButtonStyle(kind: .secondary, height: stripButtonHeight))
            closeButton
        }
    }

    private var closeButton: some View {
        Button(action: model.dismissNookKitStrip) {
            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(IconButtonStyle(kind: .ghost, side: 28))
        .help("Hide")
    }
}

func describeBuildFailure(_ report: BuildReport) -> String {
    if let diagnostic = report.diagnostics.first {
        return "\(diagnostic.file.lastPathComponent):\(diagnostic.line):\(diagnostic.column): error: \(diagnostic.message)"
    }
    let errorLine = report.log.split(whereSeparator: \.isNewline).first { $0.contains(buildErrorMarker) }
    return errorLine.map(String.init) ?? "the build failed without a compiler error; see its Build tab"
}
