import CarrierWaveData
import SwiftUI

struct QueryWorkbenchView: View {
    // MARK: Internal

    @Bindable var model: QueryWorkbenchModel

    let seedCoordinator: QuerySeedCoordinator?

    var body: some View {
        HSplitView {
            SavedQuerySidebar(model: model)
            mainPane
                .frame(minWidth: 600)
            if showSchemaBrowser {
                SchemaBrowserView(model: model)
            }
        }
        .task { await model.bootstrap() }
        .background(
            // Tap into AppKit so we can intercept the red close button
            // when the editor has unsaved changes — SwiftUI's Window
            // scene exposes no `windowShouldClose` modifier.
            WindowCloseGuard(
                isDirty: { @Sendable in model.hasUnsavedChanges },
                onAttemptClose: { @Sendable in
                    DispatchQueue.main.async { showCloseConfirm = true }
                }
            )
            .frame(width: 0, height: 0)
        )
        .confirmationDialog(
            "You have unsaved changes",
            isPresented: $showCloseConfirm,
            titleVisibility: .visible
        ) {
            if model.selectedQuery != nil {
                Button("Save") {
                    Task {
                        await model.saveOverCurrent()
                        closeWorkbenchWindow()
                    }
                }
            }
            Button("Discard", role: .destructive) {
                model.discardChanges()
                closeWorkbenchWindow()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                model.selectedQuery == nil
                    ? "The current scratch query hasn't been saved. Discard it or cancel to keep editing."
                    : "Save changes to \"\(model.selectedQuery?.name ?? "this query")\" before closing?"
            )
        }
    }

    // MARK: Private

    @State private var showCloseConfirm = false
    @AppStorage("queryWorkbenchShowSchema") private var showSchemaBrowser: Bool = true

    private var selectedColumnHints: [String: String]? {
        guard let id = model.selectedQueryID,
              let query = model.savedQueries.first(where: { $0.id == id })
        else {
            return nil
        }
        return query.columnHints
    }

    private var mainPane: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 8) {
                seedBanner
                toolbar
                QueryEditorView(
                    sql: $model.sql,
                    error: model.error,
                    hasUnsavedChanges: model.hasUnsavedChanges
                )
            }
            .padding(12)

            resultsPane
                .padding(12)
        }
    }

    /// Visible only while the QSO mirror is still being seeded after a
    /// fresh install or a watermark reset. Without this users typing
    /// `SELECT * FROM qsos` see zero rows and assume the workbench is
    /// broken.
    @ViewBuilder
    private var seedBanner: some View {
        if let seedCoordinator,
           case let .seeding(processed, _) = seedCoordinator.state
        {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Indexing \(processed) QSOs…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.08))
            .cornerRadius(4)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.runQuery() }
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.isRunning)

            Button {
                Task { await model.profileQuery() }
            } label: {
                Label("Profile", systemImage: "stopwatch")
            }
            .disabled(model.isRunning)

            Button {
                model.formatSQL()
            } label: {
                Label("Format", systemImage: "text.alignleft")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .help("Pretty-print the SQL (⇧⌘F)")
            .disabled(model.isRunning || model.sql.isEmpty)

            if model.isRunning {
                ProgressView().controlSize(.small)
                Button(role: .destructive) {
                    model.cancelRunning()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            }

            Spacer()

            Button {
                showSchemaBrowser.toggle()
            } label: {
                Label(
                    "Schema",
                    systemImage: showSchemaBrowser
                        ? "sidebar.right"
                        : "sidebar.right"
                )
            }
            .help(showSchemaBrowser ? "Hide the schema browser" : "Show the schema browser")
        }
    }

    @ViewBuilder
    private var resultsPane: some View {
        if let result = model.result {
            VStack(alignment: .leading, spacing: 8) {
                if let profile = model.profile {
                    profileSummary(profile)
                }
                QueryResultsView(
                    result: result,
                    columnHints: selectedColumnHints,
                    onShowMore: { Task { await model.showMore() } },
                    visibleLimit: result.rows.count
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let error = model.error {
            Text(error.message)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("Press ⌘⏎ to run.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func profileSummary(_ profile: QueryProfile) -> some View {
        let depths = Self.planDepths(profile.plan)
        return VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.1f ms", profile.wallClockMillis))
                .font(.caption.bold())
            ForEach(Array(profile.plan.enumerated()), id: \.offset) { idx, row in
                Text(row.detail)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.leading, CGFloat(depths[idx] * 12))
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(4)
    }

    /// Compute display depth for each plan row by walking each row's
    /// parent chain back to a 0/root parent. SQLite's EXPLAIN QUERY
    /// PLAN orders rows top-down; when `parent == 0` the row is at
    /// the root, otherwise depth is parent's depth + 1.
    private static func planDepths(_ rows: [QueryPlanRow]) -> [Int] {
        var depthByID: [Int: Int] = [:]
        var result: [Int] = []
        result.reserveCapacity(rows.count)
        for row in rows {
            let parentDepth = depthByID[row.parent] ?? -1
            let depth = parentDepth + 1
            depthByID[row.id] = depth
            result.append(depth)
        }
        return result
    }

    /// Programmatically close the workbench after the user picks
    /// Save or Discard. The window-close guard returns `false` from
    /// `windowShouldClose` while dirty, so we have to re-trigger
    /// close once the dirty state has been resolved.
    private func closeWorkbenchWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "Query Workbench" }) {
            // Bypass our delegate by calling close() directly — the
            // dirty state is now clean, so a normal close would also
            // succeed, but this avoids the redundant should-close
            // round trip.
            window.close()
        }
    }
}
