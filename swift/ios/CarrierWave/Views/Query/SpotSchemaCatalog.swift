import UIKit

// MARK: - SpotSchemaCatalog

/// Hand-curated catalog of every table the spot SQL editor can query,
/// with per-column descriptions. Ported from CW Sweep's `SchemaCatalog`
/// (minus Sweep's internal `meta` table) and re-worded for the shared
/// Rust engine's in-memory scope DB. Keep the copy in sync with the
/// engine's scope schema.
enum SpotSchemaCatalog {
    struct Table: Identifiable {
        let name: String
        let qualified: String
        let description: String
        let columns: [Column]

        var id: String {
            qualified
        }
    }

    struct Column: Identifiable {
        let name: String
        let type: String
        let isNullable: Bool
        let description: String

        var id: String {
            name
        }
    }

    static let tables: [Table] = spotTables + logTables
}

// MARK: - Live spot tables

extension SpotSchemaCatalog {
    static let spotTables: [Table] = [
        Table(
            name: "spots",
            qualified: "scope.spots",
            description: """
            Currently-visible deduplicated spots, one row per \
            (callsign, band) where the highest-priority observation wins. \
            Lives in the engine's transient scope DB — wiped on launch \
            and pruned continuously. Use this as the input for \
            saved-query spot filters (they must emit `spot_id`).
            """,
            columns: [
                Column(
                    name: "spot_id", type: "TEXT", isNullable: false,
                    description: "Engine-assigned id of the winning observation. "
                        + "REQUIRED in the result set for spot-filter queries."
                ),
                Column(
                    name: "callsign", type: "TEXT", isNullable: false,
                    description: "Spotted station callsign, uppercase."
                ),
                Column(
                    name: "band", type: "TEXT", isNullable: false,
                    description: "Band label (\"20m\", etc.) the spot is on."
                ),
                Column(
                    name: "mode", type: "TEXT", isNullable: false,
                    description: "Mode reported by the spotter (\"CW\", \"SSB\", \"FT8\", …)."
                ),
                Column(
                    name: "freq_hz", type: "INTEGER", isNullable: true,
                    description: "Frequency in Hz. Multiply / divide for kHz / MHz."
                ),
                Column(
                    name: "dxcc_entity", type: "TEXT", isNullable: true,
                    description: "Resolved DXCC entity name when known."
                ),
                Column(
                    name: "continent", type: "TEXT", isNullable: true,
                    description: "Two-letter continent of the spotted station."
                ),
                Column(
                    name: "cq_zone", type: "INTEGER", isNullable: true,
                    description: "CQ zone of the spotted station, if known."
                ),
                Column(
                    name: "itu_zone", type: "INTEGER", isNullable: true,
                    description: "ITU zone of the spotted station, if known."
                ),
                Column(
                    name: "grid", type: "TEXT", isNullable: true,
                    description: "Maidenhead grid square reported in the spot, if any."
                ),
                Column(
                    name: "park_ref", type: "TEXT", isNullable: true,
                    description: "POTA park reference for activator spots."
                ),
                Column(
                    name: "last_seen_at", type: "REAL", isNullable: false,
                    description: "Most recent observation time (epoch seconds)."
                ),
                Column(
                    name: "priority", type: "INTEGER", isNullable: false,
                    description: "Source priority — higher wins when the same call+band "
                        + "shows up from multiple sources."
                ),
            ]
        ),
        Table(
            name: "spot_observations",
            qualified: "scope.spot_observations",
            description: """
            Raw fan-out — one row per spot received from any source, kept \
            upstream of the dedup that produces `scope.spots`. Use for \
            skimmer counts, SNR analysis, source comparisons. Pruned to a \
            rolling window.
            """,
            columns: [
                Column(
                    name: "obs_id", type: "TEXT", isNullable: false,
                    description: "Per-observation id — unique even when the same callsign repeats."
                ),
                Column(
                    name: "spot_id", type: "TEXT", isNullable: false,
                    description: "Engine-side id; matches `scope.spots.spot_id` for the winning observation."
                ),
                Column(
                    name: "callsign", type: "TEXT", isNullable: false,
                    description: "Spotted station callsign."
                ),
                Column(
                    name: "band", type: "TEXT", isNullable: false,
                    description: "Band of the observation."
                ),
                Column(
                    name: "mode", type: "TEXT", isNullable: false,
                    description: "Mode of the observation."
                ),
                Column(
                    name: "freq_hz", type: "INTEGER", isNullable: true,
                    description: "Frequency in Hz."
                ),
                Column(
                    name: "source", type: "TEXT", isNullable: false,
                    description: "Source enum: rbn / pota / sota / wwff / pskr / "
                        + "dxSummit / dxHeat / dxWatch / cluster."
                ),
                Column(
                    name: "spotter", type: "TEXT", isNullable: true,
                    description: "Spotting station's callsign — RBN skimmer, cluster user, etc."
                ),
                Column(
                    name: "spot_lat", type: "REAL", isNullable: true,
                    description: "Spotted (DX) station latitude at observation time — grid centre "
                        + "when known, DXCC entity centroid otherwise."
                ),
                Column(
                    name: "spot_lon", type: "REAL", isNullable: true,
                    description: "Spotted (DX) station longitude — see spot_lat for resolution rules."
                ),
                Column(
                    name: "snr_db", type: "INTEGER", isNullable: true,
                    description: "Signal-to-noise reported by RBN skimmers, in dB."
                ),
                Column(
                    name: "speed_wpm", type: "INTEGER", isNullable: true,
                    description: "CW speed reported by RBN, in words per minute."
                ),
                Column(
                    name: "comment", type: "TEXT", isNullable: true,
                    description: "Spotter's comment text."
                ),
                Column(
                    name: "received_at", type: "REAL", isNullable: false,
                    description: "When the engine received the observation (epoch seconds)."
                ),
                Column(
                    name: "priority", type: "INTEGER", isNullable: false,
                    description: "Source priority used during dedup."
                ),
            ]
        ),
        Table(
            name: "spotters",
            qualified: "scope.spotters",
            description: """
            Roster of stations who spotted others. CTY-derived entity \
            centroid filled synchronously, refined by HamDB grid/lat/lon \
            when available. Use for "spots heard by EU skimmers" style \
            queries.
            """,
            columns: [
                Column(
                    name: "callsign", type: "TEXT", isNullable: false,
                    description: "Spotter's callsign, uppercase."
                ),
                Column(
                    name: "grid", type: "TEXT", isNullable: true,
                    description: "Maidenhead grid (HamDB-resolved when available)."
                ),
                Column(
                    name: "lat", type: "REAL", isNullable: true,
                    description: "Latitude in decimal degrees."
                ),
                Column(
                    name: "lon", type: "REAL", isNullable: true,
                    description: "Longitude in decimal degrees."
                ),
                Column(
                    name: "dxcc_entity", type: "TEXT", isNullable: true,
                    description: "Spotter's DXCC entity name."
                ),
                Column(
                    name: "continent", type: "TEXT", isNullable: true,
                    description: "Two-letter continent code."
                ),
                Column(
                    name: "is_skimmer", type: "INTEGER", isNullable: false,
                    description: "1 if the spot came from RBN (automated skimmer); "
                        + "0 if a human cluster spotter."
                ),
            ]
        ),
    ]
}

