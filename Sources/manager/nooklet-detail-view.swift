import AppKit
import NookCore
import SwiftUI

struct NookletDetailView: View {
    let model: LibraryModel
    let nooklet: InstalledNooklet

    var body: some View {
        let status = model.status(of: nooklet)
        let report = model.buildReports[nooklet.manifest.id]
        VStack(spacing: 22) {
            header(status)
            if let report, !report.isSuccess {
                BuildFailureBanner(model: model, report: report, packageDirectory: nooklet.directory)
            } else {
                stats(report)
            }
            folderRow
            OutputPanel(model: model, nooklet: nooklet, report: report)
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func header(_ status: NookletStatus) -> some View {
        HStack(spacing: 16) {
            NookletTile(name: nooklet.manifest.name, side: 56)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(nooklet.manifest.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(nooklet.manifest.name)
                    StatusPill(title: status.title, tone: status.tone)
                }
                Text(nooklet.manifest.id)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 16)
            actions(status)
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private func actions(_ status: NookletStatus) -> some View {
        HStack(spacing: 8) {
            switch status.tone {
            case .busy:
                Button {} label: { Label("Building…", systemImage: "hammer") }
                    .buttonStyle(NookButtonStyle(kind: .primary))
                    .disabled(true)
            case .running:
                runButton(title: "Rebuild", systemImage: "arrow.clockwise")
                Button { Task { await model.stop(nooklet) } } label: { Label("Stop", systemImage: "stop") }
                    .buttonStyle(NookButtonStyle(kind: .secondary))
                    .keyboardShortcut(".", modifiers: .command)
            case .failed:
                runButton(title: "Rebuild", systemImage: "arrow.clockwise")
            case .stopped:
                runButton(title: "Run", systemImage: "play.fill")
            }
            MoreButton(model: model, nooklet: nooklet)
        }
    }

    private func runButton(title: String, systemImage: String) -> some View {
        Button { Task { await model.run(nooklet) } } label: { Label(title, systemImage: systemImage) }
            .buttonStyle(NookButtonStyle(kind: .primary))
            .keyboardShortcut("r", modifiers: .command)
    }

    private func stats(_ report: BuildReport?) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let metrics: ProcessMetrics? = if case .running(_, let metrics) = model.runtimes[nooklet.manifest.id] { metrics } else { nil }
            HStack(spacing: 12) {
                StatCard(title: "Memory", value: metrics.map { formatMemory($0.memoryBytes) } ?? "—", systemImage: "memorychip")
                StatCard(title: "Uptime", value: metrics.map { formatUptime(since: $0.startDate, now: context.date) } ?? "—", systemImage: "timer")
                StatCard(title: "Last build", value: report.map { formatBuild($0, now: context.date) } ?? "Never", systemImage: "hammer")
            }
        }
    }

    private var folderRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder").foregroundStyle(Theme.muted)
            Text((nooklet.directory.path as NSString).abbreviatingWithTildeInPath)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { Task { await model.openPackage(nooklet) } } label: { Label("Open in Xcode", systemImage: "chevron.left.forwardslash.chevron.right") }
                .buttonStyle(NookButtonStyle(kind: .secondary, height: 32))
                .keyboardShortcut("o", modifiers: .command)
            Button { model.showInFinder(nooklet.directory) } label: { Image(systemName: "folder") }
                .buttonStyle(IconButtonStyle(side: 32))
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("Show in Finder")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .card()
    }
}

private struct MoreButton: View {
    let model: LibraryModel
    let nooklet: InstalledNooklet
    @Environment(MenuPresenter.self) private var menuPresenter
    @Environment(RemovalPresenter.self) private var removalPresenter
    @State private var frame: CGRect = .zero

    var body: some View {
        Button {
            menuPresenter.show(NookletMenus.more(for: nooklet, model: model, removal: removalPresenter), at: CGPoint(x: frame.maxX, y: frame.maxY), alignment: .belowTrailing, source: .moreButton)
        } label: {
            Image(systemName: "ellipsis")
        }
        .buttonStyle(IconButtonStyle())
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(isShowingMenu ? Theme.faint : Color.clear))
        .help("More")
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { frame = proxy.frame(in: .named(menuCoordinateSpace)) }
                    .onChange(of: proxy.frame(in: .named(menuCoordinateSpace))) { _, newFrame in frame = newFrame }
            }
        }
    }

    private var isShowingMenu: Bool { menuPresenter.isShowing(from: .moreButton) }
}

