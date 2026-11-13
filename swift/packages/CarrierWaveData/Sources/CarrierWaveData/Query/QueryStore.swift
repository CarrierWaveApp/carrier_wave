import Foundation
import GRDB
import OSLog

public actor QueryStore {
    // MARK: Lifecycle

    public init(
        databaseURL: URL,
        scopeURL: URL,
        userGridProvider: @escaping @Sendable () -> String? = QuerySQLFunctions
            .defaultUserGridProvider
    ) throws {
        let parent = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let scopeParent = scopeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: scopeParent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: scopeURL.path) {
            try FileManager.default.removeItem(at: scopeURL)
        }
        databasePath = databaseURL.path
        scopePath = scopeURL.path
        self.userGridProvider = userGridProvider
        let resolvedScopePath = scopePath
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(
                sql: "ATTACH DATABASE ? AS scope",
                arguments: [resolvedScopePath]
            )
            try ScopeSchema.apply(to: db)
        }
        writer = try DatabaseQueue(path: databasePath, configuration: config)
        try QueryMigrations.makeMigrator().migrate(writer)
    }

    // MARK: Public

    public enum StoreError: Error {
        case notReady
    }

    public var path: String {
        databasePath
    }

    public var scopeFilePath: String {
        scopePath
    }

    public func openReader() throws -> DatabaseQueue {
        let scopePathCopy = scopePath
        let provider = userGridProvider
        var config = Configuration()
        config.readonly = true
        config.prepareDatabase { db in
            try db.execute(
                sql: "ATTACH DATABASE ? AS scope",
                arguments: [scopePathCopy]
            )
            try db.execute(sql: "PRAGMA query_only = ON")
            QuerySQLFunctions.register(on: db, userGridProvider: provider)
        }
        return try DatabaseQueue(path: databasePath, configuration: config)
    }

    // MARK: - QSOs

    public func upsertQSO(_ row: QSORow) throws {
        try writer.write { db in
            try row.save(db)
        }
    }

    public func upsertQSOs(_ rows: [QSORow]) throws {
        try writer.write { db in
            for row in rows {
                try row.save(db)
            }
        }
    }

    public func deleteQSO(id: String) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM qsos WHERE id = ?", arguments: [id])
        }
    }

    public func qsoCount() throws -> Int {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM qsos") ?? 0
        }
    }

    public func qsoSeedWatermark() throws -> Date? {
        try writer.read { db in
            let value = try String.fetchOne(
                db,
                sql: "SELECT value FROM meta WHERE key = 'qso_seed_watermark'"
            )
            guard let value, let interval = TimeInterval(value) else {
                return nil
            }
            return Date(timeIntervalSince1970: interval)
        }
    }

    public func setQSOSeedWatermark(_ date: Date) throws {
        try writer.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('qso_seed_watermark', ?)",
                arguments: [String(date.timeIntervalSince1970)]
            )
        }
    }

    // MARK: - Operator profiles

    /// Fetch a single cached operator profile by callsign (case-insensitive).
    public func operatorProfile(callsign: String) throws -> OperatorProfileRow? {
        let key = callsign.uppercased()
        return try writer.read { db in
            try OperatorProfileRow.fetchOne(db, key: key)
        }
    }

    /// Upsert a single operator profile.
    public func upsertOperatorProfile(_ row: OperatorProfileRow) throws {
        try writer.write { db in
            try row.save(db)
        }
    }

    /// Bulk upsert in a single transaction. Used by the QSO-history backfill.
    public func upsertOperatorProfiles(_ rows: [OperatorProfileRow]) throws {
        guard !rows.isEmpty else {
            return
        }
        try writer.write { db in
            for row in rows {
                try row.save(db)
            }
        }
    }

    /// Delete a cached operator profile. Used when a remote lookup
    /// forward-resolves a callsign to a different current call — the row
    /// keyed by the old call would otherwise be served forever (no TTL).
    public func deleteOperatorProfile(callsign: String) throws {
        let key = callsign.uppercased()
        _ = try writer.write { db in
            try OperatorProfileRow.deleteOne(db, key: key)
        }
    }

    public func operatorProfileCount() throws -> Int {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM operator_profiles") ?? 0
        }
    }

    /// Watermark of the last QSO `modifiedAt` (or `timestamp`) consumed by the
    /// operator-profile backfill. Used to skip rows on subsequent launches.
    public func operatorBackfillWatermark() throws -> Date? {
        try writer.read { db in
            let value = try String.fetchOne(
                db,
                sql: "SELECT value FROM meta WHERE key = 'operator_backfill_watermark'"
            )
            guard let value, let interval = TimeInterval(value) else {
                return nil
            }
            return Date(timeIntervalSince1970: interval)
        }
    }

    public func setOperatorBackfillWatermark(_ date: Date) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO meta (key, value)
                    VALUES ('operator_backfill_watermark', ?)
                """,
                arguments: [String(date.timeIntervalSince1970)]
            )
        }
    }

    // MARK: - DXCC

    public func seedDXCC(_ rows: [DXCCRow]) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM dxcc")
            for row in rows {
                try row.insert(db)
            }
        }
    }

    // MARK: - Polo Notes

    public func upsertPoloNote(_ row: PoloNoteRow) throws {
        try writer.write { db in
            try row.save(db)
        }
    }

    public func deletePoloNote(callsign: String) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM polo_notes WHERE callsign = ?", arguments: [callsign])
        }
    }

    /// Replace the polo_notes table contents in a single transaction.
    /// Used when the upstream notes list is re-downloaded and the entire
    /// snapshot is authoritative (no diffing).
    public func seedPoloNotes(_ rows: [PoloNoteRow]) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM polo_notes")
            for row in rows {
                try row.insert(db)
            }
        }
    }

    // MARK: - Spot scope

    public func recordObservations(_ rows: [SpotObservationRow]) throws {
        try writer.write { db in
            for row in rows {
                try row.insert(db)
                try upsertSpotProjection(db: db, observation: row)
            }
        }
    }

    public func upsertSpotter(_ row: SpotterRow) throws {
        try writer.write { db in
            try row.save(db)
        }
    }

    public func pruneScope(window: TimeInterval) throws {
        let cutoff = Date().addingTimeInterval(-window).timeIntervalSince1970
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM scope.spot_observations WHERE received_at < ?",
                arguments: [cutoff]
            )
            try db.execute(sql: """
                DELETE FROM scope.spots
                WHERE NOT EXISTS (
                    SELECT 1 FROM scope.spot_observations
                    WHERE spot_observations.callsign = spots.callsign
                      AND spot_observations.band = spots.band
                )
            """)
        }
    }

    public func observationCount() throws -> Int {
        try writer.read { db in
            (try? Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scope.spot_observations")) ?? 0
        }
    }

    public func spotCount() throws -> Int {
        try writer.read { db in
            (try? Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scope.spots")) ?? 0
        }
    }

    // MARK: Private

    private let logger = Logger(subsystem: "com.fullduplex.shared", category: "QueryStore")
    private let writer: DatabaseQueue
    private let databasePath: String
    private let scopePath: String
    private let userGridProvider: @Sendable () -> String?

    private func upsertSpotProjection(db: Database, observation: SpotObservationRow) throws {
        try db.execute(sql: """
            INSERT INTO scope.spots (
                spot_id, callsign, band, mode, freq_hz, last_seen_at, priority
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(callsign, band) DO UPDATE SET
                spot_id = CASE WHEN excluded.priority >= spots.priority
                               THEN excluded.spot_id ELSE spots.spot_id END,
                mode = CASE WHEN excluded.priority >= spots.priority
                            THEN excluded.mode ELSE spots.mode END,
                freq_hz = CASE WHEN excluded.priority >= spots.priority
                               THEN excluded.freq_hz ELSE spots.freq_hz END,
                last_seen_at = MAX(spots.last_seen_at, excluded.last_seen_at),
                priority = MAX(spots.priority, excluded.priority)
        """, arguments: [
            observation.spotId,
            observation.callsign,
            observation.band,
            observation.mode,
            observation.freqHz,
            observation.receivedAt.timeIntervalSince1970,
            observation.priority,
        ])
    }
}
