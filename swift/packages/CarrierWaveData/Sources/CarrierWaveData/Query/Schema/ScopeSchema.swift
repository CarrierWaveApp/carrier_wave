import Foundation
import GRDB

enum ScopeSchema {
    // MARK: Internal

    static func apply(to db: Database) throws {
        try createSpotsTable(db)
        try createSpotObservationsTable(db)
        try createSpottersTable(db)
    }

    // MARK: Private

    private static func createSpotsTable(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS scope.spots (
                spot_id TEXT PRIMARY KEY NOT NULL,
                callsign TEXT NOT NULL,
                band TEXT NOT NULL,
                mode TEXT NOT NULL,
                freq_hz INTEGER,
                dxcc_entity TEXT,
                continent TEXT,
                cq_zone INTEGER,
                itu_zone INTEGER,
                grid TEXT,
                park_ref TEXT,
                last_seen_at REAL NOT NULL,
                priority INTEGER NOT NULL DEFAULT 0,
                UNIQUE(callsign, band)
            )
        """)
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS scope.spots_band ON spots(band)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS scope.spots_callsign ON spots(callsign)")
    }

    private static func createSpotObservationsTable(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS scope.spot_observations (
                obs_id TEXT PRIMARY KEY NOT NULL,
                spot_id TEXT NOT NULL,
                callsign TEXT NOT NULL,
                band TEXT NOT NULL,
                mode TEXT NOT NULL,
                freq_hz INTEGER,
                source TEXT NOT NULL,
                spotter TEXT,
                spot_lat REAL,
                spot_lon REAL,
                snr_db INTEGER,
                speed_wpm INTEGER,
                comment TEXT,
                received_at REAL NOT NULL,
                priority INTEGER NOT NULL DEFAULT 0
            )
        """)
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS scope.obs_callsign_band ON spot_observations(callsign, band)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS scope.obs_source ON spot_observations(source)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS scope.obs_received_at ON spot_observations(received_at)")
    }

    private static func createSpottersTable(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS scope.spotters (
                callsign TEXT PRIMARY KEY NOT NULL,
                grid TEXT,
                lat REAL,
                lon REAL,
                dxcc_entity TEXT,
                continent TEXT,
                is_skimmer INTEGER NOT NULL DEFAULT 0
            )
        """)
    }
}
