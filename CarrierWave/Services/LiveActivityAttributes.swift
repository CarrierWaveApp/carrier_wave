import ActivityKit
import Foundation

// MARK: - LoggingSessionAttributes

/// ActivityKit attributes for the logging session Live Activity.
/// Static attributes are set once at session start; ContentState updates per event.
struct LoggingSessionAttributes: ActivityAttributes {
    /// Dynamic state updated as QSOs are logged, frequency/mode changes, etc.
    struct ContentState: Codable, Hashable {
        var qsoCount: Int
        var frequency: String?
        var band: String?
        var mode: String
        var parkReference: String?
        var lastCallsign: String?
        var isPaused: Bool
        var updatedAt: Date

        /// Rove: current stop park ref (nil if not a rove)
        var currentStopPark: String?
        /// Rove: 1-based index of current stop
        var stopNumber: Int?
        /// Rove: total number of stops so far
        var totalStops: Int?
        /// Rove: QSOs at current stop
        var currentStopQSOs: Int?
    }

    /// Set once at session start
    var myCallsign: String
    var activationType: String
    var startedAt: Date
}
