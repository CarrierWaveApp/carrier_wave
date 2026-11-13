import SwiftUI

// MARK: - BandColors

/// Canonical band-to-color mapping for the entire app.
/// Follows a spectral gradient: low-frequency bands get warm colors, high-frequency bands get cool colors.
/// This replaces the scattered per-file `bandColor` functions throughout the codebase.
enum BandColors {
    // MARK: Internal

    /// Returns the color associated with a ham radio band string (e.g. "20m", "40M").
    static func color(for band: String) -> Color {
        bandColorMap[band.lowercased()] ?? .gray
    }

    // MARK: Private

    private static let bandColorMap: [String: Color] = [
        "160m": .indigo,
        "80m": .purple,
        "60m": Color(red: 0.3, green: 0.3, blue: 0.7),
        "40m": .blue,
        "30m": .teal,
        "20m": .green,
        "17m": .mint,
        "15m": .orange,
        "12m": .pink,
        "10m": .red,
        "6m": .yellow,
        "2m": Color(red: 0.8, green: 0.4, blue: 0.8),
        "70cm": .brown,
    ]
}
