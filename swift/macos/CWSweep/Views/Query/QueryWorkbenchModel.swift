import CarrierWaveData
import Foundation
import GRDB
import OSLog
import SwiftUI

@MainActor
@Observable
final class QueryWorkbenchModel {
    // MARK: Lifecycle

    init(store: QueryStore, savedQueryStore: SavedQueryStore) {
        self.store = store
        self.savedQueryStore = savedQueryStore
    }

    // MARK: Internal

    var sql: String = "SELECT * FROM qsos LIMIT 50;"
    var selectedQueryID: UUID?
    var savedQueries: [SavedQuery] = []
    var result: QueryResultSet?
    var profile: QueryProfile?
    var error: SQLQueryError?
    var isRunning = false
    /// User-overridable result row cap. Resets to QueryReader.defaultRowLimit
    /// each time a fresh query is selected/run; "show more" doubles it.
    var rowLimit: Int = QueryReader.defaultRowLimit

    /// True when the editor's SQL diverges from the on-disk version of
    /// the currently-selected saved query. Drives the dirty marker on
    /// the editor and enables/disables the "Save" toolbar button.
    var hasUnsavedChanges: Bool {
        guard let selectedQueryID,
              let saved = savedQueries.first(where: { $0.id == selectedQueryID })
        else {
            // No selection — treat any non-empty editor as "unsaved",
            // since the user might want to "Save As…" it.
            return !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return sql != saved.sql
    }

    /// Resolve the currently-selected `SavedQuery`, if one exists.
    var selectedQuery: SavedQuery? {
        guard let selectedQueryID else {
            return nil
        }
        return savedQueries.first { $0.id == selectedQueryID }
    }

    func bootstrap() async {
        await ensureReader()
        await seedStarterQueriesIfNeeded()
        await refreshSavedQueries()
    }

    func selectQuery(_ query: SavedQuery) {
        selectedQueryID = query.id
        sql = query.sql
        result = nil
        profile = nil
        error = nil
        rowLimit = QueryReader.defaultRowLimit
    }

    /// Clear the selection and editor for a fresh scratch query. The
    /// user will land in the "no saved query" state — typing then
    /// clicking Save opens the name/description sheet via
    /// `saveCurrent`.
    func newQuery() {
        selectedQueryID = nil
        sql = "SELECT * FROM scope.spots LIMIT 50;"
        result = nil
        profile = nil
        error = nil
        rowLimit = QueryReader.defaultRowLimit
    }

    /// Revert the editor to the on-disk version of the selected query
    /// (or to a blank scratch state if nothing is selected). Used by
    /// the "Discard" action in the close-without-saving prompt.
    func discardChanges() {
        if let saved = selectedQuery {
            sql = saved.sql
        } else {
            sql = ""
        }
        error = nil
    }

    /// Pretty-print the editor's SQL via `SQLFormatter`. Idempotent —
    /// a second click is a no-op when the formatter has nothing to
    /// fix. Treated as a regular edit so the dirty marker turns
    /// orange until the user saves.
    func formatSQL() {
        let formatted = SQLFormatter.format(sql)
        if formatted != sql {
            sql = formatted
        }
    }

    func runQuery() async {
        guard !isRunning else {
            return
        }
        isRunning = true
        defer { isRunning = false }

        await ensureReader()
        guard let reader else {
            return
        }

        do {
            let resultSet = try await reader.run(sql: sql, rowLimit: rowLimit)
            result = resultSet
            profile = nil
            error = nil
        } catch let queryError as SQLQueryError {
            error = queryError
            result = nil
            profile = nil
        } catch let other as Error {
            self.error = SQLQueryError(
                message: other.localizedDescription,
                sql: sql,
                errorOffset: nil
            )
        }
    }

    /// Double the visible row cap and re-run. Capped at the underlying
    /// query's actual row count so we don't spin if the user clicks
    /// past the end.
    func showMore() async {
        guard let result, result.truncated else {
            return
        }
        rowLimit = max(rowLimit * 2, result.rowCount)
        await runQuery()
    }

    /// Cancel the in-flight query by sending sqlite3_interrupt to the
    /// read-only connection. `runQuery` will surface the interrupt as
    /// a SQLite "interrupted" error.
    func cancelRunning() {
        guard isRunning, let reader else {
            return
        }
        reader.interrupt()
    }

    func profileQuery() async {
        guard !isRunning else {
            return
        }
        isRunning = true
        defer { isRunning = false }

        await ensureReader()
        guard let reader else {
            return
        }

        do {
            let (resultSet, prof) = try await reader.profile(sql: sql)
            result = resultSet
            profile = prof
            error = nil
        } catch let queryError as SQLQueryError {
            error = queryError
        } catch let other as Error {
            self.error = SQLQueryError(
                message: other.localizedDescription,
                sql: sql,
                errorOffset: nil
            )
        }
    }

    func saveCurrent(name: String, description: String) async {
        let query = SavedQuery(name: name, description: description, sql: sql)
        do {
            try await savedQueryStore.save(query)
            await refreshSavedQueries()
            selectedQueryID = query.id
            Self.notifyChanged()
        } catch {
            logger.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Persist the editor's current SQL onto the selected saved query,
    /// preserving its id / name / description. No-op if nothing is
    /// selected — caller should fall back to `saveCurrent` to create
    /// a new query.
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
            try await savedQueryStore.save(updated)
            await refreshSavedQueries()
            Self.notifyChanged()
        } catch {
            logger.error("save-over failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Update only the name + description of an existing saved query.
    /// Renames cause the on-disk filename to change (the store
    /// embeds the name in the path), so we delete the old file
    /// before writing the new one.
    func rename(_ query: SavedQuery, to newName: String, description: String) async {
        let updated = SavedQuery(
            id: query.id,
            name: newName,
            description: description,
            sql: query.sql,
            schemaVersion: query.schemaVersion,
            createdAt: query.createdAt,
            columnHints: query.columnHints
        )
        do {
            if newName != query.name {
                try? await savedQueryStore.delete(query)
            }
            try await savedQueryStore.save(updated)
            await refreshSavedQueries()
            Self.notifyChanged()
        } catch {
            logger.error("rename failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clone a saved query under a new id and a "(copy)" suffix.
    /// The duplicate is selected so the user can edit it immediately.
    func duplicate(_ query: SavedQuery) async {
        let copy = SavedQuery(
            id: UUID(),
            name: "\(query.name) (copy)",
            description: query.description,
            sql: query.sql,
            schemaVersion: query.schemaVersion,
            createdAt: Date(),
            columnHints: query.columnHints
        )
        do {
            try await savedQueryStore.save(copy)
            await refreshSavedQueries()
            selectQuery(copy)
            Self.notifyChanged()
        } catch {
            logger.error("duplicate failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func delete(_ query: SavedQuery) async {
        do {
            try await savedQueryStore.delete(query)
            if selectedQueryID == query.id {
                selectedQueryID = nil
            }
            await refreshSavedQueries()
            Self.notifyChanged()
        } catch {
            logger.error("delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func importFrom(url: URL) async {
        do {
            let query = try SavedQueryURL.decode(url)
            let imported = try await savedQueryStore.importQuery(query)
            await refreshSavedQueries()
            selectQuery(imported)
            Self.notifyChanged()
        } catch let SavedQueryStore.ImportError.schemaTooNew(authored, supported) {
            error = SQLQueryError(
                message: "Saved on schema v\(authored); this app supports v\(supported). Update the app.",
                sql: "",
                errorOffset: nil
            )
        } catch {
            self.error = SQLQueryError(
                message: "Import failed: \(error.localizedDescription)",
                sql: "",
                errorOffset: nil
            )
        }
    }

    func shareURL(for query: SavedQuery) -> URL? {
        try? SavedQueryURL.encode(query)
    }

    // MARK: Private

    private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "QueryWorkbench")
    private let store: QueryStore
    private let savedQueryStore: SavedQueryStore
    private var reader: QueryReader?

    /// Broadcast on every CRUD against the saved-query store so other
    /// views (band scope filter pickers) can re-validate without
    /// poll-based checks.
    private static func notifyChanged() {
        NotificationCenter.default.post(name: .savedQueriesChanged, object: nil)
    }

    private func seedStarterQueriesIfNeeded() async {
        let existing = await (try? savedQueryStore.list()) ?? []
        guard existing.isEmpty else {
            return
        }
        for starter in StarterQueries.all {
            try? await savedQueryStore.save(starter)
        }
    }

    private func ensureReader() async {
        if reader != nil {
            return
        }
        do {
            let queue = try await store.openReader()
            reader = QueryReader(reader: queue)
        } catch {
            logger.error("openReader failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshSavedQueries() async {
        do {
            savedQueries = try await savedQueryStore.list()
        } catch {
            savedQueries = []
        }
    }
}
