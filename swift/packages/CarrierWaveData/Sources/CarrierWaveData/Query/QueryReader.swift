import Foundation
import GRDB
import OSLog
import SQLite3

public actor QueryReader {
    // MARK: Lifecycle

    public init(reader: DatabaseQueue) {
        self.reader = reader
    }

    // MARK: Public

    public static let defaultRowLimit = 5_000

    public func run(sql: String, rowLimit: Int = defaultRowLimit) throws -> QueryResultSet {
        try executeOnReader(sql: sql) { db in
            try Self.execute(db: db, sql: sql, rowLimit: rowLimit)
        }
    }

    public func explain(sql: String) throws -> [QueryPlanRow] {
        try executeOnReader(sql: sql) { db in
            let planSQL = "EXPLAIN QUERY PLAN \(sql)"
            let rows = try Row.fetchAll(db, sql: planSQL)
            return rows.map { row -> QueryPlanRow in
                // EXPLAIN QUERY PLAN columns: id, parent, notused, detail.
                let id = (row["id"] as Int?) ?? 0
                let parent = (row["parent"] as Int?) ?? 0
                let detail = (row["detail"] as String?) ?? row.description
                return QueryPlanRow(id: id, parent: parent, detail: detail)
            }
        }
    }

    public func profile(sql: String, rowLimit: Int = defaultRowLimit) throws -> (QueryResultSet, QueryProfile) {
        let plan = try explain(sql: sql)
        let start = Date()
        let result = try run(sql: sql, rowLimit: rowLimit)
        let elapsed = Date().timeIntervalSince(start) * 1_000.0
        return (result, QueryProfile(plan: plan, wallClockMillis: elapsed))
    }

    /// Send `sqlite3_interrupt` to the read-only connection so a
    /// long-running query can be aborted from the UI. `nonisolated`
    /// because awaiting the actor would queue this call behind the
    /// running query — defeating the purpose. Thread-safety comes
    /// from a manual `NSLock` around the captured handle.
    /// `sqlite3_interrupt` itself is documented as thread-safe.
    nonisolated public func interrupt() {
        activeHandle.lock.withLock {
            if let conn = activeHandle.handle {
                sqlite3_interrupt(conn)
            }
        }
    }

    /// Prepare the statement and return its output column names without
    /// running it. Used to validate that a saved query has the shape a
    /// caller expects (e.g. the band scope filter requires `spot_id`)
    /// before subscribing to repeated executions.
    public func columnNames(sql: String) throws -> [String] {
        try executeOnReader(sql: sql) { db in
            try db.makeStatement(sql: sql).columnNames
        }
    }

    // MARK: Private

    /// Lock-protected box holding the SQLite connection currently
    /// executing a read. We can't reach the actor's state from a
    /// `nonisolated` `interrupt()`, so we keep this side channel
    /// (set on entry to a read closure, cleared on exit).
    private final class HandleBox: @unchecked Sendable {
        let lock = NSLock()
        var handle: OpaquePointer?
    }

    /// Wraps a `DatabaseError` together with the SQLite error offset
    /// captured in the same closure invocation. We can't write to a
    /// mutable outer var from a `@Sendable` closure, so we smuggle the
    /// offset back out as part of a custom error.
    private struct PreparedError: Error {
        let offset: Int?
        let inner: DatabaseError
    }

    private let activeHandle = HandleBox()
    private let logger = Logger(subsystem: "com.fullduplex.shared", category: "QueryReader")
    private let reader: DatabaseQueue

    private static func execute(db: Database, sql: String, rowLimit: Int) throws -> QueryResultSet {
        // Read column metadata from the prepared statement BEFORE
        // stepping the cursor. Reading from the first row's
        // `columnNames` only works when the query returns ≥1 row —
        // queries with a `WHERE 1=0`, an empty source table, or any
        // restrictive predicate would silently report zero columns
        // and break shape-based validation downstream.
        let statement = try db.makeStatement(sql: sql)
        let columns = statement.columnNames.map {
            QueryColumn(name: $0, declaredType: nil)
        }
        let cursor = try Row.fetchCursor(statement)
        var rows: [[QueryValue]] = []
        var truncated = false
        var seenCount = 0

        while let row = try cursor.next() {
            seenCount += 1
            if rows.count >= rowLimit {
                truncated = true
                continue
            }
            rows.append(Self.values(from: row))
        }

        return QueryResultSet(
            columns: columns,
            rows: rows,
            rowCount: seenCount,
            truncated: truncated
        )
    }

    private static func values(from row: Row) -> [QueryValue] {
        (0 ..< row.count).map { idx in
            let value = row[idx] as DatabaseValue
            switch value.storage {
            case .null:
                return .null
            case let .int64(int):
                return .integer(int)
            case let .double(dbl):
                return .double(dbl)
            case let .string(str):
                return .text(str)
            case let .blob(data):
                return .blob(data)
            }
        }
    }

    private static func queryError(
        from error: DatabaseError,
        sql: String,
        errorOffset: Int?
    ) -> SQLQueryError {
        SQLQueryError(
            message: error.message ?? error.description,
            sql: sql,
            errorOffset: errorOffset
        )
    }

    /// Run `body` inside the read-only queue, capturing the error offset
    /// from the SQLite connection on the same closure invocation that
    /// fails. The offset is only meaningful while the connection's last
    /// error state hasn't been overwritten — reading it after the
    /// closure exits is racy.
    private func executeOnReader<T>(
        sql: String,
        _ body: @Sendable (Database) throws -> T
    ) throws -> T {
        let handleStore = activeHandle
        do {
            return try reader.read { db in
                handleStore.lock.withLock { handleStore.handle = db.sqliteConnection }
                defer { handleStore.lock.withLock { handleStore.handle = nil } }
                do {
                    return try body(db)
                } catch let error as DatabaseError {
                    let offset: Int? = db.sqliteConnection.flatMap { conn in
                        let off = sqlite3_error_offset(conn)
                        return off >= 0 ? Int(off) : nil
                    }
                    throw PreparedError(offset: offset, inner: error)
                }
            }
        } catch let prepared as PreparedError {
            throw Self.queryError(
                from: prepared.inner,
                sql: sql,
                errorOffset: prepared.offset
            )
        } catch let error as DatabaseError {
            throw Self.queryError(from: error, sql: sql, errorOffset: nil)
        }
    }
}
