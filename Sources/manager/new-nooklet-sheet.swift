import NookCore
import SwiftUI

struct NewNookletSheet: View {
    let model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var identifier = ""
    @State private var isIdentifierEdited = false
    @State private var directory: URL?
    @State private var errorMessage: String?

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !identifier.isEmpty && directory != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("New nooklet").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text)
                    Text("Nook writes a starter package you can open in Xcode.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                field("Name") {
                    TextField("", text: $name, prompt: Text("Now Playing").foregroundStyle(Theme.faint))
                        .onChange(of: name) { _, newName in
                            if !isIdentifierEdited { identifier = model.suggestedIdentifier(forName: newName) }
                        }
                }
                field("Identifier", hint: "Filled in from the name. Used for the background service and saved settings.") {
                    TextField("", text: Binding(get: { identifier }, set: { identifier = $0; isIdentifierEdited = true }),
                              prompt: Text("com.you.now-playing").foregroundStyle(Theme.faint))
                        .font(.system(size: 14, design: .monospaced))
                }
                field("Folder") {
                    HStack {
                        Text(directory.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "No folder chosen")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(directory == nil ? Theme.faint : Theme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Choose…") { directory = chooseDirectory(prompt: "Choose") ?? directory }
                            .buttonStyle(NookButtonStyle(kind: .ghost, height: 28))
                    }
                }
                filesPreview
                if let errorMessage {
                    Text(errorMessage).font(.system(size: 12)).foregroundStyle(Theme.danger)
                }
            }
            .padding(28)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(NookButtonStyle(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
                Button { createAndRun() } label: { Label("Create and run", systemImage: "play") }
                    .buttonStyle(NookButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .frame(width: 520)
        .background(Theme.sidebar)
        .preferredColorScheme(.dark)
    }

    private func field<Content: View>(_ label: String, hint: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            content()
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.background))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.line))
            if let hint {
                Text(hint).font(.system(size: 12)).foregroundStyle(Theme.faint)
            }
        }
    }

    private var filesPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WILL CREATE").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(Theme.faint)
            ForEach([("nook.json", "name and identifier"), ("Package.swift", "depends on NookKit"), ("Sources/app.swift", "your nooklet starts here")], id: \.0) { file, note in
                HStack(spacing: 10) {
                    Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Text(file).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text)
                    Text(note).font(.system(size: 12)).foregroundStyle(Theme.faint)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.console))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.line))
    }

    private func createAndRun() {
        guard let directory else { return }
        do {
            let nooklet = try model.create(name: name.trimmingCharacters(in: .whitespaces), id: identifier, in: directory)
            dismiss()
            Task { await model.run(nooklet) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
