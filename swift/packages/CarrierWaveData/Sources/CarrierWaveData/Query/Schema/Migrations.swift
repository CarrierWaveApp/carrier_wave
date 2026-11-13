import Foundation
import GRDB

enum QueryMigrations {
    // MARK: Internal

    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try createMetaTable(db)
            try createQSOsTable(db)
            try createDXCCTable(db)
            try createPoloNotesTable(db)
            try createDXCCStatusView(db)
        }

        migrator.registerMigration("v2") { db in
            try createOperatorProfilesTable(db)
        }

        return migrator
    }

    // MARK: Private

    private static func createMetaTable(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE meta (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT
            )
        """)
    }

    private static func createQSOsTable(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE qsos (
                id TEXT PRIMARY KEY NOT NULL,
                callsign TEXT NOT NULL,
                band TEXT NOT NULL,
                mode TEXT NOT NULL,
                frequency REAL,
                timestamp REAL NOT NULL,
                my_callsign TEXT NOT NULL,
                their_grid TEXT,
                my_grid TEXT,
                park_ref TEXT,
                their_park_ref TEXT,
                dxcc INTEGER,
                modified_at REAL,
                is_hidden INTEGER NOT NULL DEFAULT 0,
                is_activity_log INTEGER NOT NULL DEFAULT 0
            )
        """)
        try db.execute(sql: "CREATE INDEX qsos_callsign ON qsos(callsign)")
        try db.execute(sql: "CREATE INDEX qsos_band_mode ON qsos(band, mode)")
        try db.execute(sql: "CREATE INDEX qsos_dxcc ON qsos(dxcc)")
        try db.execute(sql: "CREATE INDEX qsos_timestamp ON qsos(timestamp)")
    }

    private static func createDXCCTable(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE dxcc (
                entity TEXT PRIMARY KEY NOT NULL,
                prefix TEXT,
                continent TEXT,
                cq_zone INTEGER,
                itu_zone INTEGER,
                lat REAL,
                lon REAL
            )
        """)
        try db.execute(sql: "CREATE INDEX dxcc_continent ON dxcc(continent)")
    }

    private static func createPoloNotesTable(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE polo_notes (
                callsign TEXT PRIMARY KEY NOT NULL,
                tag TEXT,
                body TEXT
            )
        """)
    }

    /// Per-callsign cached operator profile. Populated from the user's prior QSOs
    /// on first launch (offline source of truth) and refreshed whenever a QRZ
    /// lookup returns differing data. HamDB results are intentionally NOT
    /// written here so they never overwrite richer QRZ/QSO-derived info.
    private static func createOperatorProfilesTable(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE operator_profiles (
                callsign TEXT PRIMARY KEY NOT NULL,
                name TEXT,
                first_name TEXT,
                nickname TEXT,
                qth TEXT,
                state TEXT,
                country TEXT,
                grid TEXT,
                license_class TEXT,
                source TEXT NOT NULL,
                updated_at REAL NOT NULL,
                enriched_at REAL
            )
        """)
    }

    private static func createDXCCStatusView(_ db: Database) throws {
        try db.execute(sql: """
            CREATE VIEW dxcc_status AS
            SELECT
                dxcc.entity AS entity,
                qsos.band AS band,
                qsos.mode AS mode,
                COUNT(qsos.id) AS worked_count,
                MAX(qsos.timestamp) AS last_worked_at,
                dxcc.continent AS continent,
                dxcc.cq_zone AS cq_zone
            FROM dxcc
            LEFT JOIN qsos ON qsos.dxcc IS NOT NULL
                AND CAST(qsos.dxcc AS TEXT) = dxcc.entity
                AND qsos.is_hidden = 0
            GROUP BY dxcc.entity, qsos.band, qsos.mode
        """)
    }
}
