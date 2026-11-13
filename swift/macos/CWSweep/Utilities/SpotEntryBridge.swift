import Foundation

/// Bridges spot selection from the workspace window to the Add QSO popup window.
/// Since these are separate SwiftUI `Window` scenes, they don't share environment
/// objects — this singleton provides the cross-window communication channel.
@MainActor @Observable
final class SpotEntryBridge {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = SpotEntryBridge()

    /// Set by SpotListView/BandMapView when a spot is selected for logging.
    /// Consumed by QSOEntryPopupView to populate fields.
    var pendingSpot: EnrichedSpot?
}
