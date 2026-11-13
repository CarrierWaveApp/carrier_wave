import SwiftUI

// MARK: - BandScopeColorMode

/// Color scheme modes for band scope spot markers.
/// Each mode uses a different visual axis to convey information at a glance.
enum BandScopeColorMode: String, CaseIterable, Identifiable, Codable {
    /// Contest: green=double mult, red=single mult, blue=new, gray=dupe
    case contest
    /// DXCC: red=needed entity, orange=new band slot, green=confirmed, gray=worked
    case dxcc
    /// Freshness: yellow→gray gradient based on spot age
    case freshness
    /// Source: color by SpotSource (RBN=blue, POTA=green, etc.)
    case source

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .contest: "Contest"
        case .dxcc: "DXCC"
        case .freshness: "Freshness"
        case .source: "Source"
        }
    }

    var icon: String {
        switch self {
        case .contest: "trophy"
        case .dxcc: "globe"
        case .freshness: "clock"
        case .source: "antenna.radiowaves.left.and.right"
        }
    }

    /// Default color mode for an operating role
    static func defaultMode(for role: OperatingRole) -> BandScopeColorMode {
        switch role {
        case .hunter: .source
        case .activator: .source
        }
    }
}

// MARK: - SpotColorScheme

/// Centralized spot color utilities to avoid duplicating color logic across views.
enum SpotColorScheme {
    /// Color representing a spot source type.
    static func sourceColor(_ source: SpotSource) -> Color {
        switch source {
        case .rbn: .blue
        case .pota: .green
        case .sota: .orange
        case .wwff: .teal
        case .dxSummit: .purple
        case .dxHeat: .red
        case .dxWatch: .indigo
        case .cluster: .yellow
        }
    }

    /// Color representing a DXCC needed status.
    static func neededColor(_ status: NeededStatus) -> Color {
        switch status {
        case .newEntity: Color(nsColor: .systemRed)
        case .newBandSlot: Color(nsColor: .systemOrange)
        case .workedNotConfirmed: .primary
        case .confirmed: Color(nsColor: .systemGreen)
        case .unknown: .primary
        }
    }

    /// Resolve the marker color for a spot based on the active color mode.
    static func markerColor(
        for spot: EnrichedSpot,
        mode: BandScopeColorMode,
        isWorkedToday: Bool
    ) -> Color {
        switch mode {
        case .contest:
            contestColor(for: spot, isWorkedToday: isWorkedToday)
        case .dxcc:
            neededColor(spot.neededStatus)
        case .freshness:
            freshnessColor(for: spot)
        case .source:
            sourceColor(spot.spot.source)
        }
    }

    /// Contest color scheme: mults > new > dupe
    static func contestColor(for spot: EnrichedSpot, isWorkedToday: Bool) -> Color {
        if isWorkedToday {
            return Color(nsColor: .systemGray)
        }
        switch spot.neededStatus {
        case .newEntity:
            // "Double mult" equivalent — new DXCC entity
            return Color(nsColor: .systemGreen)
        case .newBandSlot:
            // "Single mult" — new band slot
            return Color(nsColor: .systemRed)
        case .workedNotConfirmed,
             .confirmed:
            return Color(nsColor: .systemGray)
        case .unknown:
            // Not yet determined — treat as potentially new
            return Color(nsColor: .systemBlue)
        }
    }

    /// Freshness color: warm yellow for fresh, cool gray for stale
    static func freshnessColor(for spot: EnrichedSpot) -> Color {
        let ageMinutes = Date().timeIntervalSince(spot.spot.timestamp) / 60
        if ageMinutes < 3 {
            return Color(nsColor: .systemYellow)
        } else if ageMinutes < 10 {
            return Color(nsColor: .systemOrange)
        } else if ageMinutes < 20 {
            return .white
        } else {
            return Color(nsColor: .systemGray)
        }
    }
}
