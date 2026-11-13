import SwiftUI

// MARK: - SatelliteTheme

/// Design tokens for the Satellites workspace: Carrier Wave's own dark look
/// (near-black canvas, system-gray cards, system blue / green / red / yellow
/// accents, monospaced callsigns and numbers) with the instrument feel of a
/// tracker console — labelled fields and tabular monospaced readouts.
enum SatelliteTheme {
    // MARK: Internal

    /// Canvas and cards (match `Color(.systemBackground)` / `systemGray6` /
    /// `systemGray5` in dark mode, which the rest of the app uses).
    static let background = Color.black
    static let panel = Color(red: 0.110, green: 0.110, blue: 0.118) // #1C1C1E
    static let panelRaised = Color(red: 0.173, green: 0.173, blue: 0.180) // #2C2C2E
    static let hairline = Color.white.opacity(0.10)
    static let gridLine = Color.white.opacity(0.22)

    /// Text.
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93 systemGray
    static let textTertiary = Color(red: 0.388, green: 0.388, blue: 0.400) // #636366 systemGray2

    /// Accents (system palette, as used across Carrier Wave).
    static let accent = Color(red: 0.039, green: 0.518, blue: 1.0) // #0A84FF track / selection
    static let satellite = Color(red: 1.0, green: 0.839, blue: 0.039) // #FFD60A satellite / now
    static let rx = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158 RX / linked
    static let tx = Color(red: 1.0, green: 0.271, blue: 0.227) // #FF453A TX / stop
    static let nearWhite = Color(red: 0.96, green: 0.96, blue: 0.97)

    /// Waterfall colormap stops: black → deep blue (noise floor) → blue →
    /// green → yellow → red → white. The floor stays dim so only signals glow.
    static let waterfallStops: [(location: Double, color: Color)] = [
        (0.00, background),
        (0.30, Color(red: 0.03, green: 0.10, blue: 0.28)),
        (0.50, accent),
        (0.66, rx),
        (0.80, satellite),
        (0.91, tx),
        (1.00, nearWhite)
    ]

    /// Numbers, callsigns, frequencies: monospaced (tabular by nature).
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Labels and prose: the system font.
    static func label(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Resolve a 0…1 magnitude to a waterfall color (linear interpolation
    /// between stops). Used by the Canvas renderer per cell.
    static func waterfallColor(_ value: Double) -> Color {
        let clamped = min(max(value, 0), 1)
        var lower = waterfallStops[0]
        var upper = waterfallStops[waterfallStops.count - 1]
        for index in 1 ..< waterfallStops.count where waterfallStops[index].location >= clamped {
            lower = waterfallStops[index - 1]
            upper = waterfallStops[index]
            break
        }
        let span = upper.location - lower.location
        let fraction = span > 0 ? (clamped - lower.location) / span : 0
        return lower.color.mixed(with: upper.color, by: fraction)
    }

    /// Pre-sampled lookup table (256 entries) so a 512×200 waterfall doesn't
    /// interpolate per cell.
    static let waterfallLUT: [Color] = (0 ..< 256).map { waterfallColor(Double($0) / 255) }
}

extension Color {
    /// Linear RGB blend toward `other` in the sRGB component space.
    func mixed(with other: Color, by amount: Double) -> Color {
        let from = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let to = NSColor(other).usingColorSpace(.sRGB) ?? NSColor(other)
        let fraction = CGFloat(min(max(amount, 0), 1))
        return Color(
            red: Double(from.redComponent + (to.redComponent - from.redComponent) * fraction),
            green: Double(from.greenComponent + (to.greenComponent - from.greenComponent) * fraction),
            blue: Double(from.blueComponent + (to.blueComponent - from.blueComponent) * fraction)
        )
    }
}
