import Foundation

/// Source of a spot (model-level, not UI filter)
enum SpotSource: String, Sendable, CaseIterable {
    case rbn
    case pota
    case sota
    case wwff
    case cluster

    // MARK: Internal

    var displayName: String {
        switch self {
        case .rbn: "RBN"
        case .pota: "POTA"
        case .sota: "SOTA"
        case .wwff: "WWFF"
        case .cluster: "Cluster"
        }
    }

    /// Color name for spot source display
    var colorName: String {
        switch self {
        case .rbn: "blue"
        case .pota: "green"
        case .sota: "orange"
        case .wwff: "teal"
        case .cluster: "yellow"
        }
    }
}
