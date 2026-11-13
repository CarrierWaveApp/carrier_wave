// MARK: - Navigation

extension VimActionExecutor {
    func executeNavigation(_ motion: VimMotion) -> String? {
        switch motion {
        case let .down(count):
            return navigateVertical(offset: count)
        case let .up(count):
            return navigateVertical(offset: -count)
        case .bandDown:
            return "Band ↓"
        case .bandUp:
            return "Band ↑"
        case .top:
            return navigateEdge(.top)
        case .bottom:
            return navigateEdge(.bottom)
        case .nextResult:
            return "Next"
        case .prevResult:
            return "Prev"
        case .cycleFocus:
            cyclePaneFocus()
            return nil
        case let .focusPane(pane):
            return focusPaneDirectly(pane)
        case let .focusPaneByIndex(index):
            return focusPaneByIndex(index)
        }
    }

    private func navigateVertical(offset: Int) -> String? {
        if selectionState.focusedPane == .qsoLog {
            navigateLog(offset: offset)
        } else {
            selectionState.vimSelectionOffset = offset
        }
        return nil
    }

    private func navigateEdge(_ edge: VimJumpEdge) -> String? {
        if selectionState.focusedPane == .qsoLog {
            selectionState.selectedQSOId = edge == .top
                ? selectionState.logDisplayOrder.first
                : selectionState.logDisplayOrder.last
        } else {
            selectionState.vimJumpToEdge = edge
        }
        return nil
    }

    private func focusPaneDirectly(_ pane: FocusedPane) -> String? {
        selectionState.focusedPane = pane
        return "Focus: \(pane.displayName)"
    }

    private func focusPaneByIndex(_ index: Int) -> String? {
        let panes = selectionState.availablePanes
        guard index >= 1, index <= panes.count else {
            return nil
        }
        let target = panes[index - 1]
        selectionState.focusedPane = target
        return "Focus: \(target.displayName)"
    }

    private func navigateLog(offset: Int) {
        let ids = selectionState.logDisplayOrder
        guard !ids.isEmpty else {
            return
        }
        let currentIndex: Int = if let selectedId = selectionState.selectedQSOId,
                                   let idx = ids.firstIndex(of: selectedId)
        {
            idx
        } else {
            offset > 0 ? -1 : ids.count
        }
        let newIndex = min(max(currentIndex + offset, 0), ids.count - 1)
        selectionState.selectedQSOId = ids[newIndex]
    }

    private func cyclePaneFocus() {
        let panes = selectionState.availablePanes.isEmpty
            ? PanelIdentifier.allCases
            : selectionState.availablePanes
        guard let currentIndex = panes.firstIndex(of: selectionState.focusedPane) else {
            if let first = panes.first {
                selectionState.focusedPane = first
            }
            return
        }
        let nextIndex = (currentIndex + 1) % panes.count
        selectionState.focusedPane = panes[nextIndex]
    }
}
