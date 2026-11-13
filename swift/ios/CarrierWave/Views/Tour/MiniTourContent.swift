import CarrierWaveData
import Foundation

// MARK: - MiniTourContent

enum MiniTourContent {
    static let logger: [TourPage] = [
        TourPage(
            icon: "pencil.and.list.clipboard",
            title: "QSO Logger",
            body: """
            Log your contacts here. Each session tracks your frequency, mode, \
            and activation type (casual, POTA, or SOTA).
            """
        ),
        TourPage(
            icon: "play.fill",
            title: "Starting a Session",
            body: """
            Tap the Start button in the header to begin a new session. \
            Set your callsign, frequency, mode, and optionally a park or summit reference.
            """
        ),
        TourPage(
            icon: "stop.fill",
            title: "Ending a Session",
            body: """
            Tap the red END button in the session header when you're done. \
            Your QSOs are saved and ready to sync to QRZ, POTA, or LoFi.
            """
        ),
        TourPage(
            icon: "person.text.rectangle",
            title: "Callsign Lookup",
            body: """
            As you type, callsign info is fetched from QRZ (requires QRZ XML subscription) \
            or HamDB. Name, location, and grid are saved with your QSO.
            """
        ),
        TourPage(
            icon: "note.text",
            title: "Callsign Notes",
            body: """
            Add Polo-style notes files in Settings to see custom info and emoji for callsigns. \
            Great for tracking club members or favorite operators.
            """
        ),
        TourPage(
            icon: "command",
            title: "Logger Commands",
            body: """
            Type commands like FREQ, MODE, SPOT, RBN, SOLAR, WEATHER, MAP, or HELP \
            directly in the callsign field. Press Return to execute.
            """
        ),
        TourPage(
            icon: "text.line.first.and.arrowtriangle.forward",
            title: "Logging a QSO",
            body: """
            Type a callsign and press Return to log instantly. \
            Or type everything in one line — "AJ7CM 579 WA" fills RST \
            and QTH automatically. Edit any QSO later by tapping it.
            """
        ),
        TourPage(
            icon: "slider.horizontal.3",
            title: "Per-Field Entry",
            body: """
            Want to fill in RST or QTH before logging? \
            Enable the field entry form in Logger settings to show \
            Sent, Rcvd, and QTH fields below the callsign input.
            """
        ),
    ]

    static let logs: [TourPage] = [
        TourPage(
            icon: "list.bullet.rectangle",
            title: "Your QSO Log",
            body: """
            Browse and search your logged contacts here. QSOs sync from QRZ, POTA, \
            and LoFi, and are uploaded when you log new contacts.
            """
        ),
        TourPage(
            icon: "magnifyingglass",
            title: "Simple Search",
            body: """
            Type a callsign like W1AW to find contacts with that station. \
            Use wildcards like K1* to match all callsigns starting with K1.
            """
        ),
        TourPage(
            icon: "line.3.horizontal.decrease",
            title: "Field Filters",
            body: """
            Filter by field using field:value syntax. Examples: band:20m, mode:CW, \
            state:CA, park:K-1234, grid:FN31.
            """
        ),
        TourPage(
            icon: "calendar",
            title: "Date Filters",
            body: """
            Use date:today, after:7d (last 7 days), after:30d (last 30 days), \
            or specific dates like date:2024-01 or before:2024-06-01.
            """
        ),
        TourPage(
            icon: "checkmark.circle",
            title: "Status Filters",
            body: """
            Find confirmed contacts with confirmed:lotw or confirmed:qrz. \
            Check upload status with synced:pota or pending:yes.
            """
        ),
        TourPage(
            icon: "plus.circle",
            title: "Combining Filters",
            body: """
            Combine filters with spaces (AND): band:20m mode:CW after:30d. \
            Use | for OR: W1AW | K1ABC. Exclude with -: -mode:FT8.
            """
        ),
    ]

    static let potaActivations: [TourPage] = [
        TourPage(
            icon: "tree",
            title: "Your POTA Activations",
            body: """
            QSOs with a park reference are grouped here by park and date. \
            Each group is an activation you can upload to POTA.
            """
        ),
        TourPage(
            icon: "arrow.up.doc",
            title: "Uploading to POTA",
            body: """
            Tap an activation to review its QSOs, then upload. You need 10+ QSOs \
            for activation credit, but you can upload smaller logs to credit your hunters.
            """
        ),
    ]

    static let potaAccountSetup: [TourPage] = [
        TourPage(
            icon: "person.2.badge.gearshape",
            title: "POTA Login Requirements",
            body: """
            Carrier Wave needs a pota.app email and password to log in. \
            Google, Apple, and other external logins won't work here.
            """
        ),
        TourPage(
            icon: "exclamationmark.triangle",
            title: "Using an External Login?",
            body: """
            If you log into POTA using Google, Apple, or another service, you also need \
            to create a pota.app account with the same email address. Go to pota.app and \
            click Sign Up to create one.
            """
        ),
        TourPage(
            icon: "envelope.badge.person.crop",
            title: "Example",
            body: """
            If your Google login is joe@gmail.com, create a pota.app account with \
            joe@gmail.com and a new password. Use that email and password here. \
            It may take a few minutes for the new account to activate.
            """
        ),
    ]

