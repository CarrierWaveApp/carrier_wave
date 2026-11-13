// Needs Spot Notifier
//
// Fires toasts and local notifications when spots match operator needs.
// 10-minute cooldown per (callsign + need category) to avoid spam.
//
// Adaptive daily budget: tracks whether notified callsigns get logged as
// QSOs. When engagement is low the budget shrinks; when high it grows.

import CarrierWaveData
import Foundation
import UserNotifications

// MARK: - NeedsSpotNotifier

@MainActor
@Observable
final class NeedsSpotNotifier {
    // MARK: Lifecycle

    init() {
        loadPersistedState()
        observeQSOLogging()
    }

    deinit {
        if let qsoObserver {
            NotificationCenter.default.removeObserver(qsoObserver)
        }
    }

    // MARK: Internal

    /// Check a batch of enriched spots for need matches.
    func checkSpots(_ spots: [EnrichedSpot]) {
        guard isEnabled else {
            return
        }

        let now = Date()
        resetDailyCountIfNeeded(now: now)

        for spot in spots {
            guard spot.hasNeeds else {
                continue
            }

            // Stop once adaptive daily budget is reached
            guard dailySentCount < adaptiveDailyBudget else {
                break
            }

            // Find the highest-priority need that passes threshold
            let eligible = spot.matchedNeeds.filter {
                $0.priority >= minimumPriority
            }
            guard let topNeed = eligible.max(by: {
                $0.priority < $1.priority
            }) else {
                continue
            }

            // Check cooldown for this callsign + category combo
            let cooldownKey = "\(spot.spot.callsign)|\(topNeed.label)"
            if let lastTime = lastNotified[cooldownKey],
               now.timeIntervalSince(lastTime) < cooldown
            {
                continue
            }

            lastNotified[cooldownKey] = now
            dailySentCount += 1

            // Track this callsign for engagement measurement
            notifiedCallsigns[spot.spot.callsign.uppercased()] = now

            fireNotification(spot: spot, need: topNeed)
        }

        pruneStaleEntries(now: now)
    }

    // MARK: Private

    // Per-callsign cooldown
    private var lastNotified: [String: Date] = [:]
    private let cooldown: TimeInterval = 600

    // Daily tracking
    private var dailySentCount = 0
    private var dailyResetDate = Calendar.current.startOfDay(for: Date())

    /// Adaptive budget (persisted across launches)
    private var adaptiveDailyBudget = 25

    // Rolling engagement window (persisted across launches)
    private var windowSentCount = 0
    private var windowEngagedCount = 0

    /// Notified callsigns awaiting engagement (callsign → timestamp)
    private var notifiedCallsigns: [String: Date] = [:]

    /// Observer token — only written at init, read at deinit
    /// Observer token — only written at init, read at deinit
    @ObservationIgnored
    nonisolated(unsafe) private var qsoObserver: (any NSObjectProtocol)?
}

// MARK: - Engagement Tracking

private extension NeedsSpotNotifier {
    func handleQSOLogged(callsign: String) {
        let callUpper = callsign.uppercased()
        guard notifiedCallsigns.removeValue(forKey: callUpper) != nil else {
            return
        }
        windowEngagedCount += 1
        persistState()
    }
}

// MARK: - Adaptive Budget

private extension NeedsSpotNotifier {
    static let minimumBudget = 5
    static let maximumBudget = 50
    static let minimumSampleSize = 20
    static let lowEngagementRate = 0.05
    static let highEngagementRate = 0.20

    /// Recompute the daily budget from rolling engagement rate.
    func recomputeBudget() {
        guard windowSentCount >= Self.minimumSampleSize else {
            return
        }

        let rate = Double(windowEngagedCount) / Double(windowSentCount)

        if rate < Self.lowEngagementRate {
            // User rarely acts on notifications — send fewer
            adaptiveDailyBudget = max(
                Self.minimumBudget, adaptiveDailyBudget * 3 / 4
            )
        } else if rate > Self.highEngagementRate {
            // User frequently acts — allow more
            adaptiveDailyBudget = min(
                Self.maximumBudget, adaptiveDailyBudget * 5 / 4
            )
        }

        persistState()
    }
}

