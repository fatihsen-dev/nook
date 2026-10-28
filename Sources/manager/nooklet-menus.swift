import Foundation
import NookCore

@MainActor
enum NookletMenus {
    static func more(for nooklet: InstalledNooklet, model: LibraryModel, removal: RemovalPresenter) -> [MenuEntry] {
        locationItems(for: nooklet, model: model) + [
            .divider(),
            .item(MenuItem(title: "Clear log", systemImage: "eraser") { model.clearLog(of: nooklet) }),
            .divider(),
            removeItem(removal: removal, name: nooklet.manifest.name, directory: nooklet.directory),
        ]
    }

    static func sidebar(for entry: NookletLibraryEntry, model: LibraryModel, removal: RemovalPresenter) -> [MenuEntry] {
        switch entry {
        case .ready(let nooklet):
            let lifecycle = lifecycleItems(for: nooklet, model: model)
            return lifecycle + (lifecycle.isEmpty ? [] : [.divider()]) + locationItems(for: nooklet, model: model) + [
                .divider(),
                removeItem(removal: removal, name: nooklet.manifest.name, directory: nooklet.directory),
            ]
        case .broken(let directory, _):
            return [
                .item(MenuItem(title: "Show in Finder", systemImage: "folder") { model.showInFinder(directory) }),
                .divider(),
                removeItem(removal: removal, name: directory.lastPathComponent, directory: directory),
            ]
        }
    }

    private static func lifecycleItems(for nooklet: InstalledNooklet, model: LibraryModel) -> [MenuEntry] {
        let run = { Task { await model.run(nooklet) } }
        let stop = { Task { await model.stop(nooklet) } }
        switch model.status(of: nooklet).tone {
        case .busy:
            return []
        case .running:
            return [
                .item(MenuItem(title: "Rebuild", systemImage: "arrow.clockwise", shortcut: "⌘R") { _ = run() }),
                .item(MenuItem(title: "Stop", systemImage: "stop", shortcut: "⌘.") { _ = stop() }),
            ]
        case .failed:
            return [.item(MenuItem(title: "Rebuild", systemImage: "arrow.clockwise", shortcut: "⌘R") { _ = run() })]
        case .stopped:
            return [.item(MenuItem(title: "Run", systemImage: "play.fill", shortcut: "⌘R") { _ = run() })]
        }
    }

    private static func locationItems(for nooklet: InstalledNooklet, model: LibraryModel) -> [MenuEntry] {
        [
            .item(MenuItem(title: "Open in Xcode", systemImage: "chevron.left.forwardslash.chevron.right", shortcut: "⌘O") {
                Task { await model.openPackage(nooklet) }
            }),
            .item(MenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⇧⌘R") { model.showInFinder(nooklet.directory) }),
            .item(MenuItem(title: "Copy identifier", systemImage: "doc.on.doc") { model.copyIdentifier(of: nooklet) }),
        ]
    }

    private static func removeItem(removal: RemovalPresenter, name: String, directory: URL) -> MenuEntry {
        .item(MenuItem(title: "Remove from Nook", systemImage: "trash", role: .destructive) {
            removal.ask(name: name, directory: directory)
        })
    }
}