    static let challenges: [TourPage] = [
        TourPage(
            icon: "person.2",
            title: "Activity & Social",
            body: """
            This is your social hub. See your activity feed, connect with the \
            ham radio community, and track your milestones.
            """
        ),
        TourPage(
            icon: "person.badge.plus",
            title: "Friends & Clubs",
            body: """
            Add friends to see their activity, or join clubs to connect with groups. \
            Use the toolbar buttons to manage your connections. More social features coming soon!
            """
        ),
    ]

    static let statsDrilldown: [TourPage] = [
        TourPage(
            icon: "chart.bar.xaxis",
            title: "Explore Your Stats",
            body: """
            Tap any statistic to see the breakdown. Expand individual items to view \
            the QSOs that count toward that total.
            """
        ),
    ]

    static let activityLog: [TourPage] = [
        TourPage(
            icon: "scope",
            title: "Hunter Log",
            body: """
            Your always-on logbook for everyday contacts. \
            No session to start or stop — just open and log.
            """
        ),
        TourPage(
            icon: "text.line.first.and.arrowtriangle.forward",
            title: "Quick Entry",
            body: """
            Type a callsign and tap Log, or enter everything in one line: \
            "AJ7CM 579 WA US-0189" to auto-fill RST, state, and park. \
            Suggestions appear as you type — tap one to fill the callsign. \
            Expand the fields row for QTH, grid, park, and notes.
            """
        ),
        TourPage(
            icon: "antenna.radiowaves.left.and.right",
            title: "Station Profiles",
            body: """
            Set up a station profile with your radio, power, antenna, and grid \
            via the gear icon. Switch profiles when you change operating conditions.
            """
        ),
        TourPage(
            icon: "chart.bar.xaxis",
            title: "Daily Tracking",
            body: """
            Your daily QSO count, bands, and modes update in real time. \
            Set a daily goal in settings to stay motivated.
            """
        ),
        TourPage(
            icon: "arrow.up.doc",
            title: "Automatic Uploads",
            body: """
            QSOs are marked for upload to QRZ and LoFi automatically. \
            Hunter log contacts never go to POTA — use a POTA session for activations.
            """
        ),
    ]
}

// MARK: - Sync Setup Guides

extension MiniTourContent {
    static let qrzSetup: [TourPage] = [
        TourPage(
            icon: "arrow.triangle.2.circlepath.circle.fill",
            title: "QRZ Logbook Sync",
            body: """
            QRZ provides two-way sync — Carrier Wave downloads your existing QSOs \
            and uploads new ones. Requires a QRZ XML Logbook Data subscription.
            """
        ),
        TourPage(
            icon: "key.fill",
            title: "Getting Your API Key",
            body: """
            Log into qrz.com, go to your Logbook, then Settings. \
            Copy your API key and paste it here. This is different from \
            your QRZ login password. Each callsign has its own logbook \
            API key — if you operate under multiple calls, use the key \
            for the callsign you want to sync.
            """
        ),
        TourPage(
            icon: "arrow.clockwise",
            title: "How Sync Works",
            body: """
            Carrier Wave checks QRZ for new QSOs periodically and after each \
            session. New contacts you log are uploaded automatically. \
            Duplicate detection prevents double-logging.
            """
        ),
    ]

    static let lofiSetup: [TourPage] = [
        TourPage(
            icon: "icloud.and.arrow.down",
            title: "Ham2K LoFi",
            body: """
            LoFi syncs your logs from the Ham2K Portable Logger (PoLo) app. \
            It's download-only — Carrier Wave imports your PoLo operations.
            """
        ),
        TourPage(
            icon: "link.badge.plus",
            title: "Device Linking",
            body: """
            Enter the email address associated with your PoLo account. \
            You'll receive a verification email to link this device. \
            Tap "I've confirmed the email" after verifying.
            """
        ),
        TourPage(
            icon: "person.badge.key",
            title: "Download Permission",
            body: """
            LoFi download access must be enabled by Ham2K staff. \
            If you see 0 QSOs after syncing, join the Ham2K Discord \
            server and contact KI2D to request access.
            """
        ),
    ]

    static func pages(for id: TourState.MiniTourID) -> [TourPage] {
        switch id {
        case .logger: logger
        case .loggerInteractive: logger
        case .logs: logs
        case .potaActivations: potaActivations
        case .potaAccountSetup: potaAccountSetup
        case .challenges: challenges
        case .statsDrilldown: statsDrilldown
        case .lofiSetup: lofiSetup
        case .activityLog: activityLog
        }
    }
}
