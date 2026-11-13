import CarrierWaveData
import SwiftUI

// MARK: - VimSpotNavigationModifier

/// ViewModifier that bridges VimActionExecutor requests to SpotListView's Table selection.
///
/// Observes `SelectionState` vim bridge properties (set by VimActionExecutor) and
/// translates them into selection changes and tune-and-log actions on the spot table.
struct VimSpotNavigationModifier: ViewModifier {
    // MARK: Internal

    @Binding var selection: Set<EnrichedSpot.ID>

    var spots: [EnrichedSpot]
    var onTuneAndLog: (EnrichedSpot) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: spots) {
                selectionState.spotDisplayOrder = spots.map(\.id)
            }
            .onChange(of: selectionState.vimSelectionOffset) {
                guard selectionState.focusedPane == .spotList,
                      let offset = selectionState.vimSelectionOffset
                else {
                    return
                }
                selectionState.vimSelectionOffset = nil
                applySelectionOffset(offset)
            }
            .onChange(of: selectionState.vimJumpToEdge) {
                guard selectionState.focusedPane == .spotList,
                      let edge = selectionState.vimJumpToEdge
                else {
                    return
                }
                selectionState.vimJumpToEdge = nil
                applyJumpToEdge(edge)
            }
            .onChange(of: selectionState.vimTuneRequest) {
                guard selectionState.focusedPane == .spotList,
                      selectionState.vimTuneRequest
                else {
                    return
                }
                selectionState.vimTuneRequest = false
                tuneSelectedSpot()
            }
    }

    // MARK: Private

    @Environment(SelectionState.self) private var selectionState

    private func applySelectionOffset(_ offset: Int) {
        let ids = spots.map(\.id)
        guard !ids.isEmpty else {
            return
        }

        let currentIndex: Int = if let selectedId = selection.first,
                                   let idx = ids.firstIndex(of: selectedId)
        {
            idx
        } else {
            // No current selection — start from top for down, bottom for up
            offset > 0 ? -1 : ids.count
        }

        let newIndex = min(max(currentIndex + offset, 0), ids.count - 1)
        selection = [ids[newIndex]]
    }

    private func applyJumpToEdge(_ edge: VimJumpEdge) {
        let ids = spots.map(\.id)
        guard !ids.isEmpty else {
            return
        }

        switch edge {
        case .top:
            if let firstId = ids.first {
                selection = [firstId]
            }
        case .bottom:
            if let lastId = ids.last {
                selection = [lastId]
            }
        }
    }

    private func tuneSelectedSpot() {
        guard let selectedId = selection.first,
              let spot = spots.first(where: { $0.id == selectedId })
        else {
            return
        }
        onTuneAndLog(spot)
    }
}
