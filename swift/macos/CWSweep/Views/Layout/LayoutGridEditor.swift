import SwiftUI

// MARK: - LayoutGridEditor

/// Visual WYSIWYG editor for layout trees. Renders the tree as nested rectangles
/// with draggable dividers, right-click context menus, and drag-and-drop panel swapping.
struct LayoutGridEditor: View {
    // MARK: Internal

    @Binding var root: LayoutNode

    let onMutate: () -> Void

    var body: some View {
        nodeView(node: root, path: [])
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
    }

    // MARK: Private

    @State private var dragSource: [Int]?
    @State private var dropTarget: [Int]?

    private func splitView(
        splitNode: SplitNode,
        path: [Int]
    ) -> some View {
        let ratio = splitNode.ratio
        let coordSpace = splitCoordSpace(path)

        return GeometryReader { geo in
            let isHorizontal = splitNode.direction == .horizontal

            ZStack {
                if isHorizontal {
                    HStack(spacing: 0) {
                        nodeView(node: splitNode.first, path: path + [0])
                            .frame(width: geo.size.width * ratio)
                        nodeView(node: splitNode.second, path: path + [1])
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        nodeView(node: splitNode.first, path: path + [0])
                            .frame(height: geo.size.height * ratio)
                        nodeView(node: splitNode.second, path: path + [1])
                            .frame(maxHeight: .infinity)
                    }
                }

                // Draggable divider overlay
                dividerHandle(
                    splitPath: path,
                    direction: splitNode.direction,
                    ratio: ratio,
                    parentSize: geo.size,
                    coordSpace: coordSpace
                )
            }
            .coordinateSpace(name: coordSpace)
        }
    }

    private func splitCoordSpace(_ path: [Int]) -> String {
        "split-\(path.map(String.init).joined(separator: "-"))"
    }

    /// Returns AnyView to break recursive type lowering in the SIL generator.
    private func nodeView(node: LayoutNode, path: [Int]) -> AnyView {
        switch node {
        case let .split(splitNode):
            AnyView(splitView(splitNode: splitNode, path: path))
        case let .panel(panelId):
            AnyView(panelCell(panelId: panelId, path: path))
        }
    }
}

// MARK: - Panel Cell

extension LayoutGridEditor {
    private func panelCell(
        panelId: PanelIdentifier,
        path: [Int]
    ) -> some View {
        let isDropTarget = dropTarget == path && dragSource != path
        let isDragSource = dragSource == path

        return GeometryReader { geo in
            let isCompact = geo.size.width < 120 || geo.size.height < 60
            panelCellBody(
                panelId: panelId,
                isCompact: isCompact,
                isDragSource: isDragSource,
                isDropTarget: isDropTarget
            )
        }
        .contentShape(Rectangle())
        .contextMenu { panelContextMenu(path: path, panelId: panelId) }
        .onDrag {
            dragSource = path
            return NSItemProvider(object: pathString(path) as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleDrop(providers: providers, targetPath: path)
        }
    }

    private func panelCellBody(
        panelId: PanelIdentifier,
        isCompact: Bool,
        isDragSource: Bool,
        isDropTarget: Bool
    ) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(panelColor(panelId).opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isDropTarget
                            ? Color.accentColor
                            : panelColor(panelId).opacity(0.4),
                        lineWidth: isDropTarget ? 3 : 1
                    )
            )
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: panelId.icon)
                        .font(isCompact ? .caption : .title3)
                        .foregroundStyle(panelColor(panelId))
                    if !isCompact {
                        Text(panelId.displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .opacity(isDragSource ? 0.4 : 1.0)
            .padding(2)
    }

    private func panelColor(_ panel: PanelIdentifier) -> Color {
        switch panel {
        case .spotList: .blue
        case .qsoLog: .green
        case .qsoMap,
             .activationMap: .orange
        case .cluster: .purple
        case .dashboard: .cyan
        case .bandScope,
             .bandScopeSingle,
             .bandScopeHybrid,
             .bandScopeStacked,
             .bandScopeGrid: .indigo
        case .waterfall: .indigo
        case .radioControl: .red
        case .winKeyer: .yellow
        case .dxccTracking: .mint
        case .propagation: .pink
        case .spaceWeather: .teal
        case .spotDetail: .gray
        case .contestScore,
             .contestEntry,
             .contestBandBreakdown,
             .contestRecent: .brown
        case .jttyTerminal: .orange
        }
    }
}

// MARK: - Divider Handle

