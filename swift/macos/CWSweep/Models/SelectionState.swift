import CarrierWaveData
import Foundation

extension Notification.Name {
    static let focusEntryField = Notification.Name("focusEntryField")
}

// MARK: - FocusedPane

/// Alias for PanelIdentifier — identifies which pane holds keyboard focus in vim mode.
/// Pane numbering is dynamic: g1–gN maps to the layout's orderedPanels array.
typealias FocusedPane = PanelIdentifier

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

    /// Which pane currently holds keyboard focus in vim mode.
    var focusedPane: FocusedPane = .spotList

    /// Which panes are available in the current layout. Set by layout renderer.
    /// When empty, all PanelIdentifier cases are available (backward compat).
    var availablePanes: [FocusedPane] = []

    // MARK: - Vim Navigation Bridge

    /// Vim mode: spot IDs in display order, updated by SpotListView when filtered spots change.
    var spotDisplayOrder: [EnrichedSpot.ID] = []

    /// Vim mode: request to change selection by offset. Set by VimActionExecutor, consumed by SpotListView.
    var vimSelectionOffset: Int?

    /// Vim mode: request to jump to top/bottom. Set by VimActionExecutor, consumed by SpotListView.
    var vimJumpToEdge: VimJumpEdge?

    /// Vim mode: request to tune-and-log the current selection.
    var vimTuneRequest = false

    /// Vim mode: active search filter parsed from `/` search text. Nil when no search active.
    var vimFilterResult: VimFilterResult?

    /// Vim mode: QSO row IDs in display order (populated by QSOLogTableView).
    var logDisplayOrder: [UUID] = []

    /// Vim mode: request to dismiss current spot from view.
    var vimDismissSpot = false

    /// Vim mode: request to delete selected QSO from log.
    var vimDeleteQSO = false

    /// Vim mode: request to toggle inspector panel.
    var vimToggleInspector = false

    /// Vim mode: request to show a sidebar destination (`:spots`, `:log`, …).
    /// Set by VimActionExecutor, consumed by WorkspaceView.
    var vimNavigateTo: SidebarItem?

    /// Vim mode: request to switch operating role (`:role activator`).
    /// Set by VimActionExecutor, consumed by WorkspaceView.
    var vimSetRole: OperatingRole?

    /// Fire-and-forget: signal the log table to remove a QSO row by ID without full reload.
    var logRemovedQSOId: UUID?

    /// Fire-and-forget: signal the log table to prepend a new QSO row without full reload.
    var logInsertedQSORow: QSOTableRow?

    /// Fire-and-forget: signal the log table to update an existing row without full reload.
    var logUpdatedQSORow: QSOTableRow?

    // MARK: - Activator Edit Mode

    /// When true, vim `i` on log pane enters edit mode instead of opening inspector.
    var activatorEditMode = false

    /// Fire-and-forget: signal ParsedEntryView to enter edit mode for an existing QSO.
    var editingQSOId: UUID?

    /// Reconstructed entry text for the QSO being edited.
    var editingEntryText: String?

    // MARK: - Activation Map

    /// Grid square of the callsign currently being entered (from CallsignInfoCache lookup).
    /// Set by ParsedEntryView+CallsignLookup, read by ActivationMapPane.
    var entryCallsignGrid: String?

    /// Latest fully-parsed QuickEntry result for the current entry text.
    /// Source of truth for the remote CW keyer's macro expansion (CALL, RST, …).
    /// Set by ParsedEntryView, read by RemoteOpService.
    var parsedQuickEntry: QuickEntryResult?

    /// Best-known operator name for the entry callsign, sourced from the
    /// callsign-info lookup. Used to expand `{NAME}` in CW slots.
    var entryCallsignName: String?

    /// Best-known US state for the entry callsign, sourced from the
    /// callsign-info lookup (QRZ preferred, HamDB fallback). Used to expand
    /// `{HISSTATE}` in CW slots — typically populated for POTA exchanges.
    var entryCallsignState: String?

    /// Plain entry-text callsign fallback for when QuickEntryParser hasn't
    /// produced a structured result yet (e.g. user is still typing).
    var entryCallsign: String?

    /// True when the entry text field is non-empty.
    /// Set by ParsedEntryView, read by ActivationMapPane.
    var entryInProgress = false

    // MARK: - Park Cache

    /// Running cache of callsign → park reference from spots. Used to auto-fill theirParkReference.
    var spotParkCache: [String: String] = [:]
}

// MARK: - VimJumpEdge

enum VimJumpEdge {
    case top
    case bottom
}
