import NookCore
import SwiftUI

let updateCardWidth: CGFloat = 440
let compactUpdateCardWidth: CGFloat = 400
let progressTrackHeight: CGFloat = 6
let bytesPerMegabyte = 1_000_000.0
let moveToApplicationsSteps = ["Quit Nook.", "Drag Nook.app into the Applications folder.", "Open it from Applications and update."]

struct UpdateLayer: View {
    let model: UpdateModel

    var body: some View {
        ZStack {
            if let phase = model.phase {
                Theme.scrim
                    .contentShape(Rectangle())
                    .onTapGesture { if phase.isDismissible { model.close() } }
                    .transition(.opacity)
                UpdateCard(model: model, phase: phase)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: model.phase == nil)
    }
}

private struct UpdateCard: View {
    let model: UpdateModel
    let phase: UpdatePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
        }
        .padding(24)
        .frame(width: phase == .upToDate ? compactUpdateCardWidth : updateCardWidth)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius + 2).fill(Theme.menu))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius + 2).strokeBorder(Theme.line))
    }

    @ViewBuilder
    private var content: some View {
        let current = model.currentVersion.description
        switch phase {
        case .available(let release):
            UpdateHeader(icon: "arrow.down.to.line", tone: .lime, title: "Nook \(release.version) is available",
                         message: "You have \(current). It takes a few seconds and Nook reopens on its own.")
            if !release.highlights.isEmpty {
                ReleaseNotesBox(highlights: release.highlights) { model.openReleasePage(release) }
            }
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle").font(.system(size: 13)).foregroundStyle(Theme.lime)
                Text("Running nooklets keep running while Nook updates.").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
            }
            UpdateActions {
                Button("Skip this version") { model.skip(release) }.buttonStyle(NookButtonStyle(kind: .ghost))
            } trailing: {
                Button("Later", action: model.close).buttonStyle(NookButtonStyle(kind: .secondary)).keyboardShortcut(.cancelAction)
                Button("Update and restart") { model.install(release) }.buttonStyle(NookButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
            }
        case .downloading(let release, let progress):
            UpdateHeader(icon: "arrow.down.to.line", tone: .lime, title: "Downloading Nook \(release.version)",
                         message: "Nook checks the download's signature before it installs anything.")
            UpdateProgress(fraction: progress?.fraction ?? 0, label: "Downloading…", detail: progress.map(downloadedText) ?? "")
            UpdateActions {
                EmptyView()
            } trailing: {
                Button("Cancel", action: model.close).buttonStyle(NookButtonStyle(kind: .secondary)).keyboardShortcut(.cancelAction)
            }
        case .installing(let release):
            UpdateHeader(icon: "arrow.clockwise", tone: .lime, title: "Installing Nook \(release.version)",
                         message: "Signature verified. Nook closes and reopens in a moment.")
            UpdateProgress(fraction: 1, label: "Restarting…", detail: model.signingTeam.map { "Developer ID · \($0)" } ?? "")
        case .upToDate:
            UpdateHeader(icon: "checkmark.circle", tone: .lime, title: "Nook is up to date",
                         message: "\(current) is the newest version. Nook checks again every day.")
            UpdateActions {
                EmptyView()
            } trailing: {
                Button("OK", action: model.close).buttonStyle(NookButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
            }
        case .failed(let release, let reason):
            UpdateHeader(icon: "exclamationmark.triangle", tone: .danger,
                         title: release == nil ? "Nook could not check for updates" : "The update could not be installed",
                         message: release == nil
                            ? "Check your internet connection and try again."
                            : "Nook \(current) is unchanged and still works. You can try again later or download the new version yourself.")
            Text(reason)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.text)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .card(fill: Theme.sidebar)
            UpdateActions {
                if release != nil {
                    Button("Download manually") { model.openReleasePage(release) }.buttonStyle(NookButtonStyle(kind: .ghost))
                }
            } trailing: {
                Button("Close", action: model.close).buttonStyle(NookButtonStyle(kind: .secondary)).keyboardShortcut(.cancelAction)
                Button("Try again") { retry(release) }.buttonStyle(NookButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
            }
        case .needsMove(let release):
            UpdateHeader(icon: "folder", tone: .muted, title: "Move Nook to Applications to update",
                         message: "Nook \(release.version) is available, but Nook is running from a place it cannot replace itself in, such as the disk image or Downloads.")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(moveToApplicationsSteps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Theme.raised))
                        Text(step).font(.system(size: 13)).foregroundStyle(Theme.text)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .card(fill: Theme.sidebar)
            UpdateActions {
                Button("Download manually") { model.openReleasePage(release) }.buttonStyle(NookButtonStyle(kind: .ghost))
            } trailing: {
                Button("Close", action: model.close).buttonStyle(NookButtonStyle(kind: .secondary)).keyboardShortcut(.cancelAction)
            }
        }
    }

    private func retry(_ release: AppRelease?) {
        guard let release else {
            model.close()
            model.checkNow()
            return
        }
        model.install(release)
    }

    private func downloadedText(_ progress: DownloadProgress) -> String {
        let received = megabytes(progress.receivedBytes)
        guard let total = progress.totalBytes else { return "\(received) MB" }
        return "\(received) of \(megabytes(total)) MB"
    }

    private func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / bytesPerMegabyte)
    }
}

private enum BadgeTone {
    case lime
    case danger
    case muted

    var foreground: Color {
        switch self {
        case .lime: Theme.lime
        case .danger: Theme.danger
        case .muted: Theme.muted
        }
    }

    var background: Color {
        switch self {
        case .lime: Theme.limeSoft
        case .danger: Theme.dangerSoft
        case .muted: Theme.raised
        }
    }
}

private struct UpdateHeader: View {
    let icon: String
    let tone: BadgeTone
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tone.foreground)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(tone.background))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                Text(message).font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(3)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ReleaseNotesBox: View {
    let highlights: [String]
    let onOpenNotes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WHAT'S NEW").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(Theme.faint)
                Spacer()
                Button(action: onOpenNotes) {
                    HStack(spacing: 4) {
                        Text("Release notes")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(LinkTextButtonStyle())
            }
            ForEach(highlights, id: \.self) { highlight in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Theme.lime).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                    Text(highlight).font(.system(size: 13)).foregroundStyle(Theme.text).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card(fill: Theme.sidebar)
    }
}

private struct LinkTextButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovering ? Theme.text : Theme.muted)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .contentShape(Rectangle())
            .pointerCursor()
            .onHover { isHovering = $0 }
            .animation(hoverAnimation, value: isHovering)
    }
}

private struct UpdateProgress: View {
    let fraction: Double
    let label: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text(detail).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.raised)
                    Capsule().fill(Theme.lime).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: progressTrackHeight)
            .animation(.easeOut(duration: 0.2), value: fraction)
        }
    }
}

private struct UpdateActions<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer()
            trailing
        }
        .padding(.top, 6)
    }
}

extension UpdatePhase {
    var isDismissible: Bool {
        switch self {
        case .available, .upToDate, .failed, .needsMove: true
        case .downloading, .installing: false
        }
    }
}
