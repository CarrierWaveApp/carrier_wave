import Foundation

// MARK: - OperatingRole

/// The five operating role presets
enum OperatingRole: String, CaseIterable, Identifiable, Codable {
    case contester
    case hunter
    case activator
    case dxer
    case casual

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .contester: "Contester"
        case .hunter: "Hunter"
        case .activator: "Activator"
        case .dxer: "DXer"
        case .casual: "Casual"
        }
    }

    var icon: String {
        switch self {
        case .contester: "trophy"
        case .hunter: "binoculars"
        case .activator: "antenna.radiowaves.left.and.right"
        case .dxer: "globe"
        case .casual: "radio"
        }
    }

    var keyboardShortcut: Int {
        switch self {
        case .contester: 1
        case .hunter: 2
        case .activator: 3
        case .dxer: 4
        case .casual: 5
        }
    }
}

// MARK: - SidebarItem

/// Items in the navigation sidebar
enum SidebarItem: String, CaseIterable, Identifiable {
    case logger
    case spots
    case map
    case bandMap
    case cluster
    case pota
    case ft8
    case cw
    case qsoLog
    case dashboard
    case multipliers
    case contestScore
    case sdr
    case recordings
    case radio
    case winkeyer
    case sync
    case sessions

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .logger: "Logger"
        case .spots: "Spots"
        case .map: "Map"
        case .bandMap: "Band Map"
        case .cluster: "DX Cluster"
        case .pota: "POTA"
        case .ft8: "FT8"
        case .cw: "CW"
        case .sdr: "SDR"
        case .recordings: "Recordings"
        case .qsoLog: "QSO Log"
        case .dashboard: "Dashboard"
        case .multipliers: "Multipliers"
        case .contestScore: "Contest Score"
        case .radio: "Radio"
        case .winkeyer: "WinKeyer"
        case .sync: "Sync"
        case .sessions: "Sessions"
        }
    }

    var icon: String {
        switch self {
        case .logger: "square.and.pencil"
        case .spots: "dot.radiowaves.left.and.right"
        case .map: "map"
        case .bandMap: "chart.bar"
        case .cluster: "network"
        case .pota: "tree"
        case .ft8: "waveform"
        case .cw: "waveform.path"
        case .sdr: "antenna.radiowaves.left.and.right.circle"
        case .recordings: "recordingtape"
        case .qsoLog: "list.bullet.rectangle"
        case .dashboard: "chart.pie"
        case .multipliers: "tablecells"
        case .contestScore: "trophy"
        case .radio: "antenna.radiowaves.left.and.right"
        case .winkeyer: "pianokeys"
        case .sync: "arrow.triangle.2.circlepath"
        case .sessions: "clock.arrow.circlepath"
        }
    }

    /// Section grouping for sidebar
    var section: SidebarSection {
        switch self {
        case .logger,
             .spots,
             .map,
             .bandMap,
             .cluster,
             .sdr: .operating
        case .pota,
             .ft8,
             .cw: .modes
        case .qsoLog,
             .dashboard,
             .multipliers,
             .contestScore,
             .sessions,
             .recordings: .data
        case .radio,
             .winkeyer,
             .sync: .system
        }
    }
}

// MARK: - SidebarSection

enum SidebarSection: String, CaseIterable, Identifiable {
    case operating
    case modes
    case data
    case system

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .operating: "Operating"
        case .modes: "Modes"
        case .data: "Data"
        case .system: "System"
        }
    }

    var items: [SidebarItem] {
        SidebarItem.allCases.filter { $0.section == self }
    }
}

// MARK: - LayoutConfiguration

/// Serializable layout state for a role preset
struct LayoutConfiguration: Codable {
    var role: OperatingRole
    var visibleSidebarItem: SidebarItem.RawValue
    var showInspector: Bool
    var inspectorWidth: Double

    static func `default`(for role: OperatingRole) -> LayoutConfiguration {
        switch role {
        case .contester:
            LayoutConfiguration(
                role: role,
                visibleSidebarItem: SidebarItem.logger.rawValue,
                showInspector: false,
                inspectorWidth: 300
            )
        case .hunter:
            LayoutConfiguration(
                role: role,
                visibleSidebarItem: SidebarItem.spots.rawValue,
                showInspector: true,
                inspectorWidth: 300
            )
        case .activator:
            LayoutConfiguration(
                role: role,
                visibleSidebarItem: SidebarItem.logger.rawValue,
                showInspector: true,
                inspectorWidth: 300
            )
        case .dxer:
            LayoutConfiguration(
                role: role,
                visibleSidebarItem: SidebarItem.spots.rawValue,
                showInspector: true,
                inspectorWidth: 350
            )
        case .casual:
            LayoutConfiguration(
                role: role,
                visibleSidebarItem: SidebarItem.qsoLog.rawValue,
                showInspector: false,
                inspectorWidth: 300
            )
        }
    }
}
