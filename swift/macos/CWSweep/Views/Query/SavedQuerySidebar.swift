import AppKit
import CarrierWaveData
import SwiftUI

// MARK: - SavedQuerySidebar

struct SavedQuerySidebar: View {
    // MARK: Internal

    @Bindable var model: QueryWorkbenchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            Divider()
            queryList
            Divider()
            actionRow
        }
        .frame(minWidth: 220)
        .sheet(isPresented: $showSaveAsSheet) { saveAsSheet }
        .sheet(item: $renamingQuery) { query in
            RenameSheet(query: query) { newName, description in
                Task { await model.rename(query, to: newName, description: description) }
            }
        }
    }

    // MARK: Private

    @State private var showSaveAsSheet = false
    @State private var draftName = ""
    @State private var draftDescription = ""
    @State private var renamingQuery: SavedQuery?

    private var sidebarHeader: some View {
        HStack {
            Text("Saved Queries")
                .font(.headline)
            Spacer()
        }
        .padding(8)
    }

    private var queryList: some View {
        List(selection: $model.selectedQueryID) {
            ForEach(model.savedQueries) { query in
                row(for: query)
                    .tag(query.id)
                    .contextMenu { contextMenu(for: query) }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.selectedQueryID) { _, newID in
            if let newID, let match = model.savedQueries.first(where: { $0.id == newID }) {
                model.selectQuery(match)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            Button {
                model.newQuery()
            } label: {
                Label("New", systemImage: "plus")
            }
            .help("Start a new query")

            Button {
                Task { await model.saveOverCurrent() }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .help("Save changes to the selected query (⌘S)")
            .keyboardShortcut("s", modifiers: .command)
            .disabled(model.selectedQuery == nil || !model.hasUnsavedChanges)

            Button {
                openSaveAsSheet()
            } label: {
                Label("Save As…", systemImage: "square.and.arrow.down.on.square")
            }
            .help("Save the editor contents as a new saved query")

            Button {
                Task { await importFromClipboard() }
            } label: {
                Label("Import", systemImage: "tray.and.arrow.down")
            }
            .help("Import a cwquery:// URL from the clipboard")

            Spacer()
        }
        .padding(8)
        .buttonStyle(.borderless)
    }

    private var saveAsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Query As").font(.headline)
            TextField("Name", text: $draftName)
            TextField("Description", text: $draftDescription)
            HStack {
                Spacer()
                Button("Cancel") { showSaveAsSheet = false }
                Button("Save") {
                    let name = draftName
                    let description = draftDescription
                    Task {
                        await model.saveCurrent(name: name, description: description)
                    }
                    showSaveAsSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftName.isEmpty)
            }
        }
        .padding()
        .frame(width: 380)
    }

    private func row(for query: SavedQuery) -> some View {
        HStack(spacing: 4) {
            Text(query.name)
            // Dot marks the currently-selected query when its editor
            // SQL has diverged from the on-disk version. Cheap visual
            // hook so users notice they have unsaved work.
            if model.selectedQueryID == query.id, model.hasUnsavedChanges {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func contextMenu(for query: SavedQuery) -> some View {
        Button("Edit") {
            model.selectQuery(query)
        }
        Button("Duplicate") {
            Task { await model.duplicate(query) }
        }
        Button("Rename…") {
            renamingQuery = query
        }
        Divider()
        Button("Copy Share URL") {
            if let url = model.shareURL(for: query) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            Task { await model.delete(query) }
        }
    }

    /// Save As… seeds the dialog with the current selection's name +
    /// " (copy)" so the user doesn't have to retype to clone.
    private func openSaveAsSheet() {
        if let selected = model.selectedQuery {
            draftName = "\(selected.name) (copy)"
            draftDescription = selected.description
        } else {
            draftName = ""
            draftDescription = ""
        }
        showSaveAsSheet = true
    }

    private func importFromClipboard() async {
        guard let urlString = NSPasteboard.general.string(forType: .string),
              let url = URL(string: urlString)
        else {
            return
        }
        await model.importFrom(url: url)
    }
}

// MARK: - RenameSheet

/// Lifted out of the sidebar so its `@State` resets cleanly each time
/// `renamingQuery` rebinds — embedding `TextField`s inside the
/// `.sheet(item:)` closure with parent state would carry stale values
/// between sheet presentations.
private struct RenameSheet: View {
    // MARK: Lifecycle

    init(query: SavedQuery, onSave: @escaping (String, String) -> Void) {
        self.query = query
        self.onSave = onSave
        _name = State(initialValue: query.name)
        _description = State(initialValue: query.description)
    }

    // MARK: Internal

    let query: SavedQuery
    let onSave: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Query").font(.headline)
            TextField("Name", text: $name)
            TextField("Description", text: $description)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(name, description)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 380)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
}
