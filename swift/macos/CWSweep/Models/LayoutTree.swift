import CoreGraphics
import Foundation

// MARK: - PanelIdentifier

/// Identifies a panel type that can be placed in a layout slot.
/// Raw values are used in JSON serialization — do not rename without migration.
enum PanelIdentifier: String, Codable, CaseIterable, Identifiable, Equatable {
    case spotList
    case qsoLog // always renders with ParsedEntryView docked above
    case qsoMap
    case cluster
    case dashboard
    case bandScope // legacy — renders ContestBandScopeView for compat with saved layouts
    case bandScopeSingle
    case bandScopeHybrid
    case bandScopeStacked
    case bandScopeGrid
    case waterfall
    case activationMap
    case radioControl
    case winKeyer
    case dxccTracking
    case propagation
    case spaceWeather
    case spotDetail
    case contestScore
    case contestEntry
    case contestBandBreakdown
    case contestRecent
    case jttyTerminal

    // MARK: Internal

    /// Cases the user can pick when adding/changing panels. Excludes
    /// the legacy `.bandScope` placeholder so the layout editor only
    /// surfaces the four dedicated band-scope variants.
    static var pickable: [PanelIdentifier] {
        allCases.filter { $0 != .bandScope }
    }

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .spotList: "Spots"
        case .qsoLog: "QSO Log"
        case .qsoMap: "Map"
        case .cluster: "DX Cluster"
        case .dashboard: "Dashboard"
        case .bandScope: "Band Scope"
        case .bandScopeSingle: "Band Scope: Single"
        case .bandScopeHybrid: "Band Scope: Rail"
        case .bandScopeStacked: "Band Scope: Stacked"
        case .bandScopeGrid: "Band Scope: Grid"
        case .waterfall: "Waterfall"
        case .activationMap: "Activation Map"
        case .radioControl: "Radio"
        case .winKeyer: "WinKeyer"
        case .dxccTracking: "DXCC"
        case .propagation: "Propagation"
        case .spaceWeather: "Space Weather"
        case .spotDetail: "Spot Detail"
        case .contestScore: "Contest Score"
        case .contestEntry: "Contest Entry"
        case .contestBandBreakdown: "Contest Bands"
        case .contestRecent: "Contest Recent QSOs"
        case .jttyTerminal: "JTTY"
        }
    }

    var icon: String {
        switch self {
        case .spotList: "dot.radiowaves.left.and.right"
        case .qsoLog: "list.bullet.rectangle"
        case .qsoMap: "map"
        case .cluster: "network"
        case .dashboard: "chart.pie"
        case .bandScope: "waveform"
        case .bandScopeSingle: "waveform"
        case .bandScopeHybrid: "rectangle.split.2x1"
        case .bandScopeStacked: "rectangle.split.1x2"
        case .bandScopeGrid: "rectangle.split.3x3"
        case .waterfall: "waveform.path.ecg.rectangle"
        case .activationMap: "mappin.and.ellipse"
        case .radioControl: "antenna.radiowaves.left.and.right"
        case .winKeyer: "pianokeys"
        case .dxccTracking: "flag.fill"
        case .propagation: "sun.max"
        case .spaceWeather: "sparkles"
        case .spotDetail: "info.circle"
        case .contestScore: "trophy"
        case .contestEntry: "keyboard"
        case .contestBandBreakdown: "chart.bar"
        case .contestRecent: "list.bullet.rectangle.portrait"
        case .jttyTerminal: "keyboard.badge.ellipsis"
        }
    }
}

// MARK: - SplitDirection

enum SplitDirection: String, Codable, Equatable {
    case horizontal // HSplitView — children side by side
    case vertical // VSplitView — children stacked
}

// MARK: - SplitNode

/// Internal node of the layout tree: a split with two children.
/// Manual Codable to match LayoutNode's manual conformance and avoid
/// synthesized conformance triggering SIL generator infinite recursion.
struct SplitNode: Equatable, Identifiable {
    // MARK: Lifecycle

    init(
        id: String = UUID().uuidString,
        direction: SplitDirection,
        first: LayoutNode,
        second: LayoutNode,
        ratio: Double = 0.5,
        firstFixedSize: CGFloat? = nil
    ) {
        self.id = id
        self.direction = direction
        self.first = first
        self.second = second
        self.ratio = ratio
        self.firstFixedSize = firstFixedSize
    }

    // MARK: Internal

    let id: String
    var direction: SplitDirection
    var first: LayoutNode
    var second: LayoutNode
    /// Proportion allocated to the first child (0.0–1.0). Used as an initial sizing hint
    /// when the split is resizable (i.e. `firstFixedSize == nil`).
    var ratio: Double
    /// When set, the first child is rendered at this exact height (vertical split) or
    /// width (horizontal split) inside a non-resizable container — VSplitView/HSplitView
    /// ignore frame constraints on their panes, so this is the only reliable way to
    /// pin a slim slot like a header strip. When nil, the split is resizable (VSplitView).
    var firstFixedSize: CGFloat?
}

// MARK: Codable

extension SplitNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case direction
        case first
        case second
        case ratio
        case firstFixedSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        direction = try container.decode(SplitDirection.self, forKey: .direction)
        first = try container.decode(LayoutNode.self, forKey: .first)
        second = try container.decode(LayoutNode.self, forKey: .second)
        ratio = try container.decode(Double.self, forKey: .ratio)
        firstFixedSize = try container.decodeIfPresent(CGFloat.self, forKey: .firstFixedSize)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(direction, forKey: .direction)
        try container.encode(first, forKey: .first)
        try container.encode(second, forKey: .second)
        try container.encode(ratio, forKey: .ratio)
        try container.encodeIfPresent(firstFixedSize, forKey: .firstFixedSize)
    }
}

// MARK: - LayoutNode

/// A node in the layout binary tree: either a split with two children or a leaf panel.
/// Manual Codable to avoid synthesized conformance on indirect enum which causes
/// infinite recursion in the SIL generator (computeLoweredRValueType).
indirect enum LayoutNode: Equatable, Identifiable {
    case split(SplitNode)
    case panel(PanelIdentifier)

    // MARK: Internal

    var id: String {
        switch self {
        case let .split(node): node.id
        case let .panel(panel): panel.rawValue
        }
    }

    /// Collect all panels via in-order traversal (left-to-right, top-to-bottom).
    var orderedPanels: [PanelIdentifier] {
        switch self {
        case let .split(node):
            node.first.orderedPanels + node.second.orderedPanels
        case let .panel(panel):
            [panel]
        }
    }
}

// MARK: Codable

extension LayoutNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case split
        case panel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "split":
            let node = try container.decode(SplitNode.self, forKey: .split)
            self = .split(node)
        case "panel":
            let panel = try container.decode(PanelIdentifier.self, forKey: .panel)
            self = .panel(panel)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown LayoutNode type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .split(node):
            try container.encode("split", forKey: .type)
            try container.encode(node, forKey: .split)
        case let .panel(panel):
            try container.encode("panel", forKey: .type)
            try container.encode(panel, forKey: .panel)
        }
    }
}
