import Foundation

// MARK: - WhatsNewCatalog Recent

/// Per-version release notes split out of `WhatsNewCatalog` to keep the main
/// declaration under SwiftLint's 300-line type-body cap. Mirrors the
/// `+Archive.swift` pattern; the catalog's `entries` concatenates both.
extension WhatsNewCatalog {
    static let recentEntries: [WhatsNewEntry] = [
        // MARK: iOS — 1.106.0

        WhatsNewEntry(
            version: "1.106.0",
            date: recentDate(2_026, 11, 1),
            headline: "Add QSOs to ended sessions, AMSAT reports",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Add a QSO after ending a session",
                    detail: "Type one logger-style line on a finished "
                        + "session to log a missed contact, with lookup and "
                        + "uploads, without reopening it."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Report satellite status to AMSAT",
                    detail: "File your own Heard / Not Heard observation "
                        + "from a bird's community block or transmitter page."
                ),
            ]
        ),

        // MARK: iOS — 1.105.0

        WhatsNewEntry(
            version: "1.105.0",
            date: recentDate(2_026, 10, 23),
            headline: "New pota.app support, satellite list and pass plot",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .fix,
                    title: "Works with the new pota.app",
                    detail: "POTA sign-in, the logs link and spot park "
                        + "names follow the rebuilt pota.app site."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Satellite list points at the bird",
                    detail: "Every bird with a pass in the next 24 hours, "
                        + "with a compass arrow that turns with the phone; "
                        + "tap one to open antenna pointing."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Pass plot while pointing",
                    detail: "Below the horizon the pointing view draws the "
                        + "next pass on a polar sky plot, rotated to the "
                        + "boom, with the rise point marked."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Merged sessions export in full",
                    detail: "Export ADIF on a session now includes every "
                        + "QSO in it, across parks, days and rove stops."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Satellites tab opens instantly",
                    detail: "Cached orbital data shows right away and "
                        + "refreshes in the background."
                ),
            ]
        ),

        // MARK: iOS — 1.104.0

        WhatsNewEntry(
            version: "1.104.0",
            date: recentDate(2_026, 10, 13),
            headline: "Satellite community activity",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Community Activity grid",
                    detail: "AMSAT's who-heard-what grid in the Satellites "
                        + "menu: a week per transmitter with your next pass "
                        + "and QSOs, zoomable charts, and a map link."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Community signal on passes and map",
                    detail: "A dot in AMSAT's colours on every pass row, the "
                        + "info card and each map marker, plus where the bird "
                        + "was heard and by whom on the previous orbit."
                ),
            ]
        ),

        // MARK: iOS — 1.103.0

        WhatsNewEntry(
            version: "1.103.0",
            date: recentDate(2_026, 10, 11),
            headline: "WSJT-X logging, Morse practice streaks, Hunter Log fixes",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "WSJT-X logging",
                    detail: "Point WSJT-X's UDP server at your phone and every "
                        + "QSO it logs lands in your Field log once, uploading "
                        + "like a manual entry."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Morse practice streak",
                    detail: "Connect Another Morse Trainer to see your practice "
                        + "streak beside your QSO streaks and in purple on the "
                        + "activity grid."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Hunter Log commands work",
                    detail: "RBN, SOLAR, WX, MAP and MANUAL now open their "
                        + "panels in the Hunter Log; activation-only buttons "
                        + "are hidden there."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Hunter Log count on Sessions",
                    detail: "The Sessions page no longer says \"No contacts "
                        + "yet today\" after you have logged hunter QSOs."
                ),
            ]
        ),

        // MARK: iOS — 1.102.0

        WhatsNewEntry(
            version: "1.102.0",
            date: recentDate(2_026, 10, 5),
            headline: "Satellites: rotators, duplex radios, and the Sat Bridge",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Rotator & Trackers",
                    detail: "CSN S.A.T. and PSR-100 rotators are found on "
                        + "your network automatically; point and track from "
                        + "the sky view, or jog by hand."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Two-radio FM duplex",
                    detail: "Bind one CW Bridge to the uplink handheld and "
                        + "one to the downlink; both follow the pass with "
                        + "Doppler and the right CTCSS tone."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Send a pass to CW Sat Bridge",
                    detail: "Long-press an upcoming pass to upload its "
                        + "Doppler schedule to a bridge, which flies it on "
                        + "its own clock."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "QRZ key check after a callsign change",
                    detail: "A warning names the callsign your QRZ key "
                        + "belongs to and offers to add one, so new QSOs "
                        + "reach QRZ."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "No crash when switching apps mid-sync",
                    detail: "The local log moved out of the shared container "
                        + "so iOS no longer kills the app while it writes."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Callsign changes stick",
                    detail: "A changed callsign no longer reverts on relaunch "
                        + "and now reaches your account on the server."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Faster first Carrier Wave Sync",
                    detail: "The first pull applies the whole journal in one "
                        + "step instead of row by row."
                ),
            ]
        ),

        // MARK: CW Sweep — 0.14.0

        WhatsNewEntry(
            version: "0.14.0",
            date: recentDate(2_026, 10, 5),
            headline: "Satellites, rotators, and Carrier Wave Sync",
            platforms: [.macOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Carrier Wave Sync replaces iCloud",
                    detail: "Sign in with your callsign, enter your sync "
                        + "passphrase, and QSOs and sessions sync "
                        + "end-to-end encrypted with Field and Android."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Satellite mode",
                    detail: "A Satellites panel with upcoming passes, a "
                        + "polar sky plot, Doppler-corrected RX/TX and a "
                        + "synthetic waterfall; Doppler CAT tunes the rig."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Rotator panel",
                    detail: "Link state, hand controls with a hold-to-repeat "
                        + "jog pad, and network discovery under System."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Rotator auto-detection",
                    detail: "CSN S.A.T. and PSR-100 units are found on the "
                        + "LAN, even across VLANs once added by address."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "IC-9700 waterfall over LAN",
                    detail: "Scope output streams into the waterfall panel "
                        + "and follows Main or Sub."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "No more launch permission prompt",
                    detail: "The \"access data from other apps\" dialog is "
                        + "gone; your data moves to the new container once."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Far less CPU",
                    detail: "The waterfall and band scopes stop redrawing "
                        + "constantly; Icom LAN connects in about a second."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Launch crash on macOS 15",
                    detail: "The SCU-LAN10 audio player no longer trips "
                        + "AVAudioEngine at startup."
                ),
            ]
        ),

        // MARK: iOS — 1.101.0

        WhatsNewEntry(
            version: "1.101.0",
            date: recentDate(2_026, 9, 27),
            headline: "Spotting and offline fixes",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .fix,
                    title: "Re-spots use your own frequency",
                    detail: "Hunting another activator from inside your "
                        + "activation no longer re-spots you on their "
                        + "frequency."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Faster activation start",
                    detail: "The session wizard fills in a frequency right "
                        + "away instead of waiting on slow spot sources."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Brag sheet works offline",
                    detail: "With no connection the map falls back to a "
                        + "vector view and fills in contact locations once "
                        + "you're back online."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "PoLo markers no longer pending",
                    detail: "Ham2K WEATHER, SOLAR, START and BREAK rows stop "
                        + "showing as pending upload."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Smoother Sessions list",
                    detail: "Month groups are cached instead of re-sorted on "
                        + "every screen update."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Club counts follow the roster",
                    detail: "Brag sheet club member counts update whenever "
                        + "the club roster changes."
                ),
            ]
        ),

        // MARK: iOS — 1.100.1

        WhatsNewEntry(
            version: "1.100.1",
            date: recentDate(2_026, 9, 20),
            headline: "Satellite fixes",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .fix,
                    title: "Real satellite names",
                    detail: "Birds that showed catalog placeholders like "
                        + "\"OBJECT C\" now use their real names — TO-108, "
                        + "FO-29, and friends."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "FO-29 is back",
                    detail: "Satellites with mislabeled catalog data no "
                        + "longer vanish from the list when the community "
                        + "still hears them."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Steadier pointing mode",
                    detail: "The Doppler-corrected tuning readout stays on "
                        + "screen while you steer, and the frequency no "
                        + "longer shifts when you land on target."
                ),
            ]
        ),

        // MARK: iOS — 1.100.0

        WhatsNewEntry(
            version: "1.100.0",
            date: recentDate(2_026, 9, 20),
            headline: "Satellites grow up",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Satellite logging",
                    detail: "QSOs carry SAT_NAME and PROP_MODE for LoTW "
                        + "satellite credit, with a post-pass quick log "
                        + "that never disturbs a live activation."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Pass alerts",
                    detail: "Favorite a bird to get notified before its "
                        + "passes, with a live countdown on the Lock "
                        + "Screen. Record the pass and mark each contact."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Powerful pass filters",
                    detail: "Filter by mode, uplink/downlink band, "
                        + "community activity, favorites, elevation, and "
                        + "a per-direction horizon mask. Enable "
                        + "Satellites under Settings → Experiments."
                ),
            ]
        ),

        // MARK: iOS — 1.99.0

        WhatsNewEntry(
            version: "1.99.0",
            date: recentDate(2_026, 8, 27),
            headline: "Connected apps and fresher lookups",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Connected apps",
                    detail: "Third-party tools can now access your log "
                        + "with your consent — sign in on the app's "
                        + "authorization page and manage or revoke "
                        + "access any time. Your log stays end-to-end "
                        + "encrypted."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Fresher callsign lookups",
                    detail: "Cached operator info now refreshes instead "
                        + "of sticking forever — changed and re-issued "
                        + "callsigns show the current holder."
                ),
            ]
        ),

        // MARK: iOS — 1.98.0

        WhatsNewEntry(
            version: "1.98.0",
            date: recentDate(2_026, 8, 3),
            headline: "Park n-fers, prefix hot keys, and map overlays",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Park n-fers when hunting",
                    detail: "Log a multi-park activation in one entry — "
                        + "type the callsign then every park "
                        + "(e.g. US-1044 US-3791). Each park counts on "
                        + "its own, and working one park of an n-fer "
                        + "leaves the others still showing as needed."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Richer Hunter Log quick entry",
                    detail: "Quick entry now looks up the operator and "
                        + "resolves each park's name as you type — "
                        + "including every park of an n-fer."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Callsign prefix hot keys",
                    detail: "A Prefixes row above the logger keyboard "
                        + "types common callsign prefixes with one tap."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Keyboard Rows settings hub",
                    detail: "The logger's keyboard accessory rows are "
                        + "now configured from one place in Settings."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Parks & Summits map overlays",
                    detail: "The Parks & Summits map gains toggleable "
                        + "overlays, and multi-unit parks now draw as a "
                        + "single merged boundary."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Club map opens instantly",
                    detail: "Member pins paint immediately on a "
                        + "grid-first render instead of waiting on the "
                        + "full map to load."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Session park edits stick",
                    detail: "Changing a session's park reference in the "
                        + "Edit sheet now actually saves instead of "
                        + "silently doing nothing."
                ),
            ]
        ),
    ]

    private static func recentDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }
}
