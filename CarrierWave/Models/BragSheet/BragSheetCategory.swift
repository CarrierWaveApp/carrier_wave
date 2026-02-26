import Foundation

// MARK: - BragSheetCategory

/// Categories that organize brag sheet stats in the picker and on the card.
nonisolated enum BragSheetCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case totals
    case speedAndRate
    case distance
    case powerAndEfficiency
    case geographicReach
    case volumeRecords
    case streaks
    case pota
    case cw
    case signalQuality
    case funAndUnique

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .totals: "Totals"
        case .speedAndRate: "Speed & Rate"
        case .distance: "Distance"
        case .powerAndEfficiency: "Power & Efficiency"
        case .geographicReach: "Geographic Reach"
        case .volumeRecords: "Volume Records"
        case .streaks: "Streaks"
        case .pota: "POTA"
        case .cw: "CW"
        case .signalQuality: "Signal Quality"
        case .funAndUnique: "Fun & Unique"
        }
    }

    var systemImage: String {
        switch self {
        case .totals: "number"
        case .speedAndRate: "gauge.with.needle"
        case .distance: "location.north.line"
        case .powerAndEfficiency: "bolt"
        case .geographicReach: "globe"
        case .volumeRecords: "trophy"
        case .streaks: "flame"
        case .pota: "tree"
        case .cw: "waveform"
        case .signalQuality: "antenna.radiowaves.left.and.right"
        case .funAndUnique: "sparkles"
        }
    }

    /// Stats belonging to this category, in default display order.
    var stats: [BragSheetStatType] {
        BragSheetStatType.allCases.filter { $0.category == self }
    }
}
