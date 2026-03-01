import CarrierWaveCore
import Foundation

// MARK: - LoggerCommand

/// Commands that can be entered in the logger input field
enum LoggerCommand: Equatable {
    /// Change frequency (e.g., "14.060" or "FREQ 14.060")
    case frequency(Double)

    /// Change mode (e.g., "MODE CW")
    case mode(String)

    /// Self-spot to POTA with optional comment
    case spot(comment: String?)

    /// Show RBN spots panel for a callsign (nil = user's callsign)
    case rbn(callsign: String?)

    /// Show activator spots panel (POTA + SOTA)
    case hunt

    /// Show P2P (park-to-park) opportunities panel
    case p2p

    /// Show solar conditions panel
    case solar

    /// Show weather panel
    case weather

    /// Show session map
    case map

    /// Show hidden QSOs
    case hidden

    /// Show help
    case help

    /// Add a note to the session log
    case note(text: String)

    /// Open radio manual in CW Field Guide
    case manual

    /// Show WebSDR recording panel
    case websdr

    /// Show band picker with recommended frequencies
    case band

    /// Change radio/rig
    case rig

    /// Open outing checklists in CW Field Guide
    case checklist

    /// Show BLE radio control panel
    case radio

    // MARK: Internal

    /// Help text listing all available commands
    static var helpText: String {
        """
        Available Commands:

        FREQ <freq>     - Set frequency
                          e.g., 14.060, 14060 kHz, 14.060 MHz
        BAND            - Pick band with recommended frequencies
        MODE <mode>     - Set mode (CW, SSB, FT8, etc.)
                          or type mode directly: CW, SSB, FT8
        RIG             - Change equipment (radio, antenna, key)
        SPOT [comment]  - Self-spot to POTA
                          e.g., SPOT QRT, SPOT QSY
        QRT             - Self-spot QRT to POTA
        RBN [callsign]  - Show RBN/POTA spots
                          e.g., RBN W1AW (or just RBN for your spots)
        HUNT            - Show activator spots (POTA + SOTA)
                          (or POTA, SPOTS)
        P2P             - Find park-to-park opportunities
                          (POTA activations only)
        SOLAR           - Show solar conditions
        WEATHER         - Show weather (or WX)
        MAP             - Show session QSO map
        HIDDEN          - Show deleted QSOs (or DELETED)
        NOTE <text>     - Add a note to the session log
        MANUAL          - Open radio manual (or MAN)
        CHECKLIST       - Open outing checklists (or CL)
        WEBSDR          - Record from a nearby WebSDR
                          (or SDR, REC, RECORD, SWL)
        RADIO           - Show BLE radio control panel
                          (or CAT, RIG-BLE)
        HELP            - Show this help (or ?)

        Type a frequency directly: 14.060, 14060, 14060kHz
        """
    }

    /// Description of the command for display
    var description: String {
        switch self {
        case let .frequency(freq):
            "Set frequency to \(FrequencyFormatter.formatWithUnit(freq))"
        case let .mode(mode):
            "Set mode to \(mode)"
        case let .spot(comment):
            if let comment, !comment.isEmpty {
                "Self-spot to POTA: \"\(comment)\""
            } else {
                "Self-spot to POTA"
            }
        case let .rbn(callsign):
            if let callsign {
                "Show spots for \(callsign)"
            } else {
                "Show your spots"
            }
        case .hunt:
            "Show activator spots"
        case .p2p:
            "Find P2P opportunities"
        case .solar:
            "Show solar conditions"
        case .weather:
            "Show weather"
        case .map:
            "Show session map"
        case .hidden:
            "Show deleted QSOs"
        case .help:
            "Show available commands"
        case let .note(text):
            "Add note: \"\(text)\""
        case .manual:
            "Open radio manual"
        case .checklist:
            "Open outing checklists"
        case .websdr:
            "Record from WebSDR"
        case .band:
            "Pick band with recommended frequencies"
        case .rig:
            "Change equipment"
        case .radio:
            "Show radio control panel"
        }
    }

    /// Icon for the command
    var icon: String {
        switch self {
        case .frequency:
            "antenna.radiowaves.left.and.right"
        case .mode:
            "waveform"
        case .spot:
            "mappin.and.ellipse"
        case .rbn:
            "dot.radiowaves.up.forward"
        case .hunt:
            "binoculars"
        case .p2p:
            "arrow.left.arrow.right"
        case .solar:
            "sun.max"
        case .weather:
            "cloud.sun"
        case .map:
            "map"
        case .hidden:
            "eye.slash"
        case .help:
            "questionmark.circle"
        case .note:
            "note.text"
        case .manual:
            "book.closed"
        case .checklist:
            "checklist"
        case .websdr:
            "radio"
        case .band:
            "list.bullet.rectangle.portrait"
        case .rig:
            "radio"
        case .radio:
            "antenna.radiowaves.left.and.right"
        }
    }

