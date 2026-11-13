import SwiftData
import SwiftUI

// MARK: - SpotlightDebugView

/// Developer-facing debug view for the CoreSpotlight reindex pipeline.
/// Displays the current state of ``SpotlightDebugState`` (which the
/// ``SpotlightReindexActor`` writes to as it runs) and exposes a
/// "Force Full Rebuild" action.
///
/// Surfaced from Settings → Developer → Spotlight Debug so users without
/// Console access can diagnose why Spotlight results aren't appearing.
struct SpotlightDebugView: View {
    // MARK: Internal

    var body: some View {
        List {
            statusSection
            indexErrorSection
            versionSection
            lastRunSection
            querySection
            actionsSection
        }
        .navigationTitle("Spotlight Debug")
    }

    // MARK: Private

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .medium
        return fmt
    }()

    @Environment(\.modelContext) private var modelContext
    @State private var state = SpotlightDebugState.shared

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Phase", value: state.currentPhase)
            LabeledContent("Running") {
                if state.isRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("yes")
                    }
                } else {
                    Text("no")
                }
            }
            LabeledContent(
                "CSSearchableIndex available",
                value: state.lastAvailable.map { $0 ? "yes" : "NO" } ?? "unknown"
            )
            if let error = state.lastError {
                LabeledContent("Last error", value: error)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private var indexErrorSection: some View {
        if state.indexErrorCount > 0 || state.lastIndexError != nil {
            Section("Index errors") {
                LabeledContent(
                    "Error count this pass",
                    value: "\(state.indexErrorCount)"
                )
                if let message = state.lastIndexError {
                    LabeledContent("Last error", value: message)
                        .foregroundStyle(.red)
                }
                Text(
                    "Errors here come from CSSearchableIndex.indexSearchableItems's "
                        + "completion callback. If this is nonzero, iOS rejected at "
                        + "least one batch — items in failing batches are NOT in the index."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var versionSection: some View {
        Section("Schema version") {
            LabeledContent("Current (code)", value: "\(state.currentVersion)")
            LabeledContent(
                "Stored (UserDefaults)",
                value: state.storedVersion < 0 ? "unread" : "\(state.storedVersion)"
            )
            Text(
                "A mismatch triggers a full rebuild on the next reindex pass."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var lastRunSection: some View {
        Section("Last run") {
            LabeledContent("Path", value: state.lastPath)
            LabeledContent(
                "Entered",
                value: state.lastEntryAt.map(Self.dateFormatter.string(from:)) ?? "—"
            )
            LabeledContent(
                "Completed",
                value: state.lastCompletedAt.map(Self.dateFormatter.string(from:)) ?? "—"
            )
            LabeledContent(
                "Elapsed",
                value: state.lastElapsed.map { String(format: "%.2fs", $0) } ?? "—"
            )
            LabeledContent("QSOs indexed", value: "\(state.lastQSOIndexed)")
            LabeledContent("Sessions indexed", value: "\(state.lastSessionIndexed)")
        }
    }

    private var querySection: some View {
        Section {
            Button {
                runIndexQuery()
            } label: {
                if state.isQueryRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Querying…")
                    }
                } else {
                    Label("Query Own Index", systemImage: "magnifyingglass")
                }
            }
            .disabled(state.isQueryRunning)

            if let count = state.lastQueryCount {
                LabeledContent("Items iOS reports", value: "\(count)")
                    .foregroundStyle(count == 0 ? .red : .primary)
            }
            if let queryError = state.lastQueryError {
                LabeledContent("Query error", value: queryError)
                    .foregroundStyle(.red)
            }
            if let queryAt = state.lastQueryAt {
                LabeledContent(
                    "Queried",
                    value: Self.dateFormatter.string(from: queryAt)
                )
            }
        } header: {
            Text("Index query")
        } footer: {
            Text(
                "Runs a CSSearchQuery against our own Spotlight domains "
                    + "and reports how many items iOS has actually indexed. "
                    + "If this returns 0 after a completed full rebuild, "
                    + "iOS is silently rejecting our items."
            )
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                let container = modelContext.container
                Task.detached(priority: .userInitiated) {
                    await SpotlightReindexActor.shared.forceFullRebuild(
                        container: container
                    )
                }
            } label: {
                Label("Force Full Rebuild", systemImage: "arrow.clockwise")
            }
            .disabled(state.isRunning)
        } footer: {
            Text(
                "Resets the stored schema version and runs a full rebuild. "
                    + "Safe to trigger repeatedly."
            )
        }
    }

    private func runIndexQuery() {
        state.isQueryRunning = true
        state.lastQueryError = nil
        Task {
            let result = await SpotlightIndexer.shared.queryOwnIndexedItemCount()
            state.lastQueryAt = Date()
            state.isQueryRunning = false
            switch result {
            case let .success(count):
                state.lastQueryCount = count
            case let .failure(error):
                state.lastQueryError = error.localizedDescription
            }
        }
    }
}
