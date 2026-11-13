import Foundation

// MARK: - CustomLayout

/// A named, serializable layout configuration.
/// Built-in presets are immutable; user layouts can be edited, exported, and imported.
struct CustomLayout: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var root: LayoutNode
    var isBuiltIn: Bool
    var createdAt: Date
    var modifiedAt: Date

    /// Panels in tree-traversal order, used for vim g1–gN focus numbering.
    var orderedPanels: [PanelIdentifier] {
        root.orderedPanels
    }

    /// Whether this layout contains activator-specific panels.
    var isActivatorStyle: Bool {
        orderedPanels.contains(.activationMap)
    }
}

// MARK: - Built-in Presets

extension CustomLayout {
    nonisolated(unsafe) static let hunterPreset = CustomLayout(
        id: "builtin-hunter",
        name: "Hunter",
        root: .split(SplitNode(
            id: "hunter-root",
            direction: .horizontal,
            first: .split(SplitNode(
                id: "hunter-left",
                direction: .vertical,
                first: .panel(.qsoLog),
                second: .panel(.spotList),
                ratio: 0.5
            )),
            second: .panel(.bandScope),
            ratio: 0.67
        )),
        isBuiltIn: true,
        createdAt: .distantPast,
        modifiedAt: .distantPast
    )

    nonisolated(unsafe) static let activatorPreset = CustomLayout(
        id: "builtin-activator",
        name: "Activator",
        root: .split(SplitNode(
            id: "activator-root",
            direction: .vertical,
            first: .panel(.qsoLog),
            second: .split(SplitNode(
                id: "activator-bottom",
                direction: .horizontal,
                first: .panel(.spotList),
                second: .panel(.activationMap),
                ratio: 0.5
            )),
            ratio: 0.5
        )),
        isBuiltIn: true,
        createdAt: .distantPast,
        modifiedAt: .distantPast
    )

    /// Default layout for contest sessions. Mirrors the columns shown in
    /// the previous bespoke `ContestOperatingView`: a left contest column
    /// (score / entry / band breakdown) and a right column with band scope
    /// over recent QSOs.
    nonisolated(unsafe) static let contesterPreset = CustomLayout(
        id: "builtin-contester",
        name: "Contester",
        root: .split(SplitNode(
            id: "contester-root",
            direction: .horizontal,
            first: .split(SplitNode(
                id: "contester-left",
                direction: .vertical,
                first: .panel(.contestScore),
                second: .split(SplitNode(
                    id: "contester-left-bottom",
                    direction: .vertical,
                    first: .panel(.contestEntry),
                    second: .panel(.contestBandBreakdown),
                    ratio: 0.65
                )),
                ratio: 0.0,
                firstFixedSize: 104
            )),
            second: .split(SplitNode(
                id: "contester-right",
                direction: .vertical,
                first: .panel(.bandScopeSingle),
                second: .panel(.contestRecent),
                ratio: 0.55
            )),
            ratio: 0.4
        )),
        isBuiltIn: true,
        createdAt: .distantPast,
        modifiedAt: .distantPast
    )

    nonisolated(unsafe) static let builtInPresets: [CustomLayout] = [
        hunterPreset,
        activatorPreset,
        contesterPreset,
    ]
}
