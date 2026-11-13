import Foundation

// MARK: - SCULAN10DebugStats

/// Snapshot of per-channel packet counters for the live SCU-LAN10 transport.
/// Used by the radio pane's debug view to surface where the connection is
/// healthy vs. silent — see `SCULAN10DebugView` for the UI.
public struct SCULAN10DebugStats: Equatable {
    // MARK: Lifecycle

    public init(
        controlReceived: Int,
        catReceived: Int,
        scopeReceived: Int,
        audioReceived: Int,
        catSent: Int,
        catSendErrors: Int
    ) {
        self.controlReceived = controlReceived
        self.catReceived = catReceived
        self.scopeReceived = scopeReceived
        self.audioReceived = audioReceived
        self.catSent = catSent
        self.catSendErrors = catSendErrors
    }

    // MARK: Public

    public static let empty = SCULAN10DebugStats(
        controlReceived: 0,
        catReceived: 0,
        scopeReceived: 0,
        audioReceived: 0,
        catSent: 0,
        catSendErrors: 0
    )

    public var controlReceived: Int
    public var catReceived: Int
    public var scopeReceived: Int
    public var audioReceived: Int
    public var catSent: Int
    public var catSendErrors: Int
}
