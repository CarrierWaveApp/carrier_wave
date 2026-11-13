// swiftlint:disable type_body_length
import Foundation

// MARK: - SchemaCatalog

/// Hand-curated catalog of every table / view the Query Workbench can
/// query, with per-column descriptions. Lives here rather than being
/// extracted from `sqlite_master` + `PRAGMA table_info` so we can
/// document semantics SQLite doesn't carry — what each enum-valued
/// `source` string means, why timestamps are unix epoch, which
/// columns are stable vs transient, etc.
///
/// Sourced by reading `Schema/Migrations.swift` and
/// `Schema/ScopeSchema.swift` and matching column meanings to their
/// `Models/*Row.swift` writers. Keep in sync with those files.
enum SchemaCatalog {
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
        let isPrimaryKey: Bool
        let isNullable: Bool
        let description: String

        var id: String {
            name
        }
    }

    static let tables: [Table] = [
        Table(
            name: "qsos",
            qualified: "qsos",
            description: """
            Slim mirror of the SwiftData QSO log, watermark-synced from \
            the canonical store. Excludes metadata-mode entries (WEATHER \
            / SOLAR / NOTE) and hidden QSOs by default — filter on \
            `is_hidden = 0` to be safe.
            """,
            columns: [
                .init(
                    name: "id", type: "TEXT", isPrimaryKey: true, isNullable: false,
                    description: "QSO UUID matching SwiftData's primary key."
                ),
                .init(
                    name: "callsign", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Worked station callsign, uppercase, no portable suffixes stripped."
                ),
                .init(
                    name: "band", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Amateur band label (e.g. \"20m\", \"160m\", \"6m\")."
                ),
                .init(
                    name: "mode", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Mode tag (CW / SSB / FT8 / RTTY / …)."
                ),
                .init(
                    name: "frequency", type: "REAL", isPrimaryKey: false, isNullable: true,
                    description: "Frequency in MHz at QSO time, or NULL if not recorded."
                ),
                .init(
                    name: "timestamp", type: "REAL", isPrimaryKey: false, isNullable: false,
                    description: "QSO start time as Unix epoch seconds (UTC)."
                ),
                .init(
                    name: "my_callsign", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Operating callsign — your station for this QSO, supports multi-callsign logbooks."
                ),
                .init(
                    name: "their_grid", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Worked station's Maidenhead grid, 4 or 6 chars, NULL if unknown."
                ),
                .init(
                    name: "my_grid", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Your operating grid for this QSO."
                ),
                .init(
                    name: "park_ref", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "POTA park reference (e.g. \"K-1234\") for activations; NULL otherwise."
                ),
                .init(
                    name: "their_park_ref", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "P2P contact's park reference, NULL if their station wasn't activating."
                ),
                .init(
                    name: "dxcc", type: "INTEGER", isPrimaryKey: false, isNullable: true,
                    description:
                    "DXCC entity number (ARRL list). Stored as integer; cast to TEXT to join `dxcc.entity`."
                ),
                .init(
                    name: "modified_at", type: "REAL", isPrimaryKey: false, isNullable: true,
                    description: "Last edit time (epoch seconds). Drives the seed coordinator's watermark sync."
                ),
                .init(
                    name: "is_hidden", type: "INTEGER", isPrimaryKey: false, isNullable: false,
                    description: "Soft-delete flag. 0 = visible, 1 = hidden. Most queries should filter `= 0`."
                ),
                .init(
                    name: "is_activity_log", type: "INTEGER", isPrimaryKey: false, isNullable: false,
                    description: "1 = ad-hoc activity entry (not a real radio QSO); 0 = ordinary contact."
                ),
            ]
        ),
        Table(
            name: "dxcc",
            qualified: "dxcc",
            description: """
            DXCC entity reference table, seeded from CTY.dat on app \
            launch. One row per entity, with primary prefix and \
            geographic / zone metadata. JOIN against `qsos.dxcc` to \
            tag QSOs with continent / zones, or against \
            `scope.spots.callsign LIKE prefix || '%'` for live \
            classification.
            """,
            columns: [
                .init(
                    name: "entity", type: "TEXT", isPrimaryKey: true, isNullable: false,
                    description: "Canonical entity name (e.g. \"United States\", \"Japan\")."
                ),
                .init(
                    name: "prefix", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Primary callsign prefix for the entity (e.g. \"K\", \"JA\")."
                ),
                .init(
                    name: "continent", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Two-letter continent code: NA, SA, EU, AF, AS, OC, AN."
                ),
                .init(
                    name: "cq_zone", type: "INTEGER", isPrimaryKey: false, isNullable: true,
                    description: "CQ zone number (1–40)."
                ),
                .init(
                    name: "itu_zone", type: "INTEGER", isPrimaryKey: false, isNullable: true,
                    description: "ITU zone number (1–90)."
                ),
                .init(
                    name: "lat", type: "REAL", isPrimaryKey: false, isNullable: true,
                    description: "Centroid latitude in decimal degrees."
                ),
                .init(
                    name: "lon", type: "REAL", isPrimaryKey: false, isNullable: true,
                    description: "Centroid longitude in decimal degrees."
                ),
            ]
        ),
        Table(
            name: "dxcc_status",
            qualified: "dxcc_status",
            description: """
            View — entity × band × mode aggregation of `qsos` joined \
            against `dxcc`. One row per worked combination. \
            `worked_count = 0` rows aren't emitted; absence of a row \
            means \"not worked yet on that slot.\"
            """,
            columns: [
                .init(
                    name: "entity", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "DXCC entity name (FK to `dxcc.entity`)."
                ),
                .init(
                    name: "band", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Band of QSOs counted in this row."
                ),
                .init(
                    name: "mode", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Mode of QSOs counted in this row."
                ),
                .init(
                    name: "worked_count", type: "INTEGER", isPrimaryKey: false, isNullable: false,
                    description: "Distinct QSOs you've made on this entity / band / mode."
                ),
                .init(
                    name: "last_worked_at", type: "REAL", isPrimaryKey: false, isNullable: true,
                    description: "Most recent QSO's timestamp on this slot (epoch seconds)."
                ),
                .init(
                    name: "continent", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Pulled from the joined dxcc row; convenience for region filters."
                ),
                .init(
                    name: "cq_zone", type: "INTEGER", isPrimaryKey: false, isNullable: true,
                    description: "Pulled from the joined dxcc row."
                ),
            ]
        ),
        Table(
            name: "polo_notes",
            qualified: "polo_notes",
            description: """
            Ham2K Polo callsign-notes lists, downloaded from configured \
            URLs and replaced wholesale on each refresh. Use to flag \
            callsigns you care about (good operators, club members, \
            blacklist).
            """,
            columns: [
                .init(
                    name: "callsign", type: "TEXT", isPrimaryKey: true, isNullable: false,
                    description: "Callsign the note applies to (uppercase)."
                ),
                .init(
                    name: "tag", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Categorical marker — emoji if present, else parsed name."
                ),
                .init(
                    name: "body", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Free-form note text or operator name."
                ),
            ]
        ),
        Table(
            name: "meta",
            qualified: "meta",
            description: """
            Internal key/value store for CW Sweep itself \
            (watermarks, schema version markers). Not generally useful \
            for user queries.
            """,
            columns: [
                .init(
                    name: "key", type: "TEXT", isPrimaryKey: true, isNullable: false,
                    description: "Setting name (e.g. \"qso_seed_watermark\")."
                ),
                .init(
                    name: "value", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Encoded setting value (often a stringified number or JSON)."
                ),
            ]
        ),
        Table(
            name: "spots",
            qualified: "scope.spots",
            description: """
            Currently-visible deduplicated spots, one row per \
            (callsign, band) where the highest-priority observation wins. \
            Lives in the transient scope DB — wiped on launch and \
            pruned every 60s. Use this as the input for band-scope \
            filter queries.
            """,
            columns: [
                .init(
                    name: "spot_id", type: "TEXT", isPrimaryKey: true, isNullable: false,
                    description:
                    "Aggregator-assigned UUID of the winning observation. REQUIRED for band-scope filter queries."
                ),
                .init(
                    name: "callsign", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Spotted station callsign, uppercase."
                ),
                .init(
                    name: "band", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Band label (\"20m\", etc.) the spot is on."
                ),
                .init(
                    name: "mode", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Mode reported by the spotter (\"CW\", \"SSB\", \"FT8\", …)."
                ),
                .init(
                    name: "freq_hz", type: "INTEGER", isPrimaryKey: false, isNullable: true,
                    description: "Frequency in Hz. Multiply / divide for kHz / MHz."
                ),
                .init(
                    name: "dxcc_entity", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Resolved DXCC entity name when known."
                ),
                .init(
                    name: "continent", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Two-letter continent of the spotted station."
                ),
                .init(
                    name: "cq_zone", type: "INTEGER", isPrimaryKey: false, isNullable: true,
                    description: "CQ zone of the spotted station, if known."
                ),
                .init(
                    name: "itu_zone", type: "INTEGER", isPrimaryKey: false, isNullable: true,
                    description: "ITU zone of the spotted station, if known."
                ),
                .init(
                    name: "grid", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Maidenhead grid square reported in the spot, if any."
                ),
                .init(
                    name: "park_ref", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "POTA park reference for activator spots."
                ),
                .init(
                    name: "last_seen_at", type: "REAL", isPrimaryKey: false, isNullable: false,
                    description: "Most recent observation time (epoch seconds)."
                ),
                .init(
                    name: "priority", type: "INTEGER", isPrimaryKey: false, isNullable: false,
                    description: "Source priority — higher wins when the same call+band shows up from multiple sources."
                ),
            ]
        ),
        Table(
            name: "spot_observations",
            qualified: "scope.spot_observations",
            description: """
            Raw fan-out — one row per spot received from any source, \
            kept upstream of the dedup that produces `scope.spots`. \
            Use for skimmer counts, SNR analysis, source comparisons. \
            Pruned to a 30-minute window every 60s.
            """,
            columns: [
                .init(
                    name: "obs_id", type: "TEXT", isPrimaryKey: true, isNullable: false,
                    description: "Per-observation UUID — unique even when the same callsign repeats."
                ),
                .init(
                    name: "spot_id", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Aggregator-side UUID; matches `scope.spots.spot_id` for the winning observation."
                ),
                .init(
                    name: "callsign", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Spotted station callsign."
                ),
                .init(
                    name: "band", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Band of the observation."
                ),
                .init(
                    name: "mode", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Mode of the observation."
                ),
                .init(
                    name: "freq_hz", type: "INTEGER", isPrimaryKey: false, isNullable: true,
                    description: "Frequency in Hz."
                ),
                .init(
                    name: "source", type: "TEXT", isPrimaryKey: false, isNullable: false,
                    description: "Source enum: rbn / pota / sota / wwff / dxSummit / dxHeat / dxWatch / cluster."
                ),
                .init(
                    name: "spotter", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Spotting station's callsign — RBN skimmer, cluster user, etc."
                ),
                .init(
                    name: "spot_lat", type: "REAL", isPrimaryKey: false, isNullable: true,
                    description: """
                    Spotted (DX) station latitude at observation time. Grid centre \
                    when `dxGrid` is known, DXCC entity centroid for the spotted \
                    callsign otherwise. Denormalized so distance queries don't have \
                    to look anything up.
                    """
                ),
                .init(
                    name: "spot_lon", type: "REAL", isPrimaryKey: false, isNullable: true,
                    description: "Spotted (DX) station longitude — see spot_lat for resolution rules."
                ),
                .init(
                    name: "snr_db", type: "INTEGER", isPrimaryKey: false, isNullable: true,
                    description: "Signal-to-noise reported by RBN skimmers, in dB."
                ),
                .init(
                    name: "speed_wpm", type: "INTEGER", isPrimaryKey: false, isNullable: true,
                    description: "CW speed reported by RBN, in words per minute."
                ),
                .init(
                    name: "comment", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Spotter's comment text."
                ),
                .init(
                    name: "received_at", type: "REAL", isPrimaryKey: false, isNullable: false,
                    description: "When this app received the observation (epoch seconds)."
                ),
                .init(
                    name: "priority", type: "INTEGER", isPrimaryKey: false, isNullable: false,
                    description: "Source priority used during dedup."
                ),
            ]
        ),
        Table(
            name: "spotters",
            qualified: "scope.spotters",
            description: """
            Roster of stations who spotted us / others. CTY-derived \
            entity centroid filled synchronously, refined by HamDB \
            grid/lat/lon when available. Use for \"spots heard by EU \
            skimmers\" style queries.
            """,
            columns: [
                .init(
                    name: "callsign", type: "TEXT", isPrimaryKey: true, isNullable: false,
                    description: "Spotter's callsign, uppercase."
                ),
                .init(
                    name: "grid", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Maidenhead grid (HamDB-resolved when available)."
                ),
                .init(
                    name: "lat", type: "REAL", isPrimaryKey: false, isNullable: true,
                    description: "Latitude in decimal degrees."
                ),
                .init(
                    name: "lon", type: "REAL", isPrimaryKey: false, isNullable: true,
                    description: "Longitude in decimal degrees."
                ),
                .init(
                    name: "dxcc_entity", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Spotter's DXCC entity name."
                ),
                .init(
                    name: "continent", type: "TEXT", isPrimaryKey: false, isNullable: true,
                    description: "Two-letter continent code."
                ),
                .init(
                    name: "is_skimmer", type: "INTEGER", isPrimaryKey: false, isNullable: false,
                    description: "1 if the spot came from RBN (automated skimmer); 0 if a human cluster spotter."
                ),
            ]
        ),
    ]
}

// swiftlint:enable type_body_length
