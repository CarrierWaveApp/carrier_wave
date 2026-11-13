import CarrierWaveData
import Foundation

enum StarterQueries {
    static let all: [SavedQuery] = [
        SavedQuery(
            name: "Recent QSOs",
            description: "The 50 most recent contacts in your log.",
            sql: """
            SELECT callsign, band, mode, timestamp, my_callsign
            FROM qsos
            WHERE is_hidden = 0
            ORDER BY timestamp DESC
            LIMIT 50;
            """,
            columnHints: ["timestamp": "timestamp"]
        ),
        SavedQuery(
            name: "Live spots — multi-skimmer concentration",
            description: "Currently visible spots ranked by how many skimmers heard them.",
            sql: """
            SELECT
                spots.callsign,
                spots.band,
                spots.mode,
                COUNT(DISTINCT spot_observations.spotter) AS skimmers,
                MAX(spot_observations.snr_db) AS best_snr_db,
                spots.last_seen_at
            FROM scope.spots AS spots
            LEFT JOIN scope.spot_observations AS spot_observations
                ON spot_observations.callsign = spots.callsign
               AND spot_observations.band = spots.band
            GROUP BY spots.spot_id
            ORDER BY skimmers DESC, best_snr_db DESC
            LIMIT 100;
            """,
            columnHints: [
                "last_seen_at": "timestamp",
                "best_snr_db": "snr_db",
            ]
        ),
        SavedQuery(
            name: "Worked-before lookup (today)",
            description: "Live spots whose callsigns you've already worked today.",
            sql: """
            SELECT spots.callsign, spots.band, spots.mode, spots.last_seen_at
            FROM scope.spots AS spots
            WHERE EXISTS (
                SELECT 1 FROM qsos
                WHERE qsos.callsign = spots.callsign
                  AND qsos.timestamp > strftime('%s', 'now', 'start of day')
                  AND qsos.is_hidden = 0
            )
            ORDER BY spots.last_seen_at DESC;
            """,
            columnHints: ["last_seen_at": "timestamp"]
        ),
        SavedQuery(
            name: "Top spotters last hour",
            description: "Most active skimmers/spotters in the last hour.",
            sql: """
            SELECT spotter, COUNT(*) AS spots_count
            FROM scope.spot_observations
            WHERE received_at > strftime('%s', 'now') - 3600
              AND spotter IS NOT NULL
            GROUP BY spotter
            ORDER BY spots_count DESC
            LIMIT 25;
            """
        ),
        SavedQuery(
            name: "DXCC status snapshot",
            description: "Worked count per DXCC entity, band, and mode.",
            sql: """
            SELECT entity, band, mode, worked_count, last_worked_at
            FROM dxcc_status
            WHERE worked_count > 0
            ORDER BY worked_count DESC
            LIMIT 100;
            """,
            columnHints: ["last_worked_at": "timestamp"]
        ),
        SavedQuery(
            name: "Needed DXCC on band",
            description: "Live spots whose entity I haven't worked on this band.",
            sql: """
            SELECT spots.spot_id, spots.callsign, spots.band, spots.mode,
                   dxcc.entity, dxcc.continent, spots.last_seen_at
            FROM scope.spots AS spots
            LEFT JOIN dxcc ON spots.callsign LIKE dxcc.prefix || '%'
            LEFT JOIN dxcc_status AS status
                ON status.entity = dxcc.entity
               AND status.band = spots.band
            WHERE COALESCE(status.worked_count, 0) = 0
              AND dxcc.entity IS NOT NULL
            ORDER BY spots.last_seen_at DESC
            LIMIT 200;
            """,
            columnHints: ["last_seen_at": "timestamp"]
        ),
        SavedQuery(
            name: "EU greyline multipliers",
            description: """
            European spots at greyline (06–08 / 18–20 UTC), filtered to \
            entities I haven't worked on the spot's band.
            """,
            sql: """
            SELECT spots.spot_id, spots.callsign, spots.band, spots.mode,
                   dxcc.entity, spots.last_seen_at
            FROM scope.spots AS spots
            JOIN dxcc ON spots.callsign LIKE dxcc.prefix || '%'
                     AND dxcc.continent = 'EU'
            LEFT JOIN dxcc_status AS status
                ON status.entity = dxcc.entity
               AND status.band = spots.band
            WHERE COALESCE(status.worked_count, 0) = 0
              AND CAST(strftime('%H', 'now') AS INTEGER) IN (6, 7, 18, 19)
            ORDER BY spots.last_seen_at DESC
            LIMIT 100;
            """,
            columnHints: ["last_seen_at": "timestamp"]
        ),
        SavedQuery(
            name: "Callsigns I've never seen",
            description: "Live spots whose callsign is not in my QSO log at all.",
            sql: """
            SELECT spots.spot_id, spots.callsign, spots.band, spots.mode,
                   spots.last_seen_at
            FROM scope.spots AS spots
            WHERE NOT EXISTS (
                SELECT 1 FROM qsos
                WHERE qsos.callsign = spots.callsign
                  AND qsos.is_hidden = 0
            )
            ORDER BY spots.last_seen_at DESC
            LIMIT 200;
            """,
            columnHints: ["last_seen_at": "timestamp"]
        ),
        SavedQuery(
            name: "Spots sorted by nearest",
            description: """
            Live spots ordered by great-circle distance from your \
            configured grid (\"myGrid\" in Settings). Spots without a \
            grid sink to the bottom.
            """,
            sql: """
            SELECT spots.spot_id, spots.callsign, spots.band, spots.mode,
                   spots.grid,
                   cw_user_grid_distance_km(spots.grid) AS distance_km,
                   cw_user_grid_bearing_deg(spots.grid) AS bearing_deg,
                   spots.last_seen_at
            FROM scope.spots AS spots
            ORDER BY distance_km ASC NULLS LAST, spots.last_seen_at DESC
            LIMIT 200;
            """,
            columnHints: ["last_seen_at": "timestamp"]
        ),
        SavedQuery(
            name: "Spots heard by nearby spotters (≤ 50 km)",
            description: """
            Spots whose source spotter (RBN skimmer or cluster user) sits \
            within 50 km of your configured grid — a proxy for \"local \
            propagation\" or a NVIS check.
            """,
            sql: """
            SELECT DISTINCT spots.callsign, spots.band, spots.mode,
                   spots.freq_hz, spotters.callsign AS spotter,
                   cw_user_distance_km(spotters.lat, spotters.lon) AS spotter_km,
                   spots.last_seen_at
            FROM scope.spots AS spots
            JOIN scope.spot_observations AS obs
                ON obs.callsign = spots.callsign
               AND obs.band = spots.band
            JOIN scope.spotters AS spotters
                ON spotters.callsign = obs.spotter
            WHERE spotters.lat IS NOT NULL
              AND spotters.lon IS NOT NULL
              AND cw_user_distance_km(spotters.lat, spotters.lon) <= 50
            ORDER BY spotter_km ASC, spots.last_seen_at DESC
            LIMIT 200;
            """,
            columnHints: ["last_seen_at": "timestamp"]
        ),
    ]
}