// MARK: - Daily Reset & Pruning

private extension NeedsSpotNotifier {
    func resetDailyCountIfNeeded(now: Date) {
        let todayStart = Calendar.current.startOfDay(for: now)
        guard todayStart > dailyResetDate else {
            return
        }

        // Roll the day's sent count into the window total
        windowSentCount += dailySentCount

        // Exponential decay (~90% per day) so the window naturally
        // forgets old data over roughly 7 days.
        windowSentCount = windowSentCount * 9 / 10
        windowEngagedCount = windowEngagedCount * 9 / 10

        dailyResetDate = todayStart
        dailySentCount = 0

        recomputeBudget()
    }

    func pruneStaleEntries(now: Date) {
        // Prune cooldown entries older than 20 minutes
        let cooldownCutoff = now.addingTimeInterval(-1_200)
        lastNotified = lastNotified.filter { $0.value > cooldownCutoff }

        // Prune notified callsigns older than 7 days
        let engagementCutoff = now.addingTimeInterval(-7 * 24 * 3_600)
        notifiedCallsigns = notifiedCallsigns.filter {
            $0.value > engagementCutoff
        }
    }
}

// MARK: - Persistence

private extension NeedsSpotNotifier {
    static let budgetKey = "needsSpotAdaptiveBudget"
    static let windowSentKey = "needsSpotWindowSent"
    static let windowEngagedKey = "needsSpotWindowEngaged"
    static let dailyResetKey = "needsSpotDailyReset"

    func loadPersistedState() {
        let defaults = UserDefaults.standard
        let stored = defaults.integer(forKey: Self.budgetKey)
        if stored > 0 {
            adaptiveDailyBudget = min(
                Self.maximumBudget, max(Self.minimumBudget, stored)
            )
        }
        windowSentCount = defaults.integer(forKey: Self.windowSentKey)
        windowEngagedCount = defaults.integer(forKey: Self.windowEngagedKey)
        if let date = defaults.object(forKey: Self.dailyResetKey) as? Date {
            dailyResetDate = date
        }
    }

    func persistState() {
        let defaults = UserDefaults.standard
        defaults.set(adaptiveDailyBudget, forKey: Self.budgetKey)
        defaults.set(windowSentCount, forKey: Self.windowSentKey)
        defaults.set(windowEngagedCount, forKey: Self.windowEngagedKey)
        defaults.set(dailyResetDate, forKey: Self.dailyResetKey)
    }
}

// MARK: - Observation

private extension NeedsSpotNotifier {
    func observeQSOLogging() {
        let token = NotificationCenter.default.addObserver(
            forName: .didLogQSO,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let callsign = notification.userInfo?["callsign"]
                as? String
            else {
                return
            }
            MainActor.assumeIsolated {
                self?.handleQSOLogged(callsign: callsign)
            }
        }
        qsoObserver = token
    }
}

// MARK: - Settings

private extension NeedsSpotNotifier {
    var isEnabled: Bool {
        UserDefaults.standard.object(
            forKey: "needsSpotNotificationsEnabled"
        ) as? Bool ?? true
    }

    var minimumPriority: NeedPriority {
        let raw = UserDefaults.standard.integer(
            forKey: "needsSpotMinPriority"
        )
        return NeedPriority(rawValue: raw) ?? .high
    }
}

// MARK: - Local Notification

private extension NeedsSpotNotifier {
    func fireNotification(spot: EnrichedSpot, need: MatchedNeed) {
        // Toast
        ToastManager.shared.show(Toast(
            type: .info,
            message: "\(need.label): \(spot.spot.callsign) on "
                + "\(FrequencyFormatter.format(spot.spot.frequencyMHz)) "
                + spot.spot.mode,
            duration: 5.0
        ))

        // Local notification
        let content = UNMutableNotificationContent()
        content.title = need.label
        let freq = FrequencyFormatter.format(spot.spot.frequencyMHz)
        content.body = "\(spot.spot.callsign) \(freq) kHz \(spot.spot.mode)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "needSpot-\(spot.spot.callsign)-\(need.label)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
