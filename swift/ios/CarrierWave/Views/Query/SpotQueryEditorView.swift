import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SpotQueryEditorView

/// iOS spot SQL editor — the promoted replacement for the hidden
/// `QueryRunnerView` experiment. A port of CW Sweep's Query Workbench:
/// monospace SQL editor with Run / Profile / Format, an error banner with
/// line/column from the engine, saved `.cwquery` queries (seeded with the
/// starter set), and a schema reference sheet. Everything executes against
/// the Rust spot engine's in-memory scope DB.
struct SpotQueryEditorView: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let reason = model.engineUnavailableReason {
                    engineUnavailableBanner(reason)
                }
                selectionHeader
                editor
                actionRow
                if let error = model.error {
                    errorBanner(error)
                }
                resultsSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Spot SQL")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingSchemaHelp) {
            SpotSchemaHelpView { snippet in
                insertSnippet(snippet)
            }
        }
        .sheet(isPresented: $showingSaveSheet) {
            SpotQuerySaveSheet(
                initialName: model.selectedQuery?.name ?? "",
                initialDescription: model.selectedQuery?.description ?? ""
            ) { name, description in
                Task { await model.saveCurrent(name: name, description: description) }
            }
        }
        .task {
            await model.bootstrap()
            SpotQueryQsoMirror.shared.mirrorIfNeeded(container: modelContext.container)
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var model = SpotQueryEditorModel()
    @State private var showingSchemaHelp = false
    @State private var showingSaveSheet = false

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 12) {
                Button {
                    showingSchemaHelp = true
                } label: {
                    Image(systemName: "book")
                }
                .accessibilityLabel("Schema reference")
                savedQueriesMenu
            }
        }
    }

    private var savedQueriesMenu: some View {
        Menu {
            Button {
                model.newQuery()
            } label: {
                Label("New Query", systemImage: "plus")
            }
            if model.hasUnsavedChanges {
                saveActions
            }
            if !model.savedQueries.isEmpty {
                Divider()
                ForEach(model.savedQueries) { query in
                    savedQueryActions(query)
                }
            }
        } label: {
            Image(systemName: "folder")
        }
        .accessibilityLabel("Saved queries")
    }

    @ViewBuilder
    private var saveActions: some View {
        if model.selectedQuery != nil {
            Button {
                Task { await model.saveOverCurrent() }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
        }
        Button {
            showingSaveSheet = true
        } label: {
            Label(
                model.selectedQuery == nil ? "Save As…" : "Save As New…",
                systemImage: "square.and.arrow.down.on.square"
            )
        }
    }

    private var selectionHeader: some View {
        HStack(spacing: 6) {
            Text(model.selectedQuery?.name ?? "Scratch query")
                .font(.subheadline.weight(.semibold))
            if model.hasUnsavedChanges {
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Unsaved changes")
            }
            Spacer()
        }
    }

    private var editor: some View {
        TextEditor(text: $model.sql)
            .font(.system(.callout, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .frame(minHeight: 170)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.runQuery() }
            } label: {
                Label("Run", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                Task { await model.profileQuery() }
            } label: {
                Label("Profile", systemImage: "speedometer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                model.formatSQL()
            } label: {
                Label("Format", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .disabled(model.isRunning || model.engineUnavailableReason != nil)
        .overlay(alignment: .trailing) {
            if model.isRunning {
                Button("Cancel") {
                    model.cancelRunning()
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if let result = model.result {
            SpotQueryResultsView(
                result: result,
                isProfile: model.resultIsProfile,
                isRunning: model.isRunning,
                onShowMore: { Task { await model.showMore() } }
            )
        }
        if let mirrorError = SpotQueryQsoMirror.shared.lastError {
            Text("QSO mirror unavailable — `qsos` joins may be empty. \(mirrorError)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func savedQueryActions(_ query: SavedQuery) -> some View {
        Menu {
            Button {
                model.selectQuery(query)
            } label: {
                Label("Open", systemImage: "arrow.up.forward.square")
            }
            Button(role: .destructive) {
                Task { await model.delete(query) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Label(
                query.name,
                systemImage: model.selectedQueryID == query.id ? "checkmark" : "doc.text"
            )
        }
    }

    private func engineUnavailableBanner(_ reason: String) -> some View {
        Label(reason, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func errorBanner(_ error: SpotQueryEditorError) -> some View {
        Label(error.display, systemImage: "xmark.octagon.fill")
            .font(.caption.monospaced())
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func insertSnippet(_ snippet: String) {
        let trimmed = model.sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            model.sql = snippet
        } else {
            model.sql = "\(model.sql)\n\(snippet)"
        }
        showingSchemaHelp = false
    }
}
