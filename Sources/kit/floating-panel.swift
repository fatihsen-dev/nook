import AppKit
import SwiftUI

let savedTopLeftKey = "nook.floating-panel.top-left"
let dragThreshold: CGFloat = 3
let offscreenPoint = NSPoint(x: -10_000, y: -10_000)

public enum PanelLevel: Sendable {
    case desktop
    case normal
    case floating

    var windowLevel: NSWindow.Level {
        switch self {
        case .desktop:
            NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .normal:
            .normal
        case .floating:
            .floating
        }
    }
}

let panelScreenMargin: CGFloat = 24

public enum PanelPosition: Sendable {
    case center
    case top
    case bottom
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    func origin(for size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        let area = visibleFrame.insetBy(dx: panelScreenMargin, dy: panelScreenMargin)
        let left = area.minX
        let centerX = area.midX - size.width / 2
        let right = area.maxX - size.width
        let bottom = area.minY
        let middleY = area.midY - size.height / 2
        let top = area.maxY - size.height
        switch self {
        case .center: return CGPoint(x: centerX, y: middleY)
        case .top: return CGPoint(x: centerX, y: top)
        case .bottom: return CGPoint(x: centerX, y: bottom)
        case .topLeading: return CGPoint(x: left, y: top)
        case .topTrailing: return CGPoint(x: right, y: top)
        case .bottomLeading: return CGPoint(x: left, y: bottom)
        case .bottomTrailing: return CGPoint(x: right, y: bottom)
        }
    }
}

public struct FloatingPanel<Content: View>: NookScene {
    let level: PanelLevel
    let position: PanelPosition
    let content: Content

    public init(level: PanelLevel = .floating, position: PanelPosition = .center, @ViewBuilder content: () -> Content) {
        self.level = level
        self.position = position
        self.content = content()
    }

    public func makeWindows() -> [NSWindow] {
        [makePanel()]
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = level.windowLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = .preferredContentSize
        panel.contentViewController = controller
        panel.setContentSize(controller.view.fittingSize)
        if let savedTopLeft = loadSavedTopLeft(), isOnSomeScreen(savedTopLeft) {
            panel.setFrameTopLeftPoint(savedTopLeft)
            writeLog("panel restored at \(describe(panel.frame.origin))")
        } else {
            place(panel)
            writeLog("panel placed at \(describe(panel.frame.origin))")
        }
        return panel
    }
}

extension FloatingPanel {
    private func place(_ panel: NSPanel) {
        guard let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame else {
            panel.center()
            return
        }
        panel.setFrameOrigin(position.origin(for: panel.frame.size, in: visibleFrame))
    }
}

private func loadSavedTopLeft() -> CGPoint? {
    guard let coordinates = UserDefaults.standard.array(forKey: savedTopLeftKey) as? [Double], coordinates.count == 2 else {
        return nil
    }
    return CGPoint(x: coordinates[0], y: coordinates[1])
}

@MainActor
private func isOnSomeScreen(_ point: CGPoint) -> Bool {
    NSScreen.screens.contains { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(point) }
}

private final class KeyablePanel: NSPanel {
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var isDragging = false

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragStart = (NSEvent.mouseLocation, frame.origin)
            isDragging = false
            super.sendEvent(event)
        case .leftMouseDragged:
            moveIfDragging(event)
        case .leftMouseUp:
            finishDrag(event)
        default:
            super.sendEvent(event)
        }
    }

    private func moveIfDragging(_ event: NSEvent) {
        guard let dragStart else {
            super.sendEvent(event)
            return
        }
        let mouse = NSEvent.mouseLocation
        let offset = CGSize(width: mouse.x - dragStart.mouse.x, height: mouse.y - dragStart.mouse.y)
        guard isDragging || hypot(offset.width, offset.height) >= dragThreshold else {
            super.sendEvent(event)
            return
        }
        isDragging = true
        setFrameOrigin(NSPoint(x: dragStart.origin.x + offset.width, y: dragStart.origin.y + offset.height))
    }

    private func finishDrag(_ event: NSEvent) {
        defer {
            dragStart = nil
            isDragging = false
        }
        guard isDragging else {
            super.sendEvent(event)
            return
        }
        saveTopLeft(of: self)
        writeLog("panel moved to \(describe(frame.origin))")
        super.sendEvent(makeCancellingMouseUp(from: event))
    }

    private func makeCancellingMouseUp(from event: NSEvent) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseUp, location: offscreenPoint, modifierFlags: event.modifierFlags,
            timestamp: event.timestamp, windowNumber: windowNumber, context: nil,
            eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: 0) ?? event
    }
}

@MainActor
private func saveTopLeft(of window: NSWindow) {
    UserDefaults.standard.set([Double(window.frame.minX), Double(window.frame.maxY)], forKey: savedTopLeftKey)
}

private func describe(_ point: CGPoint) -> String {
    "\(Int(point.x)), \(Int(point.y))"
}
