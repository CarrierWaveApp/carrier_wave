import CarrierWaveCore
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
            title: "Quick Entry",
            body: """
            Type everything in one line: callsign, RST, state, park, and notes. \
            Example: "AJ7CM 579 WA US-0189" auto-fills the form instantly.
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
            title: "POTA Accounts Explained",
            body: "POTA has two account systems that can be confusing."
        ),
        TourPage(
            icon: "server.rack",
            title: "External Logins (Google, Apple, etc.)",
            body: """
            If you registered years ago, you may have an external login (Google, Apple, etc.). \
            This is separate from your pota.app account.
            """
        ),
        TourPage(
            icon: "envelope.badge.person.crop",
            title: "Creating a pota.app Account",
            body: """
            Go to pota.app, create an account with email/password, then link your \
            existing service login in your profile settings. Carrier Wave uses \
            your pota.app credentials.
            """
        ),
    ]

    static let challenges: [TourPage] = [
        TourPage(
            icon: "person.2",
            title: "Activity & Social",
            body: """
            This is your social hub. Join challenges to track progress toward awards, \
            compete on leaderboards, and connect with the ham radio community.
            """
        ),
        TourPage(
            icon: "flag.2.crossed",
            title: "Challenges",
            body: """
            Browse and join challenges, then watch your progress as you make QSOs. \
            Compete with others on leaderboards and earn recognition for your achievements.
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

    static let lofiSetup: [TourPage] = [
        TourPage(
            icon: "icloud.and.arrow.down",
            title: "Ham2K LoFi",
            body: """
            LoFi syncs your logs from the Ham2K Portable Logger (PoLo) app. \
            It's download-only - Carrier Wave imports your PoLo operations.
            """
        ),
        TourPage(
            icon: "link.badge.plus",
            title: "Device Linking",
            body: """
            Enter the email address associated with your PoLo account. \
            You'll receive a verification code to link this device.
            """
        ),
    ]

    static func pages(for id: TourState.MiniTourID) -> [TourPage] {
        switch id {
        case .logger: logger
        case .logs: logs
        case .potaActivations: potaActivations
        case .potaAccountSetup: potaAccountSetup
        case .challenges: challenges
        case .statsDrilldown: statsDrilldown
        case .lofiSetup: lofiSetup
        }
    }
}
