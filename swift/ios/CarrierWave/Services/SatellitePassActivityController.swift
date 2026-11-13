import ActivityKit
import UIKit

// MARK: - SatellitePassActivityController

/// Lifecycle for the satellite pass-countdown Live Activity. Deliberately its
/// own small controller (not a generalization of `LiveActivityService`, which
/// is hard-typed to the logging-session activity and its update stream): this
/// activity is date-driven and never updates mid-pass.
///
/// ActivityKit can't start an activity from a background task without push,
/// so starts are local by design: the pass-notification tap (primary) and the
/// app-foreground imminence check (secondary), both funneling into `start`.
@MainActor
final class SatellitePassActivityController {
    // MARK: Internal

    static let shared = SatellitePassActivityController()

    /// Start the countdown for a pass (no-op if one for the same pass is
    /// already live; a different pass replaces the current activity).
    func start(attributes: SatellitePassAttributes) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }
        cleanupStale()
        if let current = currentActivity,
           current.attributes.noradID == attributes.noradID,
           current.attributes.aos == attributes.aos,
           current.activityState == .active
        {
            return
        }
        endCurrent()
        let content = ActivityContent(
            state: SatellitePassAttributes.ContentState(updatedAt: Date()),
            // System dims the activity after LOS even if the app never
            // returns to end it.
            staleDate: attributes.los
        )
        currentActivity = try? Activity.request(
            attributes: attributes, content: content, pushType: nil
        )
    }

    /// Start from a pass-alert notification's userInfo (the tap path).
    func start(fromUserInfo userInfo: [AnyHashable: Any]?) {
        guard let userInfo,
              let noradID = userInfo["noradID"] as? Int,
              let name = userInfo["satelliteName"] as? String,
              let aos = userInfo["aos"] as? TimeInterval,
              let los = userInfo["los"] as? TimeInterval
        else {
            return
        }
        let losDate = Date(timeIntervalSince1970: los)
        guard losDate > Date() else {
            return
        }
        start(attributes: SatellitePassAttributes(
            satelliteName: name,
            noradID: noradID,
            aos: Date(timeIntervalSince1970: aos),
            los: losDate,
            peakElevationDeg: userInfo["peakElevationDeg"] as? Double ?? 0,
            aosAzimuthDeg: userInfo["aosAzimuthDeg"] as? Double ?? 0,
            losAzimuthDeg: userInfo["losAzimuthDeg"] as? Double ?? 0,
            isMarginal: userInfo["isMarginal"] as? Bool ?? false
        ))
    }

    /// End the current activity when its pass is over (foreground check and
    /// the post-LOS quick-log entry point call this).
    func endIfPast(now: Date = Date()) {
        guard let current = currentActivity, current.attributes.los <= now else {
            return
        }
        endCurrent()
    }

    /// End every pass activity the system still holds (stale-reference
    /// recovery after relaunch).
    func cleanupStale(now: Date = Date()) {
        for activity in Activity<SatellitePassAttributes>.activities
            where activity.attributes.los <= now
        {
            let id = activity.id
            Task {
                await Self.liveActivity(id: id)?.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: Private

    private var currentActivity: Activity<SatellitePassAttributes>?

    private func endCurrent() {
        guard let current = currentActivity else {
            return
        }
        currentActivity = nil
        let id = current.id
        Task {
            await Self.liveActivity(id: id)?.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Fresh lookup of a running activity. `Activity` isn't `Sendable` and its
    /// `end` runs off the main actor, so a reference held in (or captured from)
    /// this MainActor controller can't be handed to it (Xcode 27+). A fresh
    /// lookup yields a disconnected value that can.
    nonisolated private static func liveActivity(id: String) -> Activity<SatellitePassAttributes>? {
        Activity<SatellitePassAttributes>.activities.first { $0.id == id }
    }
}
