import SwiftUI
import UniformTypeIdentifiers

// MARK: - LayoutNodeEditor

/// Pure functions for manipulating LayoutNode trees.
/// Extracted from LayoutEditorView to keep type body within lint limits.
enum LayoutNodeEditor {
    static func getNode(_ root: LayoutNode, at path: [Int]) -> LayoutNode? {
        var current = root
        for index in path {
            guard case let .split(splitNode) = current else {
                return nil
            }
            current = index == 0 ? splitNode.first : splitNode.second
        }
        return current
    }

    static func setNode(_ root: inout LayoutNode, at path: [Int], to newNode: LayoutNode) {
        if path.isEmpty {
            root = newNode
            return
        }
        guard case var .split(splitNode) = root else {
            return
        }
        let remaining = Array(path.dropFirst())
        if path[0] == 0 {
            setNode(&splitNode.first, at: remaining, to: newNode)
        } else {
            setNode(&splitNode.second, at: remaining, to: newNode)
        }
        root = .split(splitNode)
    }

    static func splitPanel(
        root: inout LayoutNode,
        at path: [Int],
        direction: SplitDirection
    ) {
        guard let currentNode = getNode(root, at: path),
              case let .panel(currentPanel) = currentNode
        else {
            return
        }
        let newPanel: PanelIdentifier = currentPanel == .spotList ? .qsoLog : .spotList
        let split = SplitNode(
            direction: direction,
            first: .panel(currentPanel),
            second: .panel(newPanel)
        )
        setNode(&root, at: path, to: .split(split))
    }

    static func removeSplit(root: inout LayoutNode, at path: [Int]) {
        guard !path.isEmpty else {
            return
        }
        let parentPath = Array(path.dropLast())
        let childIndex = path.last!
        guard let parentNode = getNode(root, at: parentPath),
              case let .split(splitNode) = parentNode
        else {
            return
        }
        let sibling = childIndex == 0 ? splitNode.second : splitNode.first
        setNode(&root, at: parentPath, to: sibling)
    }

    static func swapChildren(root: inout LayoutNode, at path: [Int]) {
        guard let node = getNode(root, at: path),
              case var .split(splitNode) = node
        else {
            return
        }
        let temp = splitNode.first
        splitNode.first = splitNode.second
        splitNode.second = temp
        setNode(&root, at: path, to: .split(splitNode))
    }

    static func toggleDirection(root: inout LayoutNode, at path: [Int]) {
        guard let node = getNode(root, at: path),
              case var .split(splitNode) = node
        else {
            return
        }
        splitNode.direction = splitNode.direction == .horizontal
            ? .vertical : .horizontal
        setNode(&root, at: path, to: .split(splitNode))
    }

    static func setRatio(root: inout LayoutNode, at path: [Int], ratio: Double) {
        guard let node = getNode(root, at: path),
              case var .split(splitNode) = node
        else {
            return
        }
        splitNode.ratio = min(max(ratio, 0.15), 0.85)
        setNode(&root, at: path, to: .split(splitNode))
    }

    /// Swap the panels at two different leaf paths.
    static func swapPanels(root: inout LayoutNode, pathA: [Int], pathB: [Int]) {
        guard let nodeA = getNode(root, at: pathA),
              let nodeB = getNode(root, at: pathB),
              case .panel = nodeA,
              case .panel = nodeB
        else {
            return
        }
        setNode(&root, at: pathA, to: nodeB)
        setNode(&root, at: pathB, to: nodeA)
    }
}

// MARK: - LayoutDocument

/// FileDocument wrapper for JSON export/import.
struct LayoutDocument: FileDocument {
    // MARK: Lifecycle

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    // MARK: Internal

    static var readableContentTypes: [UTType] {
        [.json]
    }

    let data: Data

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
