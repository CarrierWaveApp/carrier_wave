import CarrierWaveData
import UIKit
import UserNotifications

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    /// Temporary orientation lock a view can impose (satellite pointing
    /// mode locks portrait so twisting the boom-mounted phone for
    /// polarization doesn't rotate the UI). Nil restores the default
    /// per-idiom behavior.
    static var orientationLock: UIInterfaceOrientationMask?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Local-notification taps (satellite pass alerts). Remote (CKSync)
        // push stays on the dedicated remote-notification callbacks below.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _: UIApplication,
        supportedInterfaceOrientationsFor _: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if let lock = Self.orientationLock {
            return lock
        }
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        await CloudSyncService.shared.handleRemoteNotification(userInfo)
        return .newData
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken _: Data
    ) {
        // CKSyncEngine handles token registration internally
    }

    func applicationDidReceiveMemoryWarning(_: UIApplication) {
        SyncDebugLog.shared.warning("Memory warning received — clearing reference caches")
        Task { @MainActor in
            await POTAParksCache.shared.clearForMemoryPressure()
            await SOTASummitsCache.shared.clearForMemoryPressure()
            await WWFFReferencesCache.shared.clearForMemoryPressure()
            SCPService.shared.clearForMemoryPressure()
        }
    }
}

// MARK: UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Foreground presentation: satellite pass alerts show as banners (the
    /// pass is imminent either way); every other local notification keeps the
    /// historical no-delegate behavior (suppressed in foreground — those
    /// senders pair their notification with an in-app toast).
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        if identifier.hasPrefix(SatellitePassAlertScheduler.identifierPrefix) {
            return [.banner, .sound]
        }
        return []
    }

    /// Tap handling: a pass-alert tap re-posts the pass geometry app-wide so
    /// ContentView switches to the satellites tab, selects the bird, and
    /// starts the countdown Live Activity.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        guard request.identifier.hasPrefix(SatellitePassAlertScheduler.identifierPrefix) else {
            return
        }
        let userInfo = request.content.userInfo
        await MainActor.run {
            NotificationCenter.default.post(
                name: .didReceiveSatellitePassAlert, object: nil,
                userInfo: userInfo as? [String: Any]
            )
        }
    }
}
