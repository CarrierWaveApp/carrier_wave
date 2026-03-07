import CarrierWaveData
import Foundation

extension Notification.Name {
    static let focusEntryField = Notification.Name("focusEntryField")
}

// MARK: - SelectionState

/// Shared observable selection state for wiring QSO selection across the view hierarchy.
/// Injected via .environment() on WorkspaceView, written by QSOLogTableView, read by InspectorView.
@MainActor @Observable
final class SelectionState {
    var selectedQSOId: QSO.ID?

    /// Fire-and-forget: spot → entry field. Set by SpotListView, consumed by ParsedEntryView.
    var pendingSpotEntry: String?

    /// Currently selected spot for inspector display
    var selectedSpot: EnrichedSpot?

    /// Fire-and-forget: Cmd+L focus request. Set by WorkspaceView, consumed by ParsedEntryView.
    var requestEntryFocus = false
}
