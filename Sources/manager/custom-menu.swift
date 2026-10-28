import AppKit
import SwiftUI

let menuWidth: CGFloat = 224
let menuPadding: CGFloat = 6
let menuItemHeight: CGFloat = 32
let menuSpacing: CGFloat = 2
let menuWindowInset: CGFloat = 8
let menuAnchorGap: CGFloat = 6
let menuCoordinateSpace = "library"

struct MenuItem: Identifiable {
    enum Role {
        case normal
        case destructive
    }

    let id = UUID()
    let title: String
    let systemImage: String
    var shortcut: String? = nil
    var role: Role = .normal
    let action: () -> Void
}

enum MenuEntry: Identifiable {
    case item(MenuItem)
    case divider(UUID = UUID())

    var id: UUID {
        switch self {
        case .item(let item): item.id
        case .divider(let id): id
        }
    }

    var height: CGFloat {
        switch self {
        case .item: menuItemHeight
        case .divider: 1
        }
    }
}

enum MenuSource: Equatable {
    case sidebarRow(URL)
    case moreButton
}

enum MenuAlignment {
    case pointer
    case belowTrailing
}

struct MenuPresentation {
    let entries: [MenuEntry]
    let anchor: CGPoint
    let alignment: MenuAlignment
    let source: MenuSource

    var height: CGFloat {
        let content = entries.map(\.height).reduce(0, +)
        return content + menuSpacing * CGFloat(max(entries.count - 1, 0)) + menuPadding * 2
    }

    func origin(in container: CGSize) -> CGPoint {
        let preferred: CGPoint = switch alignment {
        case .pointer: CGPoint(x: anchor.x + 2, y: anchor.y + 2)
        case .belowTrailing: CGPoint(x: anchor.x - menuWidth, y: anchor.y + menuAnchorGap)
        }
        let maxX = container.width - menuWidth - menuWindowInset
        let x = min(max(preferred.x, menuWindowInset), maxX)
        let fitsBelow = preferred.y + height <= container.height - menuWindowInset
        let y = fitsBelow ? preferred.y : max(anchor.y - height - menuAnchorGap, menuWindowInset)
        return CGPoint(x: x, y: y)
    }
}

@MainActor
@Observable
final class MenuPresenter {
    private(set) var presentation: MenuPresentation?

    func show(_ entries: [MenuEntry], at anchor: CGPoint, alignment: MenuAlignment, source: MenuSource) {
        presentation = MenuPresentation(entries: entries, anchor: anchor, alignment: alignment, source: source)
    }

    func dismiss() {
        presentation = nil
    }

    func isShowing(from source: MenuSource) -> Bool {
        presentation?.source == source
    }
}

struct MenuLayer: View {
    let presenter: MenuPresenter

    var body: some View {
        GeometryReader { proxy in
            if let presentation = presenter.presentation {
                let origin = presentation.origin(in: proxy.size)
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { presenter.dismiss() }
                    MenuPanel(entries: presentation.entries) { item in
                        presenter.dismiss()
                        item.action()
                    }
                    .offset(x: origin.x, y: origin.y)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    Button("Close menu") { presenter.dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .hidden()
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
        .animation(.easeOut(duration: 0.12), value: presenter.presentation != nil)
    }
}

private struct MenuPanel: View {
    let entries: [MenuEntry]
    let onSelect: (MenuItem) -> Void

    var body: some View {
        VStack(spacing: menuSpacing) {
            ForEach(entries) { entry in
                switch entry {
                case .item(let item):
                    MenuRow(item: item) { onSelect(item) }
                case .divider:
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
            }
        }
        .padding(menuPadding)
        .frame(width: menuWidth)
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius + 2).fill(Theme.menu))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius + 2).strokeBorder(Theme.line))
        .compositingGroup()
        .shadow(color: .black.opacity(0.7), radius: 18, y: 16)
    }
}

private struct MenuRow: View {
    let item: MenuItem
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 16)
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.role == .destructive ? Theme.danger : Theme.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.faint)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: menuItemHeight)
            .background(RoundedRectangle(cornerRadius: 8).fill(isHovering ? Theme.raisedStrong : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { isHovering = $0 }
    }

    private var iconColor: Color {
        if item.role == .destructive { return Theme.danger }
        return isHovering ? Theme.text : Theme.muted
    }
}

struct SecondaryClickCatcher: NSViewRepresentable {
    let onSecondaryClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> SecondaryClickView {
        let view = SecondaryClickView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ view: SecondaryClickView, context: Context) {
        view.onSecondaryClick = onSecondaryClick
    }
}

final class SecondaryClickView: NSView {
    var onSecondaryClick: (CGPoint) -> Void = { _ in }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, isSecondaryClick(event) else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func rightMouseDown(with event: NSEvent) {
        report(event)
    }

    override func mouseDown(with event: NSEvent) {
        report(event)
    }

    private func isSecondaryClick(_ event: NSEvent) -> Bool {
        event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }

    private func report(_ event: NSEvent) {
        guard let contentHeight = window?.contentView?.bounds.height else { return }
        onSecondaryClick(CGPoint(x: event.locationInWindow.x, y: contentHeight - event.locationInWindow.y))
    }
}

extension EnvironmentValues {
    @Entry var isOverlayPresented = false
}

extension View {
    func onSecondaryClick(_ action: @escaping (CGPoint) -> Void) -> some View {
        overlay(SecondaryClickCatcher(onSecondaryClick: action))
    }
}
