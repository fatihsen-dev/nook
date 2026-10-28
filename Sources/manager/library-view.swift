import AppKit
import NookCore
import SwiftUI

struct LibraryView: View {
    @State var model: LibraryModel
    @State private var isCreatingNooklet = false
    @State private var menuPresenter = MenuPresenter()
    @State private var removalPresenter = RemovalPresenter()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if !model.hasLoaded {
                LoadingView()
                    .transition(.opacity)
            } else if model.entries.isEmpty {
                FirstRunView(model: model, onCreate: { isCreatingNooklet = true }, onAddFolder: addFolder)
            } else {
                HStack(spacing: 0) {
                    SidebarView(model: model, onCreate: { isCreatingNooklet = true }, onAddFolder: addFolder)
                    detail
                }
                .environment(\.isOverlayPresented, isOverlayPresented)
            }
            MenuLayer(presenter: menuPresenter)
            RemovalConfirmationLayer(model: model, request: removalPresenter.request, onClose: removalPresenter.close)
        }
        .coordinateSpace(.named(menuCoordinateSpace))
        .environment(menuPresenter)
        .environment(removalPresenter)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.25), value: model.hasLoaded)
        .sheet(isPresented: $isCreatingNooklet) {
            NewNookletSheet(model: model)
        }
        .alert(item: $model.errorReport) { report in
            Alert(title: Text(report.title), message: Text(report.message))
        }
        .task { await model.monitor() }
    }

    private var isOverlayPresented: Bool {
        menuPresenter.presentation != nil || removalPresenter.request != nil
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedEntry {
        case .ready(let nooklet):
            NookletDetailView(model: model, nooklet: nooklet)
        case .broken(let directory, let reason):
            BrokenNookletView(model: model, directory: directory, reason: reason)
        case nil:
            Color.clear
        }
    }

    private func addFolder() {
        guard let directory = chooseDirectory(prompt: "Add") else { return }
        Task { await model.addFolder(directory) }
    }
}

struct SidebarView: View {
    let model: LibraryModel
    let onCreate: () -> Void
    let onAddFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            NookWordmark(height: 26)
                .padding(.horizontal, 6)
                .padding(.top, Theme.titlebarInset)
            VStack(spacing: 4) {
                HStack {
                    Text("NOOKLETS")
                    Spacer()
                    Text("\(model.entries.count)")
                }
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.faint)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.entries, id: \.directory) { entry in
                            SidebarRow(model: model, entry: entry)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            HStack(spacing: 8) {
                Button(action: onCreate) {
                    Label("New nooklet", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(NookButtonStyle(kind: .secondary))
                Button(action: onAddFolder) {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(IconButtonStyle())
                .help("Add an existing nooklet folder")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: Theme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }
}

private struct SidebarRow: View {
    let model: LibraryModel
    let entry: NookletLibraryEntry
    @State private var isHovering = false
    @Environment(MenuPresenter.self) private var menuPresenter
    @Environment(RemovalPresenter.self) private var removalPresenter

    var body: some View {
        Button { model.select(entry.directory) } label: {
            HStack(spacing: 12) {
                content
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(rowBackground))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isShowingMenu ? Theme.limeOutline : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { isHovering = $0 }
        .onSecondaryClick { point in
            menuPresenter.show(NookletMenus.sidebar(for: entry, model: model, removal: removalPresenter), at: point, alignment: .pointer, source: .sidebarRow(entry.directory))
        }
        .animation(hoverAnimation, value: isHovering)
    }

    private var isShowingMenu: Bool { menuPresenter.isShowing(from: .sidebarRow(entry.directory)) }

    private var rowBackground: Color {
        if isSelected { return Theme.raised }
        return isHovering ? Theme.rowHover : Color.clear
    }

    private var isSelected: Bool { model.selectedDirectory == entry.directory }

    @ViewBuilder
    private var content: some View {
        switch entry {
        case .ready(let nooklet):
            let status = model.status(of: nooklet)
            NookletTile(name: nooklet.manifest.name, side: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(nooklet.manifest.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text([status.title, status.memory].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(status.tone == .failed ? Theme.danger : Theme.muted)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Circle().fill(status.tone.dot).frame(width: 8, height: 8)
        case .broken(let directory, _):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.dangerSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(directory.lastPathComponent).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text("Can't load").font(.system(size: 12)).foregroundStyle(Theme.danger)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

struct BrokenNookletView: View {
    let model: LibraryModel
    let directory: URL
    let reason: String
    @Environment(RemovalPresenter.self) private var removalPresenter

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 32)).foregroundStyle(Theme.danger)
            Text("\(directory.lastPathComponent) can't be loaded").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text)
            Text(reason).font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 460)
            HStack(spacing: 8) {
                Button { model.showInFinder(directory) } label: { Label("Show in Finder", systemImage: "folder") }
                    .buttonStyle(NookButtonStyle(kind: .secondary))
                Button { removalPresenter.ask(name: directory.lastPathComponent, directory: directory) } label: { Label("Remove from Nook", systemImage: "trash") }
                    .buttonStyle(NookButtonStyle(kind: .primary))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
func chooseDirectory(prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = prompt
    return panel.runModal() == .OK ? panel.url : nil
}
