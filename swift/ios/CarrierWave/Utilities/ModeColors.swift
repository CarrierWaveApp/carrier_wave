import SwiftUI

// MARK: - ModeColors

/// Canonical mode-to-color mapping for the entire app: CW cyan, phone
/// pink, digital indigo, mixed purple. Promoted from the contest chip
/// convention so every mode label colors the same way.
enum ModeColors {
    static func color(for mode: String) -> Color {
        switch mode.uppercased() {
        case "CW": .cyan
        case "SSB",
             "PHONE",
             "USB",
             "LSB",
             "AM",
             "FM": .pink
        case "RTTY",
             "FT8",
             "FT4",
             "DIGITAL",
             "PSK",
             "PSK31",
             "JS8": .indigo
        case "MIXED": .purple
        default: .gray
        }
    }
}
