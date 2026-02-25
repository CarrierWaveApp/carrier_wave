import Foundation

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
        // Band picker
        CommandSuggestion(
            command: "BAND", description: "Pick band with live spots",
            icon: "list.bullet.rectangle.portrait", prefixes: ["BA"], exact: ["B"]
        ),
        // Rig
        CommandSuggestion(
            command: "RIG", description: "Change equipment",
            icon: "radio", prefixes: ["RI"]
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
        // POTA
        CommandSuggestion(
            command: "POTA", description: "Show POTA activator spots",
            icon: "tree.fill", prefixes: ["PO"], exact: ["P"]
        ),
        // P2P
        CommandSuggestion(
            command: "P2P", description: "Find P2P opportunities",
            icon: "arrow.left.arrow.right", prefixes: ["P2"]
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
        // MANUAL
        CommandSuggestion(
            command: "MANUAL", description: "Open radio manual",
            icon: "book.closed", prefixes: ["MAN"]
        ),
        // CHECKLIST
        CommandSuggestion(
            command: "CHECKLIST", description: "Open outing checklists",
            icon: "checklist", prefixes: ["CH", "CL"]
        ),
        // QRT
        CommandSuggestion(
            command: "QRT", description: "Self-spot QRT to POTA",
            icon: "mappin.and.ellipse", prefixes: ["QR"], exact: ["Q"]
        ),
        // WEBSDR
        CommandSuggestion(
            command: "WEBSDR", description: "Record from a nearby WebSDR",
            icon: "radio", prefixes: ["WEB", "SDR", "REC", "SWL"]
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
