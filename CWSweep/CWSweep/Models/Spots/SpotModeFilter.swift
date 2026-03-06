import CarrierWaveCore
import Foundation

/// Filter for spot mode families (CW, Phone, Digital)
enum SpotModeFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case cw
    case phone
    case digital

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .all: "All"
        case .cw: "CW"
        case .phone: "Phone"
        case .digital: "Digital"
        }
    }

    /// Check if a mode string matches this filter
    func matches(mode: String) -> Bool {
        switch self {
        case .all:
            true
        case .cw:
            ModeEquivalence.family(for: mode) == .cw
        case .phone:
            ModeEquivalence.family(for: mode) == .phone
        case .digital:
            ModeEquivalence.family(for: mode) == .digital
        }
    }
}
