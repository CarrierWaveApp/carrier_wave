import SwiftUI

// MARK: - TabSwitchNotificationModifier

/// Extracts notification-driven tab switching from ContentView body
/// to reduce type-checker complexity.
struct TabSwitchNotificationModifier: ViewModifier {
    @Binding var selectedTab: AppTab?
    @Binding var pendingSpotlightQSOID: UUID?
    @Binding var pendingSpotlightSessionID: UUID?

    func body(content: Content) -> some View {
        content
            .modifier(DeepLinkNotifications(selectedTab: $selectedTab))
            .modifier(SessionNotifications(selectedTab: $selectedTab))
            .modifier(QSYNotifications(selectedTab: $selectedTab))
            .modifier(SpotlightNotifications(
                selectedTab: $selectedTab,
                pendingSpotlightQSOID: $pendingSpotlightQSOID,
                pendingSpotlightSessionID: $pendingSpotlightSessionID
            ))
    }
}

// MARK: - DeepLinkNotifications

private struct DeepLinkNotifications: ViewModifier {
    // MARK: Internal

    @Binding var selectedTab: AppTab?

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(for: .didReceiveWidgetDeepLink)
            ) { notification in
                handleWidgetDeepLink(notification)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .didReceiveSatellitePassAlert)
            ) { _ in
                // Pass-alert tap: land on the satellites tab; the root view
                // consumes the same notification to select the bird.
                selectedTab = .satellites
            }
    }

    // MARK: Private

    private func handleWidgetDeepLink(_ notification: Notification) {
        guard let target = notification.userInfo?["target"] as? String else {
            return
        }
        switch target {
        case "activitylog",
             "logger":
            selectedTab = .logger
        case "conditions",
             "dashboard":
            selectedTab = .dashboard
        case "hunt":
            selectedTab = .logger
            // Defer so the Sessions idle/intent view is mounted before
            // requesting the Hunter Log push.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .didRequestHunterLog, object: nil)
            }
        default:
            break
        }
    }
}

// MARK: - SessionNotifications

private struct SessionNotifications: ViewModifier {
    @Binding var selectedTab: AppTab?

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(for: .didReceiveWatchStartSession)
            ) { _ in
                selectedTab = .logger
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .didStartSessionExternally)
            ) { _ in
                selectedTab = .logger
            }
    }
}

// MARK: - SpotlightNotifications

/// Listens for `didOpenSpotlightQSO` / `didOpenSpotlightSession` notifications
/// posted by `CarrierWaveApp.handleSpotlightActivity` when the user taps a
/// CoreSpotlight search result. Stores the entity ID in a pending binding the
/// destination view consumes via `task(id:)`, then switches to the appropriate
/// tab so the destination view materializes.
private struct SpotlightNotifications: ViewModifier {
    @Binding var selectedTab: AppTab?
    @Binding var pendingSpotlightQSOID: UUID?
    @Binding var pendingSpotlightSessionID: UUID?

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(for: .didOpenSpotlightQSO)
            ) { notification in
                guard let id = notification.userInfo?["qsoID"] as? UUID else {
                    return
                }
                pendingSpotlightQSOID = id
                selectedTab = .logs
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .didOpenSpotlightSession)
            ) { notification in
                guard let id = notification.userInfo?["sessionID"] as? UUID else {
                    return
                }
                pendingSpotlightSessionID = id
                selectedTab = .logger
            }
    }
}

// MARK: - QSYNotifications

private struct QSYNotifications: ViewModifier {
    @Binding var selectedTab: AppTab?

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(for: .didReceiveQSYSpot)
            ) { notification in
                guard notification.userInfo?["callsign"] is String else {
                    return
                }
                selectedTab = .logger
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .didReceiveQSYTune)
            ) { _ in
                selectedTab = .logger
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .didReceiveQSYLookup)
            ) { _ in
                selectedTab = .logs
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .didReceiveQSYLog)
            ) { notification in
                guard notification.userInfo?["callsign"] is String else {
                    return
                }
                selectedTab = .logger
            }
    }
}
