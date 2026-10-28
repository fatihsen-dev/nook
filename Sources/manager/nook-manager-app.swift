import AppKit
import NookCore
import NookSystem
import SwiftUI

let windowDefaultSize = CGSize(width: 1120, height: 720)
let windowMinimumSize = CGSize(width: 900, height: 600)
let appVersionInfoKey = "CFBundleShortVersionString"

@main
struct NookManagerApp: App {
    private let configurationResult = Result { try NookConfiguration.load(environment: ProcessInfo.processInfo.environment, bundleInfo: Bundle.main.infoDictionary ?? [:]) }
    private let updates: UpdateModel?

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        do {
            updates = try UpdateConfiguration.load(environment: ProcessInfo.processInfo.environment, bundle: .main).map { UpdateModel(configuration: $0) }
        } catch {
            FileHandle.standardError.write(Data("Nook updates are off: \(error.localizedDescription)\n".utf8))
            updates = nil
        }
    }

    var body: some Scene {
        Window("Nook", id: "library") {
            Group {
                switch configurationResult {
                case .success(let configuration):
                    LibraryView(
                        model: LibraryModel(
                            manager: makeNookletManager(configuration: configuration),
                            editor: makeCodeEditor(),
                            nookKitDependency: configuration.nookKitDependency,
                            identifierOwner: NSUserName(),
                            nookKitRefreshPlan: makeNookKitRefreshPlan(configuration: configuration)),
                        updates: updates)
                case .failure(let error):
                    ContentUnavailableView("Nook is not configured", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
                }
            }
            .frame(minWidth: windowMinimumSize.width, minHeight: windowMinimumSize.height)
            .preferredColorScheme(.dark)
            .onAppear {
                NSApplication.shared.applicationIconImage = makeAppIconImage()
                NSApplication.shared.activate()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(windowDefaultSize)
        .commands {
            if let updates {
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates…", action: updates.checkNow)
                }
            }
        }
    }
}

private func makeNookKitRefreshPlan(configuration: NookConfiguration) -> NookKitRefreshPlan? {
    guard let appVersion = Bundle.main.infoDictionary?[appVersionInfoKey] as? String else { return nil }
    return NookKitRefreshPlan(refresher: makeNookKitRefresher(configuration: configuration), appVersion: appVersion)
}
