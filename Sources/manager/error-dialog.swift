import SwiftUI

let errorDetailsMaximumHeight: CGFloat = 220

struct ErrorLayer: View {
    let report: ErrorReport?
    let onClose: () -> Void

    var body: some View {
        ZStack {
            if let report {
                Theme.scrim
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .transition(.opacity)
                ErrorCard(report: report, onClose: onClose)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: report?.id)
    }
}

private struct ErrorCard: View {
    let report: ErrorReport
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.dangerSoft))
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.title).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                    if let summary = report.summary {
                        Text(summary).font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(3)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ScrollView {
                Text(report.details)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .frame(maxHeight: errorDetailsMaximumHeight)
            .fixedSize(horizontal: false, vertical: true)
            .card(fill: Theme.sidebar)
            HStack {
                Spacer()
                Button("OK", action: onClose)
                    .buttonStyle(NookButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: updateCardWidth)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius + 2).fill(Theme.menu))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius + 2).strokeBorder(Theme.line))
        .onExitCommand(perform: onClose)
    }
}