// MARK: - Log / reference tables

extension SpotSchemaCatalog {
    static let logTables: [Table] = [
        Table(
            name: "qsos",
            qualified: "qsos",
            description: """
            Slim mirror of your QSO log (newest entries), fed on demand \
            when the editor opens. Excludes metadata-mode entries \
            (WEATHER / SOLAR / NOTE); filter on `is_hidden = 0` to skip \
            soft-deleted contacts.
            """,
            columns: [
                Column(
                    name: "id", type: "TEXT", isNullable: false,
                    description: "QSO UUID matching the app's primary key (lowercase)."
                ),
                Column(
                    name: "callsign", type: "TEXT", isNullable: false,
                    description: "Worked station callsign, uppercase, no portable suffixes stripped."
                ),
                Column(
                    name: "band", type: "TEXT", isNullable: false,
                    description: "Amateur band label (e.g. \"20m\", \"160m\", \"6m\")."
                ),
                Column(
                    name: "mode", type: "TEXT", isNullable: false,
                    description: "Mode tag (CW / SSB / FT8 / RTTY / …)."
                ),
                Column(
                    name: "frequency", type: "REAL", isNullable: true,
                    description: "Frequency in MHz at QSO time, or NULL if not recorded."
                ),
                Column(
                    name: "timestamp", type: "REAL", isNullable: false,
                    description: "QSO start time as Unix epoch seconds (UTC)."
                ),
                Column(
                    name: "my_callsign", type: "TEXT", isNullable: false,
                    description: "Operating callsign — your station for this QSO."
                ),
                Column(
                    name: "their_grid", type: "TEXT", isNullable: true,
                    description: "Worked station's Maidenhead grid, 4 or 6 chars, NULL if unknown."
                ),
                Column(
                    name: "my_grid", type: "TEXT", isNullable: true,
                    description: "Your operating grid for this QSO."
                ),
                Column(
                    name: "park_ref", type: "TEXT", isNullable: true,
                    description: "POTA park reference (e.g. \"K-1234\") for activations; NULL otherwise."
                ),
                Column(
                    name: "their_park_ref", type: "TEXT", isNullable: true,
                    description: "P2P contact's park reference, NULL if their station wasn't activating."
                ),
                Column(
                    name: "dxcc", type: "INTEGER", isNullable: true,
                    description: "DXCC entity number (ARRL list)."
                ),
                Column(
                    name: "modified_at", type: "REAL", isNullable: true,
                    description: "Last edit time (epoch seconds)."
                ),
                Column(
                    name: "is_hidden", type: "INTEGER", isNullable: false,
                    description: "Soft-delete flag. 0 = visible, 1 = hidden. "
                        + "Most queries should filter `= 0`."
                ),
                Column(
                    name: "is_activity_log", type: "INTEGER", isNullable: false,
                    description: "1 = ad-hoc hunter-log entry; 0 = ordinary contact."
                ),
            ]
        ),
        Table(
            name: "dxcc",
            qualified: "dxcc",
            description: """
            DXCC entity reference table, seeded from CTY.dat. One row per \
            entity, with primary prefix and geographic / zone metadata. \
            JOIN against `scope.spots.callsign LIKE prefix || '%'` for \
            live classification.
            """,
            columns: [
                Column(
                    name: "entity", type: "TEXT", isNullable: false,
                    description: "Canonical entity name (e.g. \"United States\", \"Japan\")."
                ),
                Column(
                    name: "prefix", type: "TEXT", isNullable: true,
                    description: "Primary callsign prefix for the entity (e.g. \"K\", \"JA\")."
                ),
                Column(
                    name: "continent", type: "TEXT", isNullable: true,
                    description: "Two-letter continent code: NA, SA, EU, AF, AS, OC, AN."
                ),
                Column(
                    name: "cq_zone", type: "INTEGER", isNullable: true,
                    description: "CQ zone number (1–40)."
                ),
                Column(
                    name: "itu_zone", type: "INTEGER", isNullable: true,
                    description: "ITU zone number (1–90)."
                ),
                Column(
                    name: "lat", type: "REAL", isNullable: true,
                    description: "Centroid latitude in decimal degrees."
                ),
                Column(
                    name: "lon", type: "REAL", isNullable: true,
                    description: "Centroid longitude in decimal degrees."
                ),
            ]
        ),
        Table(
            name: "dxcc_status",
            qualified: "dxcc_status",
            description: """
            Entity × band × mode aggregation of `qsos` joined against \
            `dxcc`. One row per worked combination — absence of a row \
            means "not worked yet on that slot."
            """,
            columns: [
                Column(
                    name: "entity", type: "TEXT", isNullable: false,
                    description: "DXCC entity name (FK to `dxcc.entity`)."
                ),
                Column(
                    name: "band", type: "TEXT", isNullable: false,
                    description: "Band of QSOs counted in this row."
                ),
                Column(
                    name: "mode", type: "TEXT", isNullable: false,
                    description: "Mode of QSOs counted in this row."
                ),
                Column(
                    name: "worked_count", type: "INTEGER", isNullable: false,
                    description: "Distinct QSOs you've made on this entity / band / mode."
                ),
                Column(
                    name: "last_worked_at", type: "REAL", isNullable: true,
                    description: "Most recent QSO's timestamp on this slot (epoch seconds)."
                ),
                Column(
                    name: "continent", type: "TEXT", isNullable: true,
                    description: "Pulled from the joined dxcc row; convenience for region filters."
                ),
                Column(
                    name: "cq_zone", type: "INTEGER", isNullable: true,
                    description: "Pulled from the joined dxcc row."
                ),
            ]
        ),
        Table(
            name: "polo_notes",
            qualified: "polo_notes",
            description: """
            Ham2K Polo callsign-notes lists. Currently only populated \
            when a host feeds them to the engine — queries against an \
            unfed table return no rows.
            """,
            columns: [
                Column(
                    name: "callsign", type: "TEXT", isNullable: false,
                    description: "Callsign the note applies to (uppercase)."
                ),
                Column(
                    name: "tag", type: "TEXT", isNullable: true,
                    description: "Categorical marker — emoji if present, else parsed name."
                ),
                Column(
                    name: "body", type: "TEXT", isNullable: true,
                    description: "Free-form note text or operator name."
                ),
            ]
        ),
    ]
}
