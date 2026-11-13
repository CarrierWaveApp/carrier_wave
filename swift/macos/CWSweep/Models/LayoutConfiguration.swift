import Foundation

// MARK: - OperatingRole

/// Operating role presets
enum OperatingRole: String, CaseIterable, Identifiable, Codable {
    case hunter
    case activator

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .hunter: "Hunter"
        case .activator: "Activator"
        }
    }

    var icon: String {
        switch self {
        case .hunter: "binoculars"
        case .activator: "antenna.radiowaves.left.and.right"
        }
    }

    var keyboardShortcut: Int {
        switch self {
        case .hunter: 1
        case .activator: 2
        }
    }
}

// MARK: - SidebarItem

/// Items in the navigation sidebar
enum SidebarItem: String, CaseIterable, Identifiable {
    case logger
    case spots
    case map
    case cluster
    case satellites
    case qsoLog
    case dashboard
    case dxcc
    case radio
    case winkeyer
    case rotator
    case sync

    // MARK: Internal

    /// Dev hook, never persisted: `open -a "CW Sweep" --args -initialSidebarItem rotator`
    /// opens the workspace on that item so a panel can be checked without clicking.
    static var fromLaunchArguments: SidebarItem? {
        UserDefaults.standard.string(forKey: "initialSidebarItem").flatMap(SidebarItem.init(rawValue:))
    }

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .logger: "Sessions"
        case .spots: "Spots"
        case .map: "Map"
        case .cluster: "DX Cluster"
        case .satellites: "Satellites"
        case .qsoLog: "QSO Log"
        case .dashboard: "Dashboard"
        case .radio: "Radio"
        case .winkeyer: "WinKeyer"
        case .rotator: "Rotator"
        case .sync: "Sync"
        case .dxcc: "DXCC"
        }
    }

    var icon: String {
        switch self {
        case .logger: "square.and.pencil"
        case .spots: "dot.radiowaves.left.and.right"
        case .map: "map"
        case .cluster: "network"
        case .satellites: "dot.radiowaves.up.forward"
        case .qsoLog: "list.bullet.rectangle"
        case .dashboard: "chart.pie"
        case .radio: "antenna.radiowaves.left.and.right"
        case .winkeyer: "pianokeys"
        case .rotator: "rotate.3d"
        case .sync: "arrow.triangle.2.circlepath"
        case .dxcc: "flag.fill"
        }
    }

    /// Section grouping for sidebar
    var section: SidebarSection {
        switch self {
        case .logger,
             .spots,
             .map,
             .cluster,
             .satellites: .operating
        case .qsoLog,
             .dashboard,
             .dxcc: .data
        case .radio,
             .winkeyer,
             .rotator,
             .sync: .system
        }
    }
}

// MARK: - SidebarSection

enum SidebarSection: String, CaseIterable, Identifiable {
    case operating
    case data
    case system

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .operating: "Operating"
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
        }
    }
}
