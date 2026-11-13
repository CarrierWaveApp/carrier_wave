import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import SwiftUI
import UIKit
import UserNotifications

// MARK: - SatellitePassAlertScheduler

/// Schedules local notifications for upcoming passes of favorited birds.
///
/// Deliberately independent of `SatelliteTrackerModel` (which is `@State`-owned
/// by the satellites tab and dies with it): the scheduler runs the shared Rust
/// engine's whole pipeline headlessly — `refresh` (cache-through, 6 h TTL,
/// stale fallback offline) + `plan_alerts` (10°/20° gating, AOS−lead fire
/// times, 24 cap, minute-rounded identifiers, notification copy) — so the
/// background-refresh task and app-foreground hooks can reschedule without
/// the tab. The persisted observer location picks the QTH.
@MainActor
@Observable
final class SatellitePassAlertScheduler {
    // MARK: Lifecycle

    private init() {
        FavoriteSatellitesStore.shared.onChange = { [weak self] in
            guard let self else {
                return
            }
            // First-ever favorite: favoriting IS the alert intent — enable
            // alerts (only while the toggle has never been set explicitly)
            // and request notification permission.
            let defaults = UserDefaults.standard
            if !FavoriteSatellitesStore.shared.noradIDs.isEmpty,
               defaults.object(forKey: Self.enabledKey) == nil
            {
                defaults.set(true, forKey: Self.enabledKey)
                Task {
                    _ = await Self.ensureAuthorization()
                }
            }
            reschedule(trigger: "favorites-change")
        }
    }

    // MARK: Internal

    static let shared = SatellitePassAlertScheduler()

    /// Identifier prefix the engine stamps on planned alerts ("satpass-…");
    /// the foreground-presentation gate and reconciliation both key on it.
    nonisolated static let identifierPrefix = "satpass-"

    /// Settings keys (all plain defaults, mirroring the app's per-feature
    /// notification toggles).
    nonisolated static let enabledKey = "satellitePassAlertsEnabled"
    nonisolated static let leadMinutesKey = "satelliteAlertLeadMinutes"
    nonisolated static let includeMarginalKey = "satelliteAlertsIncludeMarginal"
    /// Last real observer fix ("lat,lon"), written by `SatellitesRootView`
    /// so headless reschedules prefer a GPS fix over grid fallbacks.
    nonisolated static let lastObserverKey = "satelliteLastObserverLatLon"

    /// How many pass alerts are currently pending (for the settings sheet).
    private(set) var pendingAlertCount = 0
    private(set) var lastRescheduleAt: Date?

