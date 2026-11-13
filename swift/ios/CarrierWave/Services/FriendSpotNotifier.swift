// Friend Spot Notifier
//
// Deduped toast + local notification when friends appear in spots.
// Uses a 10-minute cooldown per callsign to avoid spamming.

import CarrierWaveData
import Foundation
import UserNotifications

// MARK: - FriendSpotNotifier

@MainActor
@Observable
final class FriendSpotNotifier {
    // MARK: Internal

    /// Update the set of friend callsigns to watch for
    func updateFriends(_ callsigns: Set<String>) {
        friendCallsigns = callsigns
    }

    /// Check a batch of enriched spots for friend matches
    func checkSpots(_ spots: [EnrichedSpot]) {
        guard isEnabled, !friendCallsigns.isEmpty else {
            return
        }

        let now = Date()
        for spot in spots {
            let callsign = spot.spot.callsign.uppercased()
            guard friendCallsigns.contains(callsign) else {
                continue
            }

            // Check cooldown
            if let lastTime = lastNotified[callsign],
               now.timeIntervalSince(lastTime) < cooldown
            {
                continue
            }

            lastNotified[callsign] = now

            // Fire toast
            ToastManager.shared.friendSpotted(
                callsign: callsign,
                frequency: spot.spot.frequencyKHz,
                mode: spot.spot.mode
            )

            // Fire local notification
            sendLocalNotification(
                callsign: callsign,
                frequency: spot.spot.frequencyKHz,
                mode: spot.spot.mode,
                park: spot.spot.parkRef
            )
        }
    }

    // MARK: Private

    private var friendCallsigns: Set<String> = []
    private var lastNotified: [String: Date] = [:]
    private let cooldown: TimeInterval = 600 // 10 minutes

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "friendSpotNotificationsEnabled") as? Bool ?? true
    }

    private func sendLocalNotification(
        callsign: String,
        frequency: Double,
        mode: String,
        park: String?
    ) {
        let content = UNMutableNotificationContent()
        content.title = "\(callsign) is on the air!"

        var body = "\(String(format: "%.1f", frequency)) kHz \(mode)"
        if let park {
            body += " at \(park)"
        }
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "friendSpot-\(callsign)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
