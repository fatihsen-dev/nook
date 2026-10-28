import SwiftUI

let confirmationWidth: CGFloat = 420
let copiedFeedbackDuration: Duration = .seconds(1.5)

struct RemovalRequest: Identifiable {
    let id = UUID()
    let name: String
    let directory: URL
}

struct RemovalConfirmationLayer: View {
    let model: LibraryModel
    let request: RemovalRequest?
    let onClose: () -> Void

    var body: some View {
        ZStack {
            if let request {
                Theme.scrim
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .transition(.opacity)
                RemovalConfirmationCard(request: request, onCancel: onClose, onCopyPath: { model.copyPath(of: request.directory) }) {
                    onClose()
                    Task { await model.remove(request.directory) }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: request?.id)
    }
}

private struct RemovalConfirmationCard: View {
    let request: RemovalRequest
    let onCancel: () -> Void
    let onCopyPath: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "trash")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.dangerSoft))
            VStack(alignment: .leading, spacing: 8) {
                Text("Remove \(request.name) from Nook?")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text("Nook stops it and deletes its log, build report and installed copy. Your source folder stays where it is.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CopyablePath(directory: request.directory, onCopy: onCopyPath)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(NookButtonStyle(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Remove", action: onRemove)
                    .buttonStyle(NookButtonStyle(kind: .destructive))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: confirmationWidth)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius + 2).fill(Theme.menu))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius + 2).strokeBorder(Theme.line))
    }
}

private struct CopyablePath: View {
    let directory: URL
    let onCopy: () -> Void
    @State private var isHovering = false
    @State private var isCopied = false

    var body: some View {
        Button {
            onCopy()
            isCopied = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text((directory.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isCopied ? Theme.lime : Theme.muted)
                    .opacity(isHovering || isCopied ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(isHovering ? Theme.raised : Theme.sidebar))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help("Copy path")
        .onHover { isHovering = $0 }
        .animation(hoverAnimation, value: isHovering)
        .animation(hoverAnimation, value: isCopied)
        .task(id: isCopied) {
            guard isCopied else { return }
            try? await Task.sleep(for: copiedFeedbackDuration)
            isCopied = false
        }
    }
}

@MainActor
@Observable
final class RemovalPresenter {
    var request: RemovalRequest?

    func ask(name: String, directory: URL) {
        request = RemovalRequest(name: name, directory: directory)
    }

    func close() {
        request = nil
    }
}
