import CarrierWaveData
import Foundation

// MARK: - CallsignSuffix

/// Standard amateur radio callsign suffixes
enum CallsignSuffix: String, CaseIterable, Identifiable {
    case none = "None"
    case portable = "Portable"
    case mobile = "Mobile"
    case maritime = "Maritime Mobile"
    case aeronautical = "Aeronautical Mobile"
    case custom = "Custom"

    // MARK: Internal

    var id: String {
        rawValue
    }

    /// The suffix code used in the callsign
    var code: String {
        switch self {
        case .none: ""
        case .portable: "P"
        case .mobile: "M"
        case .maritime: "MM"
        case .aeronautical: "AM"
        case .custom: ""
        }
    }

    /// Description for display
    var description: String {
        switch self {
        case .none: "No suffix"
        case .portable: "/P – Portable station"
        case .mobile: "/M – Land vehicle"
        case .maritime: "/MM – Vessel"
        case .aeronautical: "/AM – Aircraft"
        case .custom: "Custom suffix"
        }
    }
}
