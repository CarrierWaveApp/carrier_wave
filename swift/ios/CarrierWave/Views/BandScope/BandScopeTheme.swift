import SwiftUI

// MARK: - BandScopeTheme

/// Feature-scoped tokens mapped onto the app-wide semantic palette
/// (docs/design-language.md). The Band Scope adapts to light/dark like
/// every other surface — no hardcoded hex values, no forced appearance.
enum BandScopeTheme {
    // MARK: - Palette

    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.systemGray6)
    static let surface2 = Color(.systemGray5)
    static let line = Color(.separator)
    static let text = Color.primary
    static let dim = Color.secondary
    static let faint = Color(.tertiaryLabel)
    static let youLine = Color(.label)

    static let green = Color.green
    static let amber = Color.orange
    static let blue = Color.blue
    static let gray = Color(.systemGray)

    /// Chip background alpha — matches the app-wide badge tint (§9).
    static let chipBackgroundAlpha = 0.2

    static func color(for tier: SpotTier) -> Color {
        switch tier {
        case .needed: amber
        case .club: blue
        case .pota: green
        case .rbn: gray
        }
    }

    /// Only the `needed` tier glows (§2).
    static func glows(_ tier: SpotTier) -> Bool {
        tier == .needed
    }
}
