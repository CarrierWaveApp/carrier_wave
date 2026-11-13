import CarrierWaveData
import Foundation

// MARK: - SettingsSearchItem

struct SettingsSearchItem: Identifiable {
    let id = UUID()
    let title: String
    let keywords: [String]
    let breadcrumb: String
    let destination: SettingsSearchDestination
    var isDebugOnly: Bool = false
}

// MARK: - SettingsSearchIndex

enum SettingsSearchIndex {
    // MARK: Internal

    static func search(
        query: String,
        debugMode: Bool = false
    ) -> [SettingsSearchItem] {
        guard !query.isEmpty else {
            return []
        }
        let lowered = query.lowercased()
        return allItems.filter { item in
            if item.isDebugOnly, !debugMode {
                return false
            }
            if item.title.lowercased().contains(lowered) {
                return true
            }
            if item.breadcrumb.lowercased().contains(lowered) {
                return true
            }
            return item.keywords.contains { $0.contains(lowered) }
        }
    }

    // MARK: Private

    private static let allItems: [SettingsSearchItem] =
        profileItems + appearanceItems + loggerItems
            + potaItems + syncSourceItems + dataToolItems
            + developerItems + aboutItems
}

// MARK: - Item Definitions

extension SettingsSearchIndex {
    private static let profileItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            title: "My Profile",
            keywords: ["callsign", "name", "qth", "grid", "license", "about me"],
            breadcrumb: "My Profile",
            destination: .aboutMe
        ),
        SettingsSearchItem(
            title: "Callsign Aliases",
            keywords: ["callsign", "alias", "previous", "old", "call"],
            breadcrumb: "My Profile",
            destination: .callsignAliases
        ),
    ]

    private static let appearanceItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            title: "Tab Bar / Sidebar",
            keywords: ["tab", "sidebar", "navigation", "visible", "hidden", "order"],
            breadcrumb: "Appearance",
            destination: .tabConfiguration
        ),
        SettingsSearchItem(
            title: "Dashboard Metrics",
            keywords: ["dashboard", "metric", "stats", "card", "display"],
            breadcrumb: "Features",
            destination: .dashboardMetrics
        ),
        SettingsSearchItem(
            title: "On Air Now",
            keywords: ["on air", "spots", "solar", "dxpedition", "contest", "bands", "modes"],
            breadcrumb: "Features",
            destination: .onAirNow
        ),
        SettingsSearchItem(
            title: "Hunt & P2P",
            keywords: ["hunt", "p2p", "spots", "rbn", "sota", "dx cluster", "clubs"],
            breadcrumb: "Features",
            destination: .huntP2P
        ),
        SettingsSearchItem(
            title: "Contest Calendar",
            keywords: ["contest", "calendar", "utc", "zulu", "clock", "time"],
            breadcrumb: "Features",
            destination: .contestCalendar
        ),
        SettingsSearchItem(
            title: "Appearance Mode",
            keywords: ["dark", "light", "system", "sunlight", "theme", "color scheme"],
            breadcrumb: "Appearance",
            destination: .appearance
        ),
        SettingsSearchItem(
            title: "Units",
            keywords: [
                "metric", "imperial", "miles", "kilometers",
                "temperature", "fahrenheit", "celsius",
            ],
            breadcrumb: "Appearance",
            destination: .appearance
        ),
    ]

    private static let loggerItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            title: "Default Mode",
            keywords: ["cw", "ssb", "ft8", "ft4", "rtty", "mode"],
            breadcrumb: "Logger",
            destination: .logger
        ),
        SettingsSearchItem(
            title: "Keyboard Rows",
            keywords: [
                "keyboard", "rows", "accessory", "input", "order", "reorder",
                "number", "symbols", "command", "buttons", "prefix", "hotkey",
            ],
            breadcrumb: "Logger",
            destination: .keyboardRows
        ),
        SettingsSearchItem(
            title: "Show frequency activity",
            keywords: ["frequency", "activity", "qrm", "panel"],
            breadcrumb: "Logger",
            destination: .logger
        ),
        SettingsSearchItem(
            title: "Keep screen on",
            keywords: ["screen", "sleep", "wake", "display", "idle"],
            breadcrumb: "Logger",
            destination: .logger
        ),
        SettingsSearchItem(
            title: "Auto-switch mode for frequency",
            keywords: ["auto", "mode", "switch", "frequency", "band"],
            breadcrumb: "Logger",
            destination: .logger
        ),
        SettingsSearchItem(
            title: "Keep lookup info after logging",
            keywords: ["lookup", "callsign", "card", "info", "persist", "clear", "log"],
            breadcrumb: "Logger",
            destination: .logger
        ),
        SettingsSearchItem(
            title: "Notes display",
            keywords: ["notes", "emoji", "source", "callsign", "display"],
            breadcrumb: "Logger",
            destination: .logger
        ),
        SettingsSearchItem(
            title: "Show band privilege warnings",
            keywords: ["license", "band", "privilege", "warning", "class"],
            breadcrumb: "Logger",
            destination: .logger
        ),
        SettingsSearchItem(
            title: "Always visible fields",
            keywords: ["grid", "park", "operator", "fields", "visible"],
            breadcrumb: "Logger",
            destination: .logger
        ),
        SettingsSearchItem(
            title: "WebSDR Recordings",
            keywords: ["websdr", "kiwisdr", "recording", "audio", "sdr"],
            breadcrumb: "Logger",
            destination: .webSDRRecordings
        ),
        SettingsSearchItem(
            title: "WebSDR Favorites",
            keywords: ["websdr", "kiwisdr", "favorite", "receiver", "sdr"],
            breadcrumb: "Logger",
            destination: .webSDRFavorites
        ),
        SettingsSearchItem(
            title: "Hunter Log Settings",
            keywords: ["hunter", "log", "activity", "profile", "daily", "goal"],
            breadcrumb: "Features",
            destination: .activityLogSettings
        ),
        SettingsSearchItem(
            title: "POTA Hunter Respot",
            keywords: ["pota", "hunter", "respot", "spot", "auto", "message"],
            breadcrumb: "Features > Hunter Log",
            destination: .activityLogSettings
        ),
        SettingsSearchItem(
            title: "Simple Logging Mode",
            keywords: ["simple", "logging", "chips", "header", "minimal"],
            breadcrumb: "Logger",
            destination: .logger
        ),
        SettingsSearchItem(
            title: "Share to activity feed on session end",
            keywords: ["share", "activity", "feed", "session", "end", "auto"],
            breadcrumb: "Logger",
            destination: .logger
        ),
        SettingsSearchItem(
            title: "My Equipment",
            keywords: [
                "equipment", "radio", "antenna", "key", "mic",
                "microphone", "rig", "gear", "inventory",
            ],
            breadcrumb: "Hardware",
            destination: .myEquipment
        ),
    ]

    private static let potaItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            title: "Auto-spot every 10 minutes",
            keywords: ["pota", "spot", "frequency", "auto", "timer"],
            breadcrumb: "POTA Activations",
            destination: .potaActivations
        ),
        SettingsSearchItem(
            title: "Prompt for QSY spots",
            keywords: ["pota", "qsy", "frequency", "change", "spot"],
            breadcrumb: "POTA Activations",
            destination: .potaActivations
        ),
        SettingsSearchItem(
            title: "Post QRT when ending session",
            keywords: ["pota", "qrt", "end", "session", "spot"],
            breadcrumb: "POTA Activations",
            destination: .potaActivations
        ),
        SettingsSearchItem(
            title: "Rove QRT message",
            keywords: ["pota", "rove", "qrt", "message", "spot", "park", "transition"],
            breadcrumb: "POTA Activations",
            destination: .potaActivations
        ),
        SettingsSearchItem(
            title: "Record solar & weather at start",
            keywords: ["solar", "weather", "conditions", "record", "auto"],
            breadcrumb: "POTA Activations",
            destination: .potaActivations
        ),
        SettingsSearchItem(
            title: "Poll solar conditions hourly",
            keywords: [
                "solar", "polling", "hourly", "background",
                "conditions", "sfi", "k-index",
            ],
            breadcrumb: "POTA Activations",
            destination: .potaActivations
        ),
        SettingsSearchItem(
            title: "Include equipment on brag sheet",
            keywords: ["equipment", "brag", "share", "card", "antenna", "radio"],
            breadcrumb: "POTA Activations",
            destination: .potaActivations
        ),
        SettingsSearchItem(
            title: "Professional Statistician Mode",
            keywords: ["statistician", "charts", "stats", "box plot", "distribution"],
            breadcrumb: "POTA Activations",
            destination: .potaActivations
        ),
    ]

    private static let syncSourceItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            title: "QRZ Logbook Sync",
            keywords: ["qrz", "logbook", "sync", "upload", "download"],
            breadcrumb: "Logbook Services",
            destination: .qrzLogbook
        ),
        SettingsSearchItem(
            title: "POTA",
            keywords: ["pota", "parks", "activation", "sync", "login", "oauth"],
            breadcrumb: "Logbook Services",
            destination: .pota
        ),
        SettingsSearchItem(
            title: "Ham2K LoFi",
            keywords: ["lofi", "ham2k", "sync", "cloud", "backup"],
            breadcrumb: "Logbook Services",
            destination: .lofi
        ),
        SettingsSearchItem(
            title: "HAMRS Pro",
            keywords: ["hamrs", "sync", "import"],
            breadcrumb: "Logbook Services",
            destination: .hamrs
        ),
        SettingsSearchItem(
            title: "LoTW",
            keywords: ["lotw", "logbook", "arrl", "confirmation", "qsl"],
            breadcrumb: "Logbook Services",
            destination: .lotw
        ),
        SettingsSearchItem(
            title: "Club Log",
            keywords: ["clublog", "club", "log", "dxcc", "sync"],
            breadcrumb: "Logbook Services",
            destination: .clublog
        ),
        SettingsSearchItem(
            title: "eQSL",
            keywords: ["eqsl", "qsl", "confirmation", "card", "sync"],
            breadcrumb: "Logbook Services",
            destination: .eqsl
        ),
        SettingsSearchItem(
            title: "Tiles on the Air",
            keywords: ["tota", "tiles", "grid", "maidenhead", "outdoor", "spot", "activation"],
            breadcrumb: "Logbook Services",
            destination: .tota
        ),
        SettingsSearchItem(
            title: "iCloud Sync",
            keywords: ["icloud", "sync", "cloud"],
            breadcrumb: "Account & Data",
            destination: .icloud
        ),
        SettingsSearchItem(
            title: "Community",
            keywords: ["activities", "challenges", "friends", "community", "feed", "sms"],
            breadcrumb: "Services",
            destination: .activities
        ),
        SettingsSearchItem(
            title: "Another Morse Trainer",
            keywords: ["amt", "morse", "cw", "trainer", "practice", "streak", "n9ho"],
            breadcrumb: "Services",
            destination: .amt
        ),
        SettingsSearchItem(
            title: "WSJT-X",
            keywords: ["wsjt", "wsjtx", "wsjt-x", "ft8", "ft4", "jtdx", "digital", "udp", "listener"],
            breadcrumb: "Services",
            destination: .wsjtx
        ),
    ]

    private static let dataToolItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            title: "QRZ Callsign Lookup",
            keywords: ["qrz", "callbook", "lookup", "xml", "subscription"],
            breadcrumb: "Data & Tools",
            destination: .qrzCallbook
        ),
        SettingsSearchItem(
            title: "Callsign Notes",
            keywords: ["callsign", "notes", "polo", "file", "source"],
            breadcrumb: "Data & Tools",
            destination: .callsignNotes
        ),
        SettingsSearchItem(
            title: "External Data",
            keywords: ["external", "data", "pota", "parks", "cache", "refresh"],
            breadcrumb: "Data & Tools",
            destination: .externalData
        ),
        SettingsSearchItem(
            title: "Export SQLite Database",
            keywords: ["export", "sqlite", "database", "backup", "share"],
            breadcrumb: "Data & Tools",
            destination: .dataTools
        ),
        SettingsSearchItem(
            title: "Find & Merge Duplicates",
            keywords: ["duplicate", "dedup", "merge", "cleanup", "deduplicate"],
            breadcrumb: "Data & Tools",
            destination: .dataTools
        ),
        SettingsSearchItem(
            title: "Backups",
            keywords: ["backup", "restore", "snapshot", "recovery", "database"],
            breadcrumb: "Account & Data",
            destination: .backups
        ),
    ]

    private static let developerItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            title: "Experiments",
            keywords: ["experiment", "beta", "alpha", "feature", "flag", "labs"],
            breadcrumb: "Advanced",
            destination: .experiments
        ),
        SettingsSearchItem(
            title: "Debug Mode",
            keywords: ["debug", "developer", "advanced"],
            breadcrumb: "Advanced",
            destination: .syncDebug
        ),
        SettingsSearchItem(
            title: "Read-Only Mode",
            keywords: ["read", "only", "uploads", "disabled"],
            breadcrumb: "Advanced",
            destination: .syncDebug,
            isDebugOnly: true
        ),
        SettingsSearchItem(
            title: "Bypass POTA Maintenance",
            keywords: ["bypass", "maintenance", "pota", "upload", "24/7"],
            breadcrumb: "Advanced",
            destination: .syncDebug,
            isDebugOnly: true
        ),
        SettingsSearchItem(
            title: "Sync Debug Log",
            keywords: ["sync", "debug", "log", "troubleshoot"],
            breadcrumb: "Advanced",
            destination: .syncDebug,
            isDebugOnly: true
        ),
        SettingsSearchItem(
            title: "Hidden QSOs",
            keywords: ["hidden", "deleted", "qso", "restore"],
            breadcrumb: "Advanced",
            destination: .hiddenQSOs,
            isDebugOnly: true
        ),
        SettingsSearchItem(
            title: "Spotlight Debug",
            keywords: [
                "spotlight", "search", "corespotlight", "index",
                "reindex", "rebuild", "siri",
            ],
            breadcrumb: "Advanced",
            destination: .spotlightDebug,
            isDebugOnly: true
        ),
    ]

    private static let aboutItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            title: "Attributions",
            keywords: ["attribution", "license", "third-party", "credits"],
            breadcrumb: "About",
            destination: .attributions
        ),
        SettingsSearchItem(
            title: "Report a Bug",
            keywords: ["bug", "report", "feedback", "issue", "discord"],
            breadcrumb: "Help & Support",
            destination: .aboutMe
        ),
        SettingsSearchItem(
            title: "Show App Tour",
            keywords: ["tour", "intro", "walkthrough", "onboarding"],
            breadcrumb: "Help & Support",
            destination: .aboutMe
        ),
    ]
}
