// Video Render Context
//
// Resolved color palette + draw-time config consumed by the renderer.
// Built once per export from the ThemePreset in VideoExportConfig.

import CoreGraphics
import Foundation

// MARK: - VideoThemePalette

nonisolated struct VideoThemePalette {
    let accent: CGColor
    let accentStroke: CGColor
    let hudBackground: CGColor
    let primaryText: CGColor
    let secondaryText: CGColor
    let cardBackground: CGColor
    let arcColor: CGColor
    let spotPulse: CGColor
    let mapFallback: CGColor
}

// MARK: - Palette Presets

nonisolated extension VideoThemePalette {
    static func resolve(_ preset: ThemePreset) -> VideoThemePalette {
        switch preset {
        case .classic: .classic
        case .night: .night
        case .highContrast: .highContrast
        case .minimal: .minimal
        }
    }

    static let classic = VideoThemePalette(
        accent: CGColor(red: 0.18, green: 0.46, blue: 0.96, alpha: 1),
        accentStroke: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        hudBackground: CGColor(red: 0, green: 0, blue: 0, alpha: 0.75),
        primaryText: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        secondaryText: CGColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1),
        cardBackground: CGColor(red: 0, green: 0, blue: 0, alpha: 0.7),
        arcColor: CGColor(red: 0.18, green: 0.46, blue: 0.96, alpha: 1),
        spotPulse: CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1),
        mapFallback: CGColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
    )

    static let night = VideoThemePalette(
        accent: CGColor(red: 0.40, green: 0.65, blue: 1.0, alpha: 1),
        accentStroke: CGColor(red: 0.85, green: 0.90, blue: 1.0, alpha: 1),
        hudBackground: CGColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 0.85),
        primaryText: CGColor(red: 0.92, green: 0.94, blue: 1.0, alpha: 1),
        secondaryText: CGColor(red: 0.60, green: 0.68, blue: 0.85, alpha: 1),
        cardBackground: CGColor(red: 0.03, green: 0.05, blue: 0.10, alpha: 0.80),
        arcColor: CGColor(red: 0.40, green: 0.65, blue: 1.0, alpha: 1),
        spotPulse: CGColor(red: 0.35, green: 0.85, blue: 0.55, alpha: 1),
        mapFallback: CGColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 1)
    )

    static let highContrast = VideoThemePalette(
        accent: CGColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1),
        accentStroke: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        hudBackground: CGColor(red: 0, green: 0, blue: 0, alpha: 0.95),
        primaryText: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        secondaryText: CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1),
        cardBackground: CGColor(red: 0, green: 0, blue: 0, alpha: 0.9),
        arcColor: CGColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1),
        spotPulse: CGColor(red: 0.0, green: 1.0, blue: 0.4, alpha: 1),
        mapFallback: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    )

    static let minimal = VideoThemePalette(
        accent: CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1),
        accentStroke: CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1),
        hudBackground: CGColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 0.7),
        primaryText: CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1),
        secondaryText: CGColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1),
        cardBackground: CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.75),
        arcColor: CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1),
        spotPulse: CGColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1),
        mapFallback: CGColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
    )
}

// MARK: - VideoExportConfig + Palette

nonisolated extension VideoExportConfig {
    var palette: VideoThemePalette {
        VideoThemePalette.resolve(theme)
    }
}