extension LayoutGridEditor {
    private func dividerHandle(
        splitPath: [Int],
        direction: SplitDirection,
        ratio: Double,
        parentSize: CGSize,
        coordSpace: String
    ) -> some View {
        let isHorizontal = direction == .horizontal
        let position = isHorizontal
            ? ratio * parentSize.width
            : ratio * parentSize.height

        return Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(
                width: isHorizontal ? 12 : nil,
                height: isHorizontal ? nil : 12
            )
            .overlay {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.secondary.opacity(0.5))
                    .frame(
                        width: isHorizontal ? 3 : 24,
                        height: isHorizontal ? 24 : 3
                    )
            }
            .position(
                x: isHorizontal ? position : parentSize.width / 2,
                y: isHorizontal ? parentSize.height / 2 : position
            )
            .onHover { hovering in
                if hovering {
                    if isHorizontal {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.resizeUpDown.push()
                    }
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(coordinateSpace: .named(coordSpace))
                    .onChanged { value in
                        let newRatio: Double = if isHorizontal {
                            value.location.x / parentSize.width
                        } else {
                            value.location.y / parentSize.height
                        }
                        let snapped = snapToGrid(newRatio)
                        LayoutNodeEditor.setRatio(
                            root: &root, at: splitPath, ratio: snapped
                        )
                        onMutate()
                    }
            )
            .contextMenu { splitContextMenu(path: splitPath) }
    }

    private func snapToGrid(_ ratio: Double) -> Double {
        let gridPoints = [0.2, 0.25, 1.0 / 3.0, 0.5, 2.0 / 3.0, 0.75, 0.8]
        let snapThreshold = 0.03
        for point in gridPoints where abs(ratio - point) < snapThreshold {
            return point
        }
        return ratio
    }
}

// MARK: - Context Menus

private extension LayoutGridEditor {
    @ViewBuilder
    func panelContextMenu(
        path: [Int],
        panelId: PanelIdentifier
    ) -> some View {
        Menu("Change Panel") {
            ForEach(PanelIdentifier.pickable) { panel in
                Button(panel.displayName, systemImage: panel.icon) {
                    LayoutNodeEditor.setNode(&root, at: path, to: .panel(panel))
                    onMutate()
                }
                .disabled(panel == panelId)
            }
        }
        Divider()
        Button("Split Horizontal", systemImage: "rectangle.split.2x1") {
            LayoutNodeEditor.splitPanel(root: &root, at: path, direction: .horizontal)
            onMutate()
        }
        Button("Split Vertical", systemImage: "rectangle.split.1x2") {
            LayoutNodeEditor.splitPanel(root: &root, at: path, direction: .vertical)
            onMutate()
        }
        if !path.isEmpty {
            Divider()
            Button("Remove", systemImage: "trash", role: .destructive) {
                LayoutNodeEditor.removeSplit(root: &root, at: path)
                onMutate()
            }
        }
    }

    @ViewBuilder
    func splitContextMenu(path: [Int]) -> some View {
        Button("Swap Children", systemImage: "arrow.left.arrow.right") {
            LayoutNodeEditor.swapChildren(root: &root, at: path)
            onMutate()
        }
        Button("Toggle Direction", systemImage: "rectangle.split.2x1") {
            LayoutNodeEditor.toggleDirection(root: &root, at: path)
            onMutate()
        }
        if !path.isEmpty {
            Divider()
            Button("Remove Split", systemImage: "trash", role: .destructive) {
                LayoutNodeEditor.removeSplit(root: &root, at: path)
                onMutate()
            }
        }
    }
}

// MARK: - Drag and Drop

extension LayoutGridEditor {
    private func handleDrop(
        providers: [NSItemProvider],
        targetPath: [Int]
    ) -> Bool {
        guard let provider = providers.first else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let pathStr = item as? String else {
                return
            }
            let sourcePath = Self.parsePath(pathStr)
            DispatchQueue.main.async {
                LayoutNodeEditor.swapPanels(
                    root: &root,
                    pathA: sourcePath,
                    pathB: targetPath
                )
                onMutate()
                dragSource = nil
                dropTarget = nil
            }
        }
        return true
    }

    private func pathString(_ path: [Int]) -> String {
        path.map(String.init).joined(separator: ".")
    }

    nonisolated static func parsePath(_ str: String) -> [Int] {
        guard !str.isEmpty else {
            return []
        }
        return str.split(separator: ".").compactMap { Int($0) }
    }
}
