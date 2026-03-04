import Foundation

// MARK: - MockTourSession

/// Ephemeral mock session data for the interactive tour.
/// Plain struct — never touches SwiftData or persistence.
struct MockTourSession {
    let callsign = "KI5GTR"
    let frequency: Double = 14.060
    let mode = "CW"
    let band = "20m"
    let park = "US-0189"
    let parkName = "Saguaro National Park"
    let radio = "Elecraft KX3"
    let antenna = "EFHW 40/20/15/10"
    let key = "CW Morse Pocket Paddle"
    let grid = "DM42"
    let power = 10

    var formattedFrequency: String { "14.060" }

    var equipmentSummary: String { "KX3 +2" }
}

// MARK: - MockTourQSO

/// Ephemeral mock QSO for the interactive tour.
struct MockTourQSO: Identifiable {
    let id = UUID()
    let callsign: String
    let rstSent: String
    let rstReceived: String
    let qth: String
    let grid: String
    let isParkToPark: Bool
    let isDuplicate: Bool
    let theirPark: String?
    let time: String

    static let samples: [MockTourQSO] = [
        MockTourQSO(
            callsign: "AJ7CM",
            rstSent: "599",
            rstReceived: "599",
            qth: "AZ",
            grid: "DM42",
            isParkToPark: false,
            isDuplicate: false,
            theirPark: nil,
            time: "18:01"
        ),
        MockTourQSO(
            callsign: "K5YAA",
            rstSent: "579",
            rstReceived: "559",
            qth: "TX",
            grid: "EM12",
            isParkToPark: true,
            isDuplicate: false,
            theirPark: "US-0534",
            time: "18:04"
        ),
        MockTourQSO(
            callsign: "N3FJP",
            rstSent: "599",
            rstReceived: "589",
            qth: "MD",
            grid: "FM19",
            isParkToPark: false,
            isDuplicate: false,
            theirPark: nil,
            time: "18:07"
        ),
        MockTourQSO(
            callsign: "AJ7CM",
            rstSent: "599",
            rstReceived: "599",
            qth: "AZ",
            grid: "DM42",
            isParkToPark: false,
            isDuplicate: true,
            theirPark: nil,
            time: "18:12"
        ),
    ]
}

// MARK: - TourGuideMessage

/// Content for a single tour step narration.
struct TourGuideMessage {
    let text: String
    let buttonLabel: String

    static let steps: [LoggerTourStep: TourGuideMessage] = [
        .welcome: TourGuideMessage(
            text: """
            Hey, I'm KI5GTR — I built Carrier Wave and I'll walk you through \
            running a POTA activation session. Nothing here is real, so don't \
            worry about messing anything up.
            """,
            buttonLabel: "Let's Go"
        ),
        .startSession: TourGuideMessage(
            text: """
            This is where you set up your session. I've filled in my callsign \
            and frequency. Scroll around and explore — when you're ready, tap Next.
            """,
            buttonLabel: "Next"
        ),
        .pickEquipment: TourGuideMessage(
            text: """
            Add your radio, antenna, and key. These are saved with every QSO \
            so you can track what gear works best.
            """,
            buttonLabel: "Next"
        ),
        .setPark: TourGuideMessage(
            text: """
            Pick your activation program and park reference. Carrier Wave \
            handles POTA, SOTA, WWFF, and AoA.
            """,
            buttonLabel: "Next"
        ),
        .activeSession: TourGuideMessage(
            text: """
            You're on the air! The header shows your session at a glance. \
            Tap any capsule to change it mid-session.
            """,
            buttonLabel: "Next"
        ),
        .logQSO: TourGuideMessage(
            text: """
            Type a callsign and press Return to log. You can also type \
            everything at once — try "AJ7CM 579 WA" for quick entry. \
            Callsign info is looked up automatically.
            """,
            buttonLabel: "Next"
        ),
        .moreQSOs: TourGuideMessage(
            text: """
            QSOs stack up in your log. Park-to-park contacts get a special \
            badge. And if you work someone twice on the same band, Carrier \
            Wave flags the dupe.
            """,
            buttonLabel: "Next"
        ),
        .commands: TourGuideMessage(
            text: """
            The callsign field doubles as a command line. Type FREQ to change \
            frequency, SPOT to self-spot, MAP to see your contacts on a map, \
            and more.
            """,
            buttonLabel: "Next"
        ),
        .sdrRecording: TourGuideMessage(
            text: """
            If you have a WebSDR nearby, Carrier Wave can record your signal \
            off the air. Start recording from the session setup or type SDR.
            """,
            buttonLabel: "Next"
        ),
        .wrapUp: TourGuideMessage(
            text: """
            That's the basics! When you're done, tap END to close your session. \
            Your log syncs to QRZ, POTA, and LoFi automatically. 73 and good DX!
            """,
            buttonLabel: "Get Started"
        ),
    ]
}
