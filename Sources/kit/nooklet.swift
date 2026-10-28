import AppKit

@MainActor
public protocol Nooklet {
    associatedtype Body: NookScene

    init()

    var body: Body { get }
}

extension Nooklet {
    @MainActor
    public static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        writeLog("started (pid \(ProcessInfo.processInfo.processIdentifier))")
        let windows = Self().body.makeWindows()
        windows.forEach { $0.orderFrontRegardless() }
        withExtendedLifetime(windows) {
            application.run()
        }
    }
}

@MainActor
public protocol NookScene {
    func makeWindows() -> [NSWindow]
}
