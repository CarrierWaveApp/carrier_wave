import Foundation

/// Source of a spot (model-level, not UI filter)
enum SpotSource: String, CaseIterable {
    case rbn
    case pota
    case sota
    case wwff
    case dxSummit
    case dxHeat
    case dxWatch
    case cluster

    // MARK: Internal

    var displayName: String {
        switch self {
        case .rbn: "RBN"
        case .pota: "POTA"
        case .sota: "SOTA"
        case .wwff: "WWFF"
        case .dxSummit: "DX Summit"
        case .dxHeat: "DXHeat"
        case .dxWatch: "DXWatch"
        case .cluster: "Cluster"
        }
    }

    var shortName: String {
        switch self {
        case .rbn: "RBN"
        case .pota: "POTA"
        case .sota: "SOTA"
        case .wwff: "WWFF"
        case .dxSummit: "DXSum"
        case .dxHeat: "DXHt"
        case .dxWatch: "DXW"
        case .cluster: "Clstr"
        }
    }

    /// Color name for spot source display
    var colorName: String {
        switch self {
        case .rbn: "blue"
        case .pota: "green"
        case .sota: "orange"
        case .wwff: "teal"
        case .dxSummit: "purple"
        case .dxHeat: "red"
        case .dxWatch: "indigo"
        case .cluster: "yellow"
        }
    }
}