    /// Observer for headless prediction: last persisted GPS fix, then the
    /// profile grid, then the logger default grid. Nil = no QTH; alerts are
    /// cancelled rather than scheduled from garbage.
    nonisolated static func resolveObserver() -> (lat: Double, lon: Double)? {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: lastObserverKey) {
            let parts = raw.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                return (lat: parts[0], lon: parts[1])
            }
        }
        for key in ["myGrid", "loggerDefaultGrid"] {
            if let grid = defaults.string(forKey: key),
               let coordinate = MaidenheadConverter.coordinate(from: grid)
            {
                return (lat: coordinate.latitude, lon: coordinate.longitude)
            }
        }
        return nil
    }

    /// Mirrors the contest-reminder authorization request — the only other
    /// scheduled notification in the app.
    static func ensureAuthorization() async -> Bool {
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    /// Recompute and reconcile pending pass alerts. Coalesced: a new trigger
    /// cancels an in-flight pass.
    func reschedule(trigger: String) {
        rescheduleTask?.cancel()
        rescheduleTask = Task { [weak self] in
            await self?.performReschedule(trigger: trigger)
        }
    }

    /// Awaitable variant for the background-refresh task, which must finish
    /// (or be expired) before completing its `BGAppRefreshTask`.
    func rescheduleNow(trigger: String) async {
        rescheduleTask?.cancel()
        rescheduleTask = nil
        await performReschedule(trigger: trigger)
    }

    // MARK: Private

    private var rescheduleTask: Task<Void, Never>?

    /// Calendar-triggered request (the contest-reminder pattern), with the
    /// pass geometry in userInfo for the tap → Live Activity path.
    nonisolated private static func request(
        for alert: FfiPlannedAlert
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.userInfo = [
            "noradID": Int(alert.noradId),
            "satelliteName": alert.satelliteName,
            "aos": TimeInterval(alert.aosEpoch),
            "los": TimeInterval(alert.losEpoch),
            "peakElevationDeg": alert.peakElevationDeg,
            "aosAzimuthDeg": alert.aosAzimuthDeg,
            "losAzimuthDeg": alert.losAzimuthDeg,
            "isMarginal": alert.isMarginal,
        ]
        let fireDate = Date(timeIntervalSince1970: TimeInterval(alert.fireEpoch))
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(
            identifier: alert.identifier, content: content, trigger: trigger
        )
    }

    private func performReschedule(trigger _: String) async {
        let defaults = UserDefaults.standard
        let favoriteIDs = FavoriteSatellitesStore.shared.noradIDs
        guard defaults.bool(forKey: Self.enabledKey), !favoriteIDs.isEmpty,
              let observer = Self.resolveObserver(),
              let api = try? await SatelliteEngine.api()
        else {
            await cancelAllPassAlerts()
            return
        }

        // Cache-through refresh (6 h TTL, stale fallback offline) loads the
        // catalog plan_alerts sweeps. On a total failure keep whatever is
        // already pending — stale alerts beat none.
        let now = Date()
        let leadMinutes = max(
            defaults.object(forKey: Self.leadMinutesKey).flatMap { $0 as? Int } ?? 15, 1
        )
        guard await (try? api.refresh(force: false)) != nil,
              let planned = try? await api.planAlerts(
                  observer: FfiObserver(latDeg: observer.lat, lonDeg: observer.lon),
                  favorites: favoriteIDs.map(UInt32.init),
                  includeMarginal: defaults.bool(forKey: Self.includeMarginalKey),
                  leadSecs: Int64(leadMinutes * 60),
                  nowEpoch: Int64(now.timeIntervalSince1970),
                  hours: 24
              ),
              !Task.isCancelled
        else {
            return
        }
        await apply(planned)
        lastRescheduleAt = now
    }

    /// Reconcile pending requests by identifier: keep unchanged passes (no
    /// churn from ±30 s TLE drift thanks to the minute-rounded identifier),
    /// remove stale ones, add new ones.
    private func apply(_ planned: [FfiPlannedAlert]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        let wanted = Set(planned.map(\.identifier))
        let stale = pending.filter { !wanted.contains($0) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        let existing = Set(pending)
        for alert in planned where !existing.contains(alert.identifier) {
            try? await center.add(Self.request(for: alert))
        }
        pendingAlertCount = planned.count
        syncLiveActivity(with: planned)
    }

    /// Foreground-side Live Activity upkeep (ActivityKit can't start from a
    /// BG task without push): end a finished pass, and auto-start the
    /// countdown when the nearest favorited pass is < 30 min out.
    private func syncLiveActivity(with planned: [FfiPlannedAlert]) {
        let controller = SatellitePassActivityController.shared
        controller.endIfPast()
        guard UIApplication.shared.applicationState == .active,
              let next = planned.first
        else {
            return
        }
        let aos = Date(timeIntervalSince1970: TimeInterval(next.aosEpoch))
        guard aos.timeIntervalSinceNow < 30 * 60 else {
            return
        }
        controller.start(attributes: SatellitePassAttributes(
            satelliteName: next.satelliteName,
            noradID: Int(next.noradId),
            aos: aos,
            los: Date(timeIntervalSince1970: TimeInterval(next.losEpoch)),
            peakElevationDeg: next.peakElevationDeg,
            aosAzimuthDeg: next.aosAzimuthDeg,
            losAzimuthDeg: next.losAzimuthDeg,
            isMarginal: next.isMarginal
        ))
    }

    private func cancelAllPassAlerts() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        if !pending.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pending)
        }
        pendingAlertCount = 0
    }
}
