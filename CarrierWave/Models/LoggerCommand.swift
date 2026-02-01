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

    // MARK: Internal

    /// Help text listing all available commands
    static var helpText: String {
        """
        Available Commands:

        FREQ <MHz>      - Set frequency (e.g., 14.060)
        <mode>          - Set mode (CW, SSB, FT8, etc.)
        SPOT [comment]  - Self-spot to POTA
                          e.g., SPOT QRT, SPOT QSY
        RBN [callsign]  - Show RBN/POTA spots
                          e.g., RBN W1AW (or just RBN for your spots)
        SOLAR           - Show solar conditions
        WEATHER         - Show weather (or WX)
        MAP             - Show session QSO map
        HIDDEN          - Show deleted QSOs
        NOTE <text>     - Add a note to the session log
        HELP            - Show this help (or ?)

        You can also just type a frequency like "14.060"
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
        // Check for frequency (number only, between 1.8 and 450 MHz)
        if let freq = Double(trimmed), freq >= 1.8, freq <= 450.0 {
            return .frequency(freq)
        }

        // Check for FREQ command
        if upper.hasPrefix("FREQ ") || upper.hasPrefix("FREQ\t") {
            let value = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if let freq = Double(value), freq >= 1.8, freq <= 450.0 {
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
        case "HELP",
             "?":
            .help
        default:
            nil
        }
    }
}

// MARK: - Command Suggestions

extension LoggerCommand {
    /// Get command suggestions for autocomplete
    static func suggestions(for input: String) -> [CommandSuggestion] {
        let upper = input.uppercased()
        return allSuggestions.filter { $0.matches(upper) }
    }

    /// All available command suggestions
    private static let allSuggestions: [CommandSuggestion] = [
        // Frequency
        CommandSuggestion(
            command: "FREQ 14.060", description: "Set frequency",
            icon: "antenna.radiowaves.left.and.right", prefixes: ["FREQ", "F"]
        ),
        // Modes
        CommandSuggestion(
            command: "CW", description: "Set mode to CW",
            icon: "waveform", prefixes: ["C"]
        ),
        CommandSuggestion(
            command: "SSB", description: "Set mode to SSB",
            icon: "waveform", prefixes: ["SS"], exact: ["S"]
        ),
        CommandSuggestion(
            command: "FT8", description: "Set mode to FT8",
            icon: "waveform", prefixes: ["FT"]
        ),
        CommandSuggestion(
            command: "FT4", description: "Set mode to FT4",
            icon: "waveform", prefixes: ["FT"]
        ),
        CommandSuggestion(
            command: "RTTY", description: "Set mode to RTTY",
            icon: "waveform", prefixes: ["RT"]
        ),
        CommandSuggestion(
            command: "AM", description: "Set mode to AM",
            icon: "waveform", prefixes: ["AM"]
        ),
        CommandSuggestion(
            command: "FM", description: "Set mode to FM",
            icon: "waveform", prefixes: ["FM"]
        ),
        // SPOT
        CommandSuggestion(
            command: "SPOT", description: "Self-spot to POTA",
            icon: "mappin.and.ellipse", prefixes: ["SP"], exact: ["S"]
        ),
        // RBN
        CommandSuggestion(
            command: "RBN", description: "Show your spots",
            icon: "dot.radiowaves.up.forward", prefixes: ["RB"], exact: ["R"]
        ),
        CommandSuggestion(
            command: "RBN W1AW", description: "Show spots for callsign",
            icon: "dot.radiowaves.up.forward", prefixes: ["RB"], exact: ["R"]
        ),
        // SOLAR
        CommandSuggestion(
            command: "SOLAR", description: "Show solar conditions",
            icon: "sun.max", prefixes: ["SO"]
        ),
        // WEATHER
        CommandSuggestion(
            command: "WEATHER", description: "Show weather",
            icon: "cloud.sun", prefixes: ["WE", "WX"], exact: ["W"]
        ),
        // MAP
        CommandSuggestion(
            command: "MAP", description: "Show session map",
            icon: "map", prefixes: ["MA"]
        ),
        // HIDDEN
        CommandSuggestion(
            command: "HIDDEN", description: "Show deleted QSOs",
            icon: "eye.slash", prefixes: ["HI", "DE"]
        ),
        // NOTE
        CommandSuggestion(
            command: "NOTE ", description: "Add a note to session log",
            icon: "note.text", prefixes: ["NO"], exact: ["N"]
        ),
        // HELP
        CommandSuggestion(
            command: "HELP", description: "Show available commands",
            icon: "questionmark.circle", prefixes: ["HE"], exact: ["H", "?"]
        ),
    ]
}

// MARK: - CommandSuggestion

/// A command suggestion for autocomplete
struct CommandSuggestion: Identifiable {
    let id = UUID()
    let command: String
    let description: String
    let icon: String

    /// Prefixes that trigger this suggestion (e.g., "FR" matches "FREQ")
    var prefixes: [String] = []
    /// Exact matches that trigger this suggestion (e.g., "?" matches "HELP")
    var exact: [String] = []

    /// Check if this suggestion matches the input
    func matches(_ input: String) -> Bool {
        if exact.contains(input) {
            return true
        }
        return prefixes.contains { input.hasPrefix($0) }
    }
}