    /// Parse input string to command
    /// Returns nil if input is not a command (treat as callsign)
    static func parse(_ input: String) -> LoggerCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        let upper = trimmed.uppercased()

        // Try parsers in order of specificity
        if let cmd = parseFrequency(trimmed: trimmed, upper: upper) {
            return cmd
        }
        if let cmd = parseMode(trimmed: trimmed, upper: upper) {
            return cmd
        }
        if let cmd = parseSpot(trimmed: trimmed, upper: upper) {
            return cmd
        }
        if let cmd = parseRBN(trimmed: trimmed, upper: upper) {
            return cmd
        }
        if let cmd = parseHunt(upper: upper) {
            return cmd
        }
        if let cmd = parseP2P(upper: upper) {
            return cmd
        }
        if let cmd = parseNote(trimmed: trimmed, upper: upper) {
            return cmd
        }
        return parseSingleWord(upper: upper)
    }

    // MARK: Private

    /// Valid mode strings
    private static let validModes: Set<String> = [
        "CW",
        "SSB",
        "USB",
        "LSB",
        "AM",
        "FM",
        "FT8",
        "FT4",
        "RTTY",
        "PSK31",
        "PSK",
        "DIGITAL",
        "DATA",
        "SSTV",
        "JT65",
        "JT9",
        "WSPR",
    ]

    private static func parseFrequency(trimmed: String, upper: String) -> LoggerCommand? {
        // Check for frequency (supports MHz, kHz, or bare numbers)
        // FrequencyFormatter.parse handles unit suffixes and kHz->MHz conversion
        if let freq = FrequencyFormatter.parse(trimmed) {
            return .frequency(freq)
        }

        // Check for FREQ command
        if upper.hasPrefix("FREQ ") || upper.hasPrefix("FREQ\t") {
            let value = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if let freq = FrequencyFormatter.parse(value) {
                return .frequency(freq)
            }
        }
        return nil
    }

    private static func parseMode(trimmed: String, upper: String) -> LoggerCommand? {
        // Check for MODE command
        if upper.hasPrefix("MODE ") || upper.hasPrefix("MODE\t") {
            let mode = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                .uppercased()
            if validModes.contains(mode) {
                return .mode(mode)
            }
            return nil
        }

        // Check for bare mode name (e.g., "CW", "SSB")
        if validModes.contains(upper) {
            return .mode(upper)
        }
        return nil
    }

    private static func parseSpot(trimmed: String, upper: String) -> LoggerCommand? {
        if upper == "SPOT" {
            return .spot(comment: nil)
        }
        if upper.hasPrefix("SPOT ") {
            let comment = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            return .spot(comment: comment.isEmpty ? nil : comment)
        }
        return nil
    }

    private static func parseRBN(trimmed: String, upper: String) -> LoggerCommand? {
        if upper == "RBN" {
            return .rbn(callsign: nil)
        }
        if upper.hasPrefix("RBN ") {
            let callsign = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                .uppercased()
            return .rbn(callsign: callsign.isEmpty ? nil : callsign)
        }
        return nil
    }

    private static func parseHunt(upper: String) -> LoggerCommand? {
        if upper == "HUNT" || upper == "POTA" || upper == "SPOTS" {
            return .hunt
        }
        return nil
    }

    private static func parseP2P(upper: String) -> LoggerCommand? {
        if upper == "P2P" {
            return .p2p
        }
        return nil
    }

    private static func parseNote(trimmed: String, upper: String) -> LoggerCommand? {
        if upper.hasPrefix("NOTE ") {
            let text = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                return .note(text: text)
            }
        }
        return nil
    }

    private static func parseSingleWord(upper: String) -> LoggerCommand? {
        switch upper {
        case "BAND":
            .band
        case "RIG":
            .rig
        case "SOLAR":
            .solar
        case "WEATHER",
             "WX":
            .weather
        case "MAP":
            .map
        case "HIDDEN",
             "DELETED":
            .hidden
        case "MANUAL",
             "MAN":
            .manual
        case "CHECKLIST",
             "CL":
            .checklist
        case "WEBSDR",
             "SDR",
             "REC",
             "RECORD",
             "SWL":
            .websdr
        case "RADIO",
             "CAT",
             "RIG-BLE":
            .radio
        case "QRT":
            .spot(comment: "QRT")
        case "HELP",
             "?":
            .help
        default:
            nil
        }
    }
}
