// MARK: - SpotSourceFilter

enum SpotSourceFilter: String, CaseIterable, Identifiable {
    case all
    case pota
    case rbn
    case sota
    case wwff
    case dxSummit
    case dxHeat
    case dxWatch
    case cluster

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .all: "All"
        case .pota: "POTA"
        case .rbn: "RBN"
        case .sota: "SOTA"
        case .wwff: "WWFF"
        case .dxSummit: "DXS"
        case .dxHeat: "DXH"
        case .dxWatch: "DXW"
        case .cluster: "Cluster"
        }
    }
}
