import SwiftUI

/// Standalone layout pane wrapper for SpotDetailInspector.
/// Reads the selected spot from SelectionState (shared environment).
struct SpotDetailPane: View {
    // MARK: Internal

    var body: some View {
        if let spot = selectionState.selectedSpot {
            SpotDetailInspector(spot: spot)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                Text("No Spot Selected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Private

    @Environment(SelectionState.self) private var selectionState
}
