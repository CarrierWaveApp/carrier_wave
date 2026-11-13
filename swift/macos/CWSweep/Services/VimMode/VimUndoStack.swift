import Foundation

// MARK: - VimUndoEntry

enum VimUndoEntry: Equatable {
    case tunedFrom(frequencyMHz: Double, mode: String)
    case dismissed(spotID: String)
}

// MARK: - VimUndoStack

@MainActor
final class VimUndoStack {
    // MARK: Internal

    var canUndo: Bool {
        !stack.isEmpty
    }

    func push(_ entry: VimUndoEntry) {
        stack.append(entry)
        if stack.count > maxEntries {
            stack.removeFirst()
        }
    }

    func pop() -> VimUndoEntry? {
        stack.popLast()
    }

    func clear() {
        stack.removeAll()
    }

    // MARK: Private

    private var stack: [VimUndoEntry] = []
    private let maxEntries = 50
}
