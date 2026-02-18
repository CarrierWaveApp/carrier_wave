import ActivityKit
import Foundation
import os

// MARK: - LiveActivityService

/// Manages the Live Activity lifecycle for logging sessions.
/// Uses local updates only (no push notifications).
@MainActor
final class LiveActivityService {
    // MARK: Internal

    /// Start a new Live Activity for the given session attributes and initial state.
    func start(
        attributes: LoggingSessionAttributes,
        state: LoggingSessionAttributes.ContentState
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities not enabled, skipping start")
            return
        }

        // End any stale activities first
        cleanupStale()

        let content = ActivityContent(state: state, staleDate: nil)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivity = activity
            logger.info("Started Live Activity: \(activity.id)")
        } catch {
            logger.error("Failed to start Live Activity: \(error)")
        }
    }

    /// Update the current Live Activity with new state.
    func update(state: LoggingSessionAttributes.ContentState) {
        guard let activity = currentActivity else {
            return
        }

        let content = ActivityContent(state: state, staleDate: nil)
        Task {
            await activity.update(content)
        }
    }

    /// End the current Live Activity with optional final state.
    func end(state: LoggingSessionAttributes.ContentState? = nil) {
        guard let activity = currentActivity else {
            return
        }

        let finalContent = state.map { ActivityContent(state: $0, staleDate: nil) }
        Task {
            await activity.end(finalContent, dismissalPolicy: .immediate)
            logger.info("Ended Live Activity: \(activity.id)")
        }
        currentActivity = nil
    }

    /// Reconnect to an existing Live Activity after app relaunch.
    /// Finds any running activity and adopts it.
    /// Returns `true` if an existing activity was found.
    @discardableResult
    func reconnect() -> Bool {
        let activities = Activity<LoggingSessionAttributes>.activities
        if let existing = activities.first {
            currentActivity = existing
            logger.info("Reconnected to Live Activity: \(existing.id)")
            return true
        }
        return false
    }

    /// Clean up any stale/orphaned Live Activities from previous sessions.
    func cleanupStale() {
        let activities = Activity<LoggingSessionAttributes>.activities
        for activity in activities where activity.id != currentActivity?.id {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
                logger.info("Cleaned up stale Live Activity: \(activity.id)")
            }
        }
    }

    // MARK: Private

    private var currentActivity: Activity<LoggingSessionAttributes>?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jsvana.CarrierWave",
        category: "LiveActivity"
    )
}
