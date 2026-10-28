import AppKit
import SwiftUI

let hoverAnimation: Animation = .easeOut(duration: 0.12)
let pressedOpacity = 0.75
let disabledOpacity = 0.45

enum ButtonKind {
    case primary
    case secondary
    case ghost
    case destructive

    func background(isHovering: Bool) -> Color? {
        switch self {
        case .primary: isHovering ? Theme.limeHover : Theme.lime
        case .secondary: isHovering ? Theme.raisedHover : Theme.raisedStrong
        case .ghost: isHovering ? Theme.raised : nil
        case .destructive: isHovering ? Theme.dangerHover : Theme.danger
        }
    }

    func foreground(isHovering: Bool) -> Color {
        switch self {
        case .primary, .destructive: Theme.background
        case .secondary: Theme.text
        case .ghost: isHovering ? Theme.text : Theme.muted
        }
    }
}

struct NookButtonStyle: ButtonStyle {
    let kind: ButtonKind
    var height: CGFloat = Theme.controlHeight

    func makeBody(configuration: Configuration) -> some View {
        ButtonSurface(kind: kind, isPressed: configuration.isPressed) { isHovering in
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .labelStyle(NookLabelStyle())
                .foregroundStyle(kind.foreground(isHovering: isHovering))
                .padding(.horizontal, 14)
                .frame(height: height)
        }
    }
}

struct NookLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 13, weight: .semibold))
            configuration.title
                .lineLimit(1)
                .fixedSize()
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    var kind: ButtonKind = .secondary
    var side: CGFloat = Theme.controlHeight

    func makeBody(configuration: Configuration) -> some View {
        ButtonSurface(kind: kind, isPressed: configuration.isPressed) { isHovering in
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(kind.foreground(isHovering: isHovering))
                .frame(width: side, height: side)
        }
    }
}

private struct ButtonSurface<Content: View>: View {
    let kind: ButtonKind
    let isPressed: Bool
    @ViewBuilder let content: (Bool) -> Content
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        let isHighlighted = isHovering && isEnabled
        content(isHighlighted)
            .background(kind.background(isHovering: isHighlighted).map { RoundedRectangle(cornerRadius: Theme.controlRadius).fill($0) })
            .contentShape(Rectangle())
            .pointerCursor()
            .opacity(isPressed ? pressedOpacity : (isEnabled ? 1 : disabledOpacity))
            .onHover { isHovering = $0 }
            .animation(hoverAnimation, value: isHighlighted)
    }
}

enum StatusTone {
    case running
    case stopped
    case failed
    case busy

    var foreground: Color {
        switch self {
        case .running: Theme.lime
        case .stopped: Theme.muted
        case .failed: Theme.danger
        case .busy: Theme.text
        }
    }

    var background: Color {
        switch self {
        case .running: Theme.limeSoft
        case .stopped, .busy: Theme.raised
        case .failed: Theme.dangerSoft
        }
    }

    var dot: Color {
        self == .stopped ? Theme.faint : foreground
    }
}

struct StatusPill: View {
    let title: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tone.foreground).frame(width: 7, height: 7)
            Text(title).font(.system(size: 12, weight: .semibold))
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(tone.background))
    }
}

struct NookletTile: View {
    let name: String
    let side: CGFloat

    var body: some View {
        Text(name.prefix(1).uppercased())
            .font(.system(size: side * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.text)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: side * 0.28).fill(Theme.raisedStrong))
    }
}

struct CardBackground: ViewModifier {
    var fill: Color = Theme.sidebar
    var stroke: Color = Theme.line

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(stroke))
    }
}

extension View {
    func card(fill: Color = Theme.sidebar, stroke: Color = Theme.line) -> some View {
        modifier(CardBackground(fill: fill, stroke: stroke))
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }
}

struct PointerCursor: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(.link)
        } else {
            content
                .onHover { hovering in
                    guard hovering != isHovering else { return }
                    isHovering = hovering
                    hovering ? NSCursor.pointingHand.push() : NSCursor.pop()
                }
                .onDisappear {
                    if isHovering { NSCursor.pop() }
                }
        }
    }
}

extension View {
    func pointerCursor() -> some View {
        modifier(PointerCursor())
    }
}
