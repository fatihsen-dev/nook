import SwiftUI

struct FirstRunView: View {
    let model: LibraryModel
    let onCreate: () -> Void
    let onAddFolder: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            NookSymbol(side: 96)
            VStack(spacing: 12) {
                Text("Make your first nooklet")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("A nooklet is a small native app that lives on your desktop: a now-playing panel, a mini dock, a clock. Nook builds it, keeps it running, and restarts it if it crashes.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 520)
            }
            HStack(spacing: 10) {
                Button(action: onCreate) { Label("New nooklet", systemImage: "plus") }
                    .buttonStyle(NookButtonStyle(kind: .primary, height: 40))
                    .disabled(!isToolchainReady)
                Button(action: onAddFolder) { Label("Add existing folder", systemImage: "folder.badge.plus") }
                    .buttonStyle(NookButtonStyle(kind: .secondary, height: 40))
            }
            toolchainRow
        }
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isToolchainReady: Bool {
        if case .found = model.toolchain { return true }
        return false
    }

    private var toolchainRow: some View {
        HStack(spacing: 8) {
            switch model.toolchain {
            case .checking:
                ProgressView().controlSize(.mini)
                Text("Looking for the Swift toolchain…").foregroundStyle(Theme.muted)
            case .found(let version):
                Image(systemName: "checkmark.circle").foregroundStyle(Theme.lime)
                Text("Swift toolchain found · Swift \(version)").foregroundStyle(Theme.muted)
            case .missing:
                Image(systemName: "xmark.circle").foregroundStyle(Theme.danger)
                Text("No Swift toolchain. Install Xcode or run xcode-select --install.").foregroundStyle(Theme.danger)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.sidebar))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
    }
}
