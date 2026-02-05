import Foundation

// MARK: - DetectedCallsign

/// A callsign detected in the transcript with context
public struct DetectedCallsign: Identifiable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(), callsign: String, context: CallsignContext, timestamp: Date = Date()
    ) {
        self.id = id
        self.callsign = callsign
        self.context = context
        self.timestamp = timestamp
    }

    // MARK: Public

    /// Context in which the callsign was detected
    public enum CallsignContext: Equatable, Sendable {
        case cqCall // Station calling CQ
        case deIdentifier // Station identifying with DE
        case response // Station responding
        case unknown // Callsign without clear context
    }

    public let id: UUID
    public let callsign: String
    public let context: CallsignContext
    public let timestamp: Date
}
