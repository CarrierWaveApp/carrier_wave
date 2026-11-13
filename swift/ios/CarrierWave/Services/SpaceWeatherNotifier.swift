// Space Weather Notifier
//
// Fires toast and local notifications for new space weather events.
// Uses per-event cooldown and severity threshold.

import CarrierWaveCore
import Foundation
import UserNotifications

// MARK: - SpaceWeatherNotifier

@MainActor
@Observable
final class SpaceWeatherNotifier {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = SpaceWeatherNotifier()

    /// Notify about a new space weather event.
    /// Only notifies for moderate+ severity, respects cooldown per event ID.
    func notify(event: DONKIEvent) {
        let impact = event.radioImpact
        guard impact >= .moderate else {
            return
        }

        // Check per-event cooldown (6 hours)
        let eventID = event.eventID
        let now = Date()
        if let lastTime = lastNotified[eventID],
           now.timeIntervalSince(lastTime) < cooldown
        {
            return
        }

        // Check daily cap
        pruneOldNotifications(before: now)
        guard dailyCount < dailyCap else {
            return
        }

        lastNotified[eventID] = now
        dailyCount += 1

        // Fire toast
        ToastManager.shared.show(
            .spaceWeather(impact: impact),
            message: event.summary,
            duration: 5.0
        )

        // Fire local notification
        sendLocalNotification(event: event)
    }

    // MARK: Private

    /// Cooldown per event ID: 6 hours
    private let cooldown: TimeInterval = 21_600

    /// Daily notification cap
    private let dailyCap = 10

    private var lastNotified: [String: Date] = [:]
    private var dailyCount = 0
    private var lastCountReset: Date?

    private func pruneOldNotifications(before now: Date) {
        // Reset daily count at midnight
        let calendar = Calendar.current
        if let lastReset = lastCountReset,
           !calendar.isDate(lastReset, inSameDayAs: now)
        {
            dailyCount = 0
        }
        lastCountReset = now
    }

    private func sendLocalNotification(event: DONKIEvent) {
        let content = UNMutableNotificationContent()
        content.title = "\(event.typeName) — \(event.radioImpact.label)"
        content.body = event.summary
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "spaceWeather-\(event.eventID)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
