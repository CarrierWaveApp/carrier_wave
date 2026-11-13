import Foundation

// MARK: - WhatsNewCatalog ArchiveOlder

/// Oldest release notes split out of `WhatsNewCatalog+Archive.swift` to keep
/// the archive file under SwiftLint's 500-line file cap. Concatenated into
/// `entries` after `archivedEntries` — order is preserved.
extension WhatsNewCatalog {
    static let archivedOlderEntries: [WhatsNewEntry] = [
        // MARK: iOS — 1.91.0

        WhatsNewEntry(
            version: "1.91.0",
            date: archiveOlderDate(2_026, 5, 19),
            headline: "Weather radar on the map, propagation check refresh",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Weather radar on the map",
                    detail: "The Weather Radar experiment now overlays NEXRAD "
                        + "reflectivity directly on the Parks & Summits map, "
                        + "alongside park polygons, trails, and pins (US only)."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Per-radio connection profile",
                    detail: "Save the BLE/WiFi/CW-Bridge connection for each "
                        + "radio in your inventory; sessions auto-connect to "
                        + "the rig you picked at start instead of the global "
                        + "Radio settings."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Propagation Check, redesigned",
                    detail: "Saved checks open into a richer detail view with "
                        + "geodesic arcs to each skimmer, an azimuthal map "
                        + "toggle, a newest-first spots list, and stats that "
                        + "honor HamDB-resolved skimmer grids."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Notes & equipment on checks",
                    detail: "Attach notes plus the radio/antenna/key/mic you "
                        + "used to any propagation check, with the same "
                        + "pickers the session metadata sheet uses."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Faster Parks & Summits map",
                    detail: "Map clustering moved off the main thread via a "
                        + "quadtree, so panning and zooming the full 22k "
                        + "POTA + SOTA pin set no longer freezes the UI."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Keyer bar self-heals",
                    detail: "If the CW Bridge's USB-status push was dropped "
                        + "during reconnect, the keyer row used to stay "
                        + "hidden. Both Field and Sweep now re-poll status "
                        + "after handshake so the bar reappears within a tick."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "iCloud restore on a new device",
                    detail: "Restoring an iCloud backup on a fresh device no "
                        + "longer fails with 'backup file not found' — Field "
                        + "now downloads the backup contents from iCloud "
                        + "before trying to read them."
                ),
            ]
        ),

        // MARK: iOS — 1.90.0

        WhatsNewEntry(
            version: "1.90.0",
            date: archiveOlderDate(2_026, 5, 9),
            headline: "Hunt widget, end-session reliability",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "New Hunt widget",
                    detail: "Small home-screen widget showing propagation "
                        + "rating, K/A/SFI gauges, band conditions, and the "
                        + "live count of active POTA/SOTA/RBN spots. Tap to "
                        + "jump straight into the Hunter Log."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Ended sessions stay ended",
                    detail: "Long-standing bug where a session ended on iPhone "
                        + "would come back as active after kill/relaunch — "
                        + "stale LAN snapshots from CW Sweep could resurrect "
                        + "the just-ended record. The user's end-session "
                        + "action now always wins."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Activation Suggestion widget tap",
                    detail: "The Activation Suggestion widget now opens "
                        + "directly to Sessions instead of falling through to "
                        + "whatever tab was last selected."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "END button is bolder",
                    detail: "The red end-session button in the Logger header "
                        + "now reads END (all caps) to match its visual weight."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Smoother Dashboard and Grid Tracker",
                    detail: "Dashboard scroll and Grid Tracker typing were "
                        + "choppy on tab return — friendship queries, parallel "
                        + "stat scans, and a search-driven Canvas redraw all "
                        + "fixed."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "iPad sidebar settings",
                    detail: "Tab settings now agree with the sidebar on iPad, "
                        + "and the sidebar column is more compact."
                ),
            ]
        ),

        // MARK: iOS — 1.89.0

        WhatsNewEntry(
            version: "1.89.0",
            date: archiveOlderDate(2_026, 5, 7),
            headline: "SOTA polish — inline summit, brag sheet, self-spot",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Nearby references in the wizard",
                    detail: "Pick POTA, SOTA, or WWFF in the session wizard "
                        + "and the 3 nearest references within 10 mi appear "
                        + "instantly, derived from your grid square. Tap to "
                        + "add — no need to search first. Search still works."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Inline S2S Summit field",
                    detail: "SOTA sessions now show a Summit field in the "
                        + "Logger expanded row instead of forcing a trip to the "
                        + "QSO edit sheet. Dual POTA+SOTA shows both."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "SOTA Brag Sheet + Export ADIF",
                    detail: "SOTA-only session details finally get the share "
                        + "card and ADIF export buttons, with summit-aware "
                        + "MY_SOTA_REF, S2S tags, and the same brag layout as "
                        + "POTA activations."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "SOTA self-spotting + multi-program SPOT",
                    detail: "SPOT now dispatches per-program: POTA fans across "
                        + "every park reference, SOTA self-spots to SOTAwatch. "
                        + "Dual sessions spot both. Repeat and post-QSY auto-"
                        + "spot use the same dispatcher."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "8-character Maidenhead grids",
                    detail: "New Logger setting picks 4 / 6 / 8 character "
                        + "MY_GRIDSQUARE precision. 8-char grids matter for "
                        + "VHF/UHF and grid-square contests where 6-char is "
                        + "too coarse."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Session grid from summit/park",
                    detail: "POTA and SOTA sessions now pin MY_GRIDSQUARE to "
                        + "the surveyed park/summit coordinates instead of "
                        + "GPS at session start — reliable even with a cold "
                        + "fix or a phone in your backpack."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "SOTA activation threshold = 4 QSOs",
                    detail: "The Logger session-header chip and watch ring "
                        + "previously hardcoded 10 QSOs, so SOTA-only sessions "
                        + "stayed orange even after qualifying. Now reads each "
                        + "program's actual activation target."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Spot-frequency popup stays dismissed",
                    detail: "The nearby-spot frequency-warning banner no "
                        + "longer reappears after dismissal whenever the spot "
                        + "feed re-emits or you retune."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Reject / Reopen from session detail",
                    detail: "Reject Upload and Reopen Session confirmations "
                        + "now appear immediately when triggered from inside "
                        + "the session detail view instead of waiting until "
                        + "you pop back to the Sessions list."
                ),
            ]
        ),

        // MARK: iOS + macOS — 1.88.0 / matching CW Sweep build

        WhatsNewEntry(
            version: "1.88.0",
            date: archiveOlderDate(2_026, 5, 7),
            headline: "Remote control surface, contest strike card, club chips",
            platforms: [.iOS, .macOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Remote pane is a control surface",
                    detail: "Big tabular VFO, chunky speaker + volume strip, "
                        + "TX/RX dot, and an inline tune entry. The nested "
                        + "Radio/Scope/Waterfall/Spots/CW tabs become a "
                        + "horizontal capsule strip under the title."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "RX audio over Remote",
                    detail: "Listen to Sweep's RX audio on your phone over the "
                        + "LAN. Speaker toggle + volume slider in the Remote "
                        + "Radio pane; opt-in Opus codec drops bandwidth from "
                        + "~256 kbps PCM to ~24 kbps."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Tap straight key on Remote",
                    detail: "New pad in the Remote Radio sub-tab: tap for a "
                        + "dit, hold past 180 ms for a dah. Routes through "
                        + "CW Bridge, WinKeyer, or the radio's CAT keyer."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Club membership chips",
                    detail: "Callsign cards now show CWops, BKG, and SKCC "
                        + "membership chips (e.g. 🎹 #1532, 🤜 #29, 🔑 #6707T) "
                        + "from the new daily-refreshed enrichment cache. "
                        + "Works offline once cached."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "CWT contest strike card",
                    detail: "During CWT the callsign card, exchange row, and "
                        + "score collapse into one dense card that fits above "
                        + "the keyboard fold — 50pt monospaced NAME and "
                        + "#/S/P/C inputs for thumb-targeting at 100 QSOs/hr."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "CWT auto-fill for everyone",
                    detail: "Auto-prefill name + member number for CWops "
                        + "stations, plus name + state/province (W/VE) or "
                        + "DXCC prefix (DX) for non-members. QRZ nicknames "
                        + "win over registered first names (TIM not TIMOTHY)."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "{MYNAME} keyer macro",
                    detail: "New macro that expands to your first name in CW "
                        + "memory keyer messages — pair it with {MYCALL} for "
                        + "TU JAY 73 sign-offs."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "{MYCALL} keyer macro now resolves",
                    detail: "The CW Messages editor previously read the wrong "
                        + "UserDefaults key, so {MYCALL} always fell back to "
                        + "the placeholder W6JY in the preview. Fixed."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Remote waterfall lines",
                    detail: "Remote waterfall rows now render at 1 pt tall "
                        + "and push down on each frame instead of stretching "
                        + "to fill the canvas — the time axis is honest again."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "FT8 reliability + smoother waterfall",
                    detail: "Fixes a race that could leave FT8 silently broken "
                        + "after toggling Logger mode away and back, surfaces a "
                        + "Retry banner if the audio engine fails to start, and "
                        + "moves the waterfall FFT off the main thread."
                ),
            ]
        ),

        // MARK: iOS + macOS — 1.87.0 / matching CW Sweep build

        WhatsNewEntry(
            version: "1.87.0",
            date: archiveOlderDate(2_026, 5, 4),
            headline: "Waterfall on the phone, FT8 cleanup",
            platforms: [.iOS, .macOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Sweep waterfall on iOS Remote",
                    detail: "The Remote tab now carries a live waterfall from CW Sweep "
                        + "over the LAN, with the same color ramp as the macOS panel."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Waterfall is a first-class Sweep panel",
                    detail: "Drop the waterfall into any custom Sweep layout via the "
                        + "layout editor. Source-agnostic, ready for any radio that "
                        + "produces spectrum data."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "FlexRadio waterfall in Sweep",
                    detail: "Sweep now ingests SmartSDR panadapter / waterfall data "
                        + "over VITA-49 and feeds the shared waterfall store."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "FT8 overload banner finally honest",
                    detail: "iOS FT8 no longer flashes 'audio is clipping' on quiet "
                        + "rigs. New noise-floor-relative waterfall and split "
                        + "enter/exit thresholds match WSJT-X behavior."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Quick entry accepts more time formats",
                    detail: "Typing 'W1AW 14:30' in a quick-entry field now sets the "
                        + "UTC time override. Bare HHMM (e.g. 0930, 1430) also works "
                        + "where it isn't an amateur frequency."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Sweep tune commands work again",
                    detail: "Frequency, PTT, XIT, and RIT commands silently dropped on "
                        + "every non-CW-Bridge transport (Flex, serial CAT, IcomWiFi, "
                        + "SCU-LAN10) since April. Tunes hit the wire again."
                ),
            ]
        ),

        // MARK: iOS + macOS — 1.86.0 / matching CW Sweep build

        WhatsNewEntry(
            version: "1.86.0",
            date: archiveOlderDate(2_026, 5, 4),
            headline: "Phone-to-Mac remote, faster Sweep queries",
            platforms: [.iOS, .macOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Phone-as-dashboard remote (alpha)",
                    detail: "Pair Field with CW Sweep over LAN to see live frequency "
                        + "and curated spots, tap-to-tune, and key CW slots with "
                        + "Sweep-side macro expansion. Enable in Experiments."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "CW keyer presets",
                    detail: "New PRESETS tile in the iOS Remote CW pane programs slot "
                        + "templates in one tap. Built-in POTA preset to start."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Distance & bearing in queries",
                    detail: "New cw_distance_km / cw_bearing_deg / cw_user_* SQL "
                        + "functions in the Sweep Query Workbench. Two starter queries "
                        + "show nearest spots and nearby spotters."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Sweep Query Workbench polish",
                    detail: "Full-pane results table with click-to-sort and Copy CSV. "
                        + "New code-editor keys in the SQL editor (Tab/Shift-Tab indent, "
                        + "smart Backspace)."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "FT8 audio level meter",
                    detail: "Replaced the No Signal/Low/OK/Hot pill with an inline "
                        + "8-pip level meter and a real peak-clipping detector — no "
                        + "more false 'audio is clipping' warnings on quiet rigs."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "POTA Activations crash",
                    detail: "Fixed an EXC_BREAKPOINT crash that could hit the POTA "
                        + "Activations list when iCloud sync arrived mid-render."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Big sync no longer roasts the device",
                    detail: "Fixed a runaway loop in journal sync that scanned all "
                        + "dirty rows and rebuilt CKRecords every batch — Force Full "
                        + "Sync now drains progressively without burning the battery."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Friend requests fixed",
                    detail: "Accepting a friend request no longer shows 'request not "
                        + "found' after the request was already accepted."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "FT8 Call CQ menu works",
                    detail: "CQ / CQ POTA / CQ DX / CQ SOTA menu options now actually "
                        + "open the channel picker on iOS 18+."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Sweep VFO no longer jumps powers of 10",
                    detail: "Fixed garbled frequency display after the CW Bridge "
                        + "auto-detected the radio and swapped protocol handlers."
                ),
            ]
        ),

        // MARK: macOS — CW Sweep 0.12.0

        WhatsNewEntry(
            version: "0.12.0",
            date: archiveOlderDate(2_026, 5, 5),
            headline: "Auto-update, sessions sync, Flex waterfall",
            platforms: [.macOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "CW Sweep updates itself",
                    detail: "New builds arrive automatically over Sparkle — "
                        + "“Check for Updates…” lives in the CW Sweep menu and "
                        + "the daily background check pulls new releases from "
                        + "carrierwave.app the day they’re notarized."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Sessions sync between Field and Sweep",
                    detail: "Start an activation on either device and the other "
                        + "picks it up automatically — no Sync, Connect, or pairing "
                        + "step. Works co-located over LAN and apart over iCloud."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Waterfall is a first-class panel",
                    detail: "Drop the waterfall into any custom layout via the "
                        + "layout editor. Source-agnostic — any radio that produces "
                        + "spectrum data can feed it."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "FlexRadio panadapter ingest",
                    detail: "SmartSDR panadapter and waterfall data now flows into "
                        + "the new waterfall panel via VITA-49 over UDP."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Distance & bearing in queries",
                    detail: "New cw_distance_km / cw_bearing_deg / cw_user_* SQL "
                        + "functions in the Query Workbench. Two starter queries "
                        + "show nearest spots and nearby spotters."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Query Workbench polish",
                    detail: "Full-pane results table with click-to-sort and Copy CSV. "
                        + "New code-editor keys in the SQL editor (Tab/Shift-Tab "
                        + "indent, smart Backspace). Schema browser scrolls properly."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Tune commands work on every transport",
                    detail: "Frequency, PTT, XIT, and RIT commands silently dropped "
                        + "on every non-CW-Bridge transport (Flex, serial CAT, "
                        + "IcomWiFi, SCU-LAN10) since April. Fixed."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "VFO no longer jumps powers of 10",
                    detail: "Fixed garbled frequency display after the CW Bridge "
                        + "auto-detected the radio and swapped protocol handlers."
                ),
            ]
        ),
    ]

    private static func archiveOlderDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }
}