private struct BuildFailureBanner: View {
    let model: LibraryModel
    let report: BuildReport
    let packageDirectory: URL

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.danger)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.danger)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let first = report.diagnostics.first {
                Button { Task { await model.open(first) } } label: { Label("Open at line \(first.line)", systemImage: "arrow.up.forward.square") }
                    .buttonStyle(NookButtonStyle(kind: .secondary, height: 32))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .card(fill: Theme.dangerSoft, stroke: Theme.dangerLine)
    }

    private var title: String {
        let count = report.diagnostics.count
        return count == 0 ? "Build failed" : "Build failed · \(count) error\(count == 1 ? "" : "s")"
    }

    private var detail: String {
        guard let first = report.diagnostics.first else {
            return "See the Build tab for the full output."
        }
        let prefix = packageDirectory.path + "/"
        let file = first.file.path.hasPrefix(prefix) ? String(first.file.path.dropFirst(prefix.count)) : first.file.lastPathComponent
        return "\(file):\(first.line):\(first.column)  \(first.message)"
    }
}

private struct OutputPanel: View {
    @Bindable var model: LibraryModel
    let nooklet: InstalledNooklet
    let report: BuildReport?

    private var lines: [String] {
        switch model.outputTab {
        case .log: model.logLines
        case .build: report.map { $0.log.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) } ?? []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                tabs
                Spacer()
                Button { model.copyOutput(lines) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(IconButtonStyle(kind: .ghost, side: 28))
                    .help("Copy output")
                if model.outputTab == .log {
                    Button { model.clearLog(of: nooklet) } label: { Image(systemName: "trash") }
                        .buttonStyle(IconButtonStyle(kind: .ghost, side: 28))
                        .help("Clear log")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            SelectableOutputView(lines: lines, placeholder: placeholder)
        }
        .frame(maxHeight: .infinity)
        .card(fill: Theme.console)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(OutputTab.allCases, id: \.self) { tab in
                OutputTabButton(title: tab.rawValue, isSelected: model.outputTab == tab) { model.outputTab = tab }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.raised))
    }

    private var placeholder: String {
        switch model.outputTab {
        case .log: "Nothing logged yet. Anything the nooklet prints shows up here."
        case .build: "No build yet. Run or rebuild to see the compiler output."
        }
    }

    private func color(for line: String) -> Color {
        if line.contains(": error:") || line.hasPrefix("error:") { return Theme.danger }
        if line.hasPrefix("$ ") { return Theme.faint }
        return Theme.muted
    }
}

private struct SelectableOutputView: NSViewRepresentable {
    let lines: [String]
    let placeholder: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.insertionPointColor = .clear
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let isSelectable = !context.environment.isOverlayPresented
        if textView.isSelectable != isSelectable {
            textView.isSelectable = isSelectable
            textView.window?.invalidateCursorRects(for: textView)
        }
        let content = lines.isEmpty ? [placeholder] : lines
        let attributedText = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 7
        paragraphStyle.lineBreakMode = .byClipping

        for (index, line) in content.enumerated() {
            let value = line.isEmpty ? " " : line
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: color(for: line, isPlaceholder: lines.isEmpty),
                .paragraphStyle: paragraphStyle
            ]
            attributedText.append(NSAttributedString(string: value + (index == content.count - 1 ? "" : "\n"), attributes: attributes))
        }

        if textView.textStorage?.string != attributedText.string {
            textView.textStorage?.setAttributedString(attributedText)
            DispatchQueue.main.async {
                let documentHeight = scrollView.documentView?.bounds.height ?? 0
                let viewportHeight = scrollView.contentView.bounds.height
                let bottomOffset = max(0, documentHeight - viewportHeight)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: bottomOffset))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func color(for line: String, isPlaceholder: Bool) -> NSColor {
        if isPlaceholder { return color(hex: 0x5E645B) }
        if line.contains(": error:") || line.hasPrefix("error:") { return color(hex: 0xFF6B57) }
        if line.hasPrefix("$ ") { return color(hex: 0x5E645B) }
        return color(hex: 0x8D9389)
    }

    private func color(hex: UInt32) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {}
}
private struct OutputTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected || isHovering ? Theme.text : Theme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? Theme.raisedStrong : (isHovering ? Theme.raisedStrong.opacity(0.5) : Color.clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { isHovering = $0 }
        .animation(hoverAnimation, value: isHovering)
    }
}
