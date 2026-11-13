import Foundation

// MARK: - RadioCommandDirection

/// Direction of a radio command, used by transport log callbacks and the
/// in-app command log.
public enum RadioCommandDirection: Sendable, Equatable {
    case tx // Sent to radio
    case rx // Received from radio
    case status // Connection lifecycle event
}
