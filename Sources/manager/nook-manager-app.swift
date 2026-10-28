import AppKit
import NookCore
import NookSystem
import SwiftUI

let windowDefaultSize = CGSize(width: 1120, height: 720)
let windowMinimumSize = CGSize(width: 900, height: 600)

@main
struct NookManagerApp: App {
    private let configurationResult = Result { try NookConfiguration.load(environment: ProcessInfo.processInfo.environment, bundleInfo: Bundle.main.infoDictionary ?? [:]) }

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Nook", id: "library") {
            Group {
                switch configurationResult {
                case .success(let configuration):
                    LibraryView(model: LibraryModel(
                        manager: makeNookletManager(configuration: configuration),
                        editor: makeCodeEditor(),
                        nookKitDependency: configuration.nookKitDependency,
                        identifierOwner: NSUserName()))
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
    }
}
