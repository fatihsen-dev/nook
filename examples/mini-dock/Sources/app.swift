import AppKit
import NookKit
import SwiftUI

@main
struct MiniDock: Nooklet {
    var body: some NookScene {
        FloatingPanel(position: .bottom) {
            DockView(model: RunningApplications())
        }
    }
}

@MainActor
@Observable
final class RunningApplications {
    private(set) var applications: [NSRunningApplication] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        reload()
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let isLaunch = notification.name == NSWorkspace.didLaunchApplicationNotification
                MainActor.assumeIsolated {
                    if let name = application?.localizedName, application?.activationPolicy == .regular {
                        writeLog("\(isLaunch ? "launched" : "quit"): \(name)")
                    }
                    self?.reload()
                }
            }
        }
        writeLog("showing \(applications.count) apps")
    }

    private func reload() {
        applications = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }
}

struct DockView: View {
    let model: RunningApplications
    @State private var hovered: pid_t?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.applications, id: \.processIdentifier) { application in
                Button {
                    writeLog("activate: \(application.localizedName ?? "unknown app")")
                    application.activate()
                } label: {
                    Image(nsImage: application.icon ?? NSImage())
                        .resizable()
                        .frame(width: 40, height: 40)
                        .scaleEffect(hovered == application.processIdentifier ? 1.18 : 1)
                        .animation(.spring(duration: 0.2), value: hovered)
                }
                .buttonStyle(.plain)
                .help(application.localizedName ?? "")
                .onHover { isHovering in
                    hovered = isHovering ? application.processIdentifier : nil
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
