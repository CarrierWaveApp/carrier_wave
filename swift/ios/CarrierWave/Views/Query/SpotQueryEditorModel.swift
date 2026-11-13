import CarrierWaveCwFfi
import CarrierWaveData
import SwiftUI

// MARK: - SpotQueryEditorError

/// Query failure surfaced in the editor's error banner. Line/column come
/// from the engine's `sqlite3_error_offset` mapping when available.
struct SpotQueryEditorError: Equatable {
    let message: String
    let line: UInt32?
    let column: UInt32?

    var display: String {
        if let line, let column {
            return "Line \(line), column \(column): \(message)"
        }
        if let line {
            return "Line \(line): \(message)"
        }
        return message
    }
}

// MARK: - SpotQueryEditorModel

/// State + actions for the iOS spot SQL editor — a port of CW Sweep's
/// `QueryWorkbenchModel`, re-pointed from GRDB at the Rust spot engine's
/// query FFI (`run_query` / `profile_query` / `format_sql`). Saved
/// queries reuse the shared `.cwquery` store so files authored on either
/// platform show up on both.
@MainActor
@Observable
final class SpotQueryEditorModel {
    // MARK: Internal

    /// User-overridable result row cap. Resets to `defaultRowLimit` each
    /// time a fresh query is selected/run; "show more" doubles it.
    static let defaultRowLimit: UInt32 = 200

    var sql = "SELECT * FROM scope.spots LIMIT 50;"
    var selectedQueryID: UUID?
    var savedQueries: [SavedQuery] = []
    var result: FfiQueryResultSet?
    /// True when `result` came from Profile (EXPLAIN QUERY PLAN rows).
    var resultIsProfile = false
    var error: SpotQueryEditorError?
    var isRunning = false
    var rowLimit: UInt32 = SpotQueryEditorModel.defaultRowLimit
    /// Non-nil while the engine failed to construct — the editor shows a
    /// disabled state instead of buttons that can't work.
    var engineUnavailableReason: String?

    /// True when the editor's SQL diverges from the on-disk version of
    /// the currently-selected saved query. Drives the dirty marker and
    /// enables the Save action.
    var hasUnsavedChanges: Bool {
        guard let selected = selectedQuery else {
            return !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return sql != selected.sql
    }

    var selectedQuery: SavedQuery? {
        guard let selectedQueryID else {
            return nil
        }
        return savedQueries.first { $0.id == selectedQueryID }
    }

    func bootstrap() async {
        if engine == nil {
            engine = SpotEngineProvider.shared.engine()
            engineUnavailableReason = engine == nil
                ? (SpotEngineProvider.shared.lastEngineError ?? "Spot engine failed to start.")
                : nil
        }
        await seedStarterQueriesIfNeeded()
        await refreshSavedQueries()
    }

    func selectQuery(_ query: SavedQuery) {
        selectedQueryID = query.id
        sql = query.sql
        clearResults()
    }

    /// Clear the selection and editor for a fresh scratch query.
    func newQuery() {
        selectedQueryID = nil
        sql = "SELECT * FROM scope.spots LIMIT 50;"
        clearResults()
    }

    /// Pretty-print the editor's SQL via the Rust `format_sql` FFI (the
    /// same formatter CW Sweep's Format button uses). Idempotent — a
    /// second tap is a no-op when the formatter has nothing to fix.
    func formatSQL() {
        let formatted = formatSql(sql: sql)
        if formatted != sql {
            sql = formatted
        }
    }

    func runQuery() async {
        await execute { engine, sql, limit in
            try engine.runQuery(sql: sql, limit: limit)
        }
        resultIsProfile = false
    }

    /// EXPLAIN QUERY PLAN via the engine — rows describe the plan, not
    /// the data.
    func profileQuery() async {
        await execute { engine, sql, _ in
            try engine.profileQuery(sql: sql)
        }
        resultIsProfile = result != nil
    }

    /// Double the visible row cap and re-run. Only meaningful when the
    /// engine reported truncation.
    func showMore() async {
        guard let result, result.truncated else {
            return
        }
        rowLimit *= 2
        await runQuery()
    }

    /// Break the in-flight query (`sqlite3_interrupt`); `runQuery`
    /// surfaces the interrupt as a SQLite error.
    func cancelRunning() {
        guard isRunning, let engine else {
            return
        }
        engine.interruptQuery()
    }

    func saveCurrent(name: String, description: String) async {
        let query = SavedQuery(name: name, description: description, sql: sql)
        do {
            try await store.save(query)
            await refreshSavedQueries()
            selectedQueryID = query.id
        } catch {
            self.error = SpotQueryEditorError(
                message: "Save failed: \(error.localizedDescription)", line: nil, column: nil
            )
        }
    }

    /// Persist the editor's current SQL onto the selected saved query,
    /// preserving its id / name / description.
    func saveOverCurrent() async {
        guard let selected = selectedQuery else {
            return
        }
        let updated = SavedQuery(
            id: selected.id,
            name: selected.name,
            description: selected.description,
            sql: sql,
            schemaVersion: selected.schemaVersion,
            createdAt: selected.createdAt,
            columnHints: selected.columnHints
        )
        do {
            try await store.save(updated)
            await refreshSavedQueries()
        } catch {
            self.error = SpotQueryEditorError(
                message: "Save failed: \(error.localizedDescription)", line: nil, column: nil
            )
        }
    }

    func delete(_ query: SavedQuery) async {
        do {
            try await store.delete(query)
            if selectedQueryID == query.id {
                selectedQueryID = nil
            }
            await refreshSavedQueries()
        } catch {
            self.error = SpotQueryEditorError(
                message: "Delete failed: \(error.localizedDescription)", line: nil, column: nil
            )
        }
    }

    func refreshSavedQueries() async {
        savedQueries = await (try? store.list()) ?? []
    }

    // MARK: Private

    private let store = SavedQueryStores.makeStore()
    private var engine: SpotEngineApi?

    private func clearResults() {
        result = nil
        resultIsProfile = false
        error = nil
        rowLimit = Self.defaultRowLimit
    }

    /// Shared run/profile plumbing: hop off the main actor for the
    /// blocking FFI call, then publish the outcome.
    private func execute(
        _ operation: @escaping @Sendable (SpotEngineApi, String, UInt32) throws -> FfiQueryResultSet
    ) async {
        guard !isRunning, let engine else {
            return
        }
        isRunning = true
        defer { isRunning = false }

        let sql = sql
        let limit = rowLimit
        do {
            let resultSet = try await Task.detached(priority: .userInitiated) {
                try operation(engine, sql, limit)
            }.value
            result = resultSet
            error = nil
        } catch let SpotQueryError.Query(reason, line, column) {
            error = SpotQueryEditorError(message: reason, line: line, column: column)
            result = nil
        } catch {
            self.error = SpotQueryEditorError(
                message: error.localizedDescription, line: nil, column: nil
            )
            result = nil
        }
    }

    private func seedStarterQueriesIfNeeded() async {
        let existing = await (try? store.list()) ?? []
        guard existing.isEmpty else {
            return
        }
        for starter in StarterQueries.all {
            try? await store.save(starter)
        }
    }
}
