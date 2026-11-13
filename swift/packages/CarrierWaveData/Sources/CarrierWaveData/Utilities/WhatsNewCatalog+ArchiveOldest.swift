import Foundation

// MARK: - WhatsNewCatalog ArchiveOldest

/// Oldest release notes split out of `WhatsNewCatalog+Archive.swift` to keep
/// the archive file under SwiftLint's 500-line file cap. Concatenated into
/// `entries` after `archivedEntries` — order is preserved.
extension WhatsNewCatalog {
    static let archivedOldestEntries: [WhatsNewEntry] = [
        // MARK: iOS

        WhatsNewEntry(
            version: "1.85.0",
            date: archiveOldestDate(2_026, 5, 2),
            headline: "Tiles on the Air",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Tiles on the Air",
                    detail: "Score, path, tiles, and bonus breakdown for "
                        + "every TOTA activation in the session log.",
                    link: URL(string: "https://tilesontheair.com/"),
                    linkLabel: "tilesontheair.com"
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Brag sheets, redesigned",
                    detail: "New unified purple look for every session brag "
                        + "sheet. Sharing now produces a high-resolution image "
                        + "that lands in Copy / Save / AirDrop / Messages."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Edit TOTA after the session",
                    detail: "Edit Session now exposes TOTA category, distance, "
                        + "elevation, ruck weight, winter override, "
                        + "first-ever-tile, and bonus toggles. Locks once the "
                        + "activation is submitted."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Frequency parsing with commas",
                    detail: "Inputs like \"14,060\" now parse as 14.060 MHz "
                        + "instead of being silently dropped (en-AU/en-GB)."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Frequency editable mid-session",
                    detail: "Tap a logged QSO inside an active session to fix "
                        + "a wrong frequency — the band auto-derives."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "iPad sidebar after Hunter Log",
                    detail: "Sidebar tabs no longer get stuck after navigating "
                        + "Dashboard → Hunter Log."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Start Session sheet scrolling",
                    detail: "Scroll-to-top jitter caused by the warning banner "
                        + "fighting the scroll layout."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "QRZ upload off the main thread",
                    detail: "Background QRZ uploads no longer hold the main "
                        + "actor; logger UI stays smooth during sync."
                ),
            ]
        ),

        WhatsNewEntry(
            version: "1.84.2",
            date: archiveOldestDate(2_026, 4, 29),
            headline: "Battery-drain fix",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .fix,
                    title: "Apple Watch battery drain",
                    detail: "Stopped a WatchConnectivity reactivation loop "
                        + "that pinned a CPU core and drained battery on "
                        + "phones with no paired Apple Watch."
                ),
            ]
        ),

        WhatsNewEntry(
            version: "1.84.1",
            date: archiveOldestDate(2_026, 4, 27),
            headline: "SOTA HUNT taps + N-fer ADIFs",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .fix,
                    title: "SOTA spot taps",
                    detail: "Tapping a SOTA spot in the HUNT panel now prefills "
                        + "callsign, frequency, and notes (summit, name, points). "
                        + "The tap was previously a no-op."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "N-fer ADIF split",
                    detail: "Split ADIF export now produces one file per park "
                        + "for N-fer activations — a 5-fer gives you 5 ADIFs, a "
                        + "3-fer gives you 3, each with the right MY_POTA_REF."
                ),
            ]
        ),

        WhatsNewEntry(
            version: "1.84.0",
            date: archiveOldestDate(2_026, 4, 26),
            headline: "Recovery mode + HUNT command",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "HUNT command",
                    detail: "Type `HUNT N9HO 14060` (or include a mode) in the logger "
                        + "to log a one-off off-frequency QSO without changing your "
                        + "active session — missing freq/mode falls back to the session."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Files.app access",
                    detail: "Carrier Wave now appears in Files → On My iPhone, exposing "
                        + "the QSO Ledger ADIFs for self-service recovery."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "What's New sheet",
                    detail: "Yes, the one you're reading — release notes now ship in the app."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Database recovery mode",
                    detail: "If the database fails to open at launch, the app now preserves "
                        + "the broken file and presents a recovery screen instead of "
                        + "silently resetting (CAR-246)."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "POTA upload via ADIF",
                    detail: "POTA uploads now open the ADIF export sheet — save the file, "
                        + "upload it on pota.app/user/logs."
                ),
            ]
        ),

        WhatsNewEntry(
            version: "1.83.0",
            date: archiveOldestDate(2_026, 4, 22),
            headline: "Contests, keyer, and SKCC",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Contests browser",
                    detail: "New Contests row in the Activity tab — live + upcoming with rules, "
                        + "exchange, and friends already participating."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "CW memory keyer",
                    detail: "Eight configurable keyer messages with macros "
                        + "(MYCALL, CALL, NR, RST). Pairs with the CW Bridge."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Xiegu G90 CI-V",
                    detail: "RIT/XIT, mode, frequency, and power level over CAT — fully supported."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Group QSOs into a session",
                    detail: "Select QSOs in the Logs tab to back-fill a completed session, "
                        + "with park / mode / frequency auto-detected."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "RBN Lookup card",
                    detail: "Check Reverse Beacon Network spots for any callsign right from the "
                        + "dashboard — no logging session required."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "SKCC enrichment",
                    detail: "Spots from SKCC members display the operator's number and award "
                        + "level (Centurion / Tribune / Senator)."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Spotlight + share links",
                    detail: "QSOs and sessions are now searchable from the iOS home screen. "
                        + "Share enriched callsign / QSO / park / SOTA links via iMessage and Mail."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Single 60-second poll",
                    detail: "Spots, comments, solar, sync, and frequency activity now share "
                        + "one timer to reduce battery drain."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "QSO detail redesign",
                    detail: "Hero callsign, band/mode pills, side-by-side THEY/ME station "
                        + "cards, and chips for activity references."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "iCloud 3× duplicate QSOs",
                    detail: "Phone-mode QSOs (USB/LSB/AM/FM/DV) were duplicating on sync "
                        + "— dedup now matches the local model."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "POTA upload validation",
                    detail: "Bad modes and bands are caught before upload instead of failing on POTA's side."
                ),
            ]
        ),
        WhatsNewEntry(
            version: "1.82.0",
            date: archiveOldestDate(2_026, 4, 6),
            headline: "Safety ledger + crash fixes",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "QSO safety ledger",
                    detail: "Every QSO is also written to an append-only ADIF file outside "
                        + "SwiftData — survives database loss and can be re-imported."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Location-based prefix picker",
                    detail: "Suggests the right portable prefix (e.g. F/) based on GPS, with searchable country list."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Critical: silent database wipe",
                    detail: "ModelContainer init failure no longer silently deletes the database "
                        + "— emergency backup is created first."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Critical: snapshot restore safety",
                    detail: "iCloud snapshot restore now verifies QSO contents and creates a pre-restore "
                        + "backup before replacing the local store."
                ),
            ]
        ),
        WhatsNewEntry(
            version: "1.81.0",
            date: archiveOldestDate(2_026, 4, 2),
            headline: "IC-705 WiFi reliability",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .fix,
                    title: "IC-705 WiFi disconnects",
                    detail: "Sessions no longer drop after ~60 seconds — periodic reauth keeps the radio link alive."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Frequency / mode passthrough",
                    detail: "Logger changes now reach the radio over WiFi instead of being blocked by stale sessions."
                ),
            ]
        ),

        WhatsNewEntry(
            version: "1.80.0",
            date: archiveOldestDate(2_026, 4, 2),
            headline: "Session detail redesign",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .improvement,
                    title: "Three-tier layout",
                    detail: "Hero summary → QSO list → swipeable insights carousel. Map, States Worked, "
                        + "and Park Cards are now tap-to-expand."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Unified hero card",
                    detail: "POTA activations and regular sessions share one consolidated header with "
                        + "stats, band/mode pills, and full equipment."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Percentile rankings",
                    detail: "See how a session's QSO count, duration, and rate stack up against your history (Top X%)."
                ),
            ]
        ),
        WhatsNewEntry(
            version: "1.79.0",
            date: archiveOldestDate(2_026, 4, 2),
            headline: "Faster iCloud sync + per-service modes",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Per-service sync mode",
                    detail: "Set QRZ / POTA / eQSL to Bidirectional, Upload Only, or Download Only independently."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Journal + snapshot sync",
                    detail: "New device setup downloads one snapshot instead of syncing thousands of "
                        + "individual records — minutes vs hours."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Enriched spot widgets",
                    detail: "Widgets now show activity icon (POTA / SOTA / RBN), band, mode, and "
                        + "park / summit reference."
                ),
            ]
        ),
    ]

    private static func archiveOldestDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }
}
