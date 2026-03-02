import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
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
}

// MARK: - CarrierWaveApp

@main
struct CarrierWaveApp: App {
    // MARK: Lifecycle

    init() {
        // One-time tab migration: unhide Sessions tab for existing users
        TabConfiguration.migrateLoggerToSessions()

        // Mirror existing credentials to shared iCloud Keychain group for QSO Ledger
        KeychainHelper.shared.migrateExistingToSharedGroup()

        // Set default cw-swl server URL if not yet configured
        if (UserDefaults.standard.string(forKey: "cwswlServerURL") ?? "").isEmpty {
            UserDefaults.standard.set("https://swl.carrierwave.app", forKey: "cwswlServerURL")
        }

        let schema = Schema([
            QSO.self,
            ServicePresence.self,
            UploadDestination.self,
            POTAUploadAttempt.self,
            ActivationMetadata.self,
            ChallengeSource.self,
            ChallengeDefinition.self,
            ChallengeParticipation.self,
            LeaderboardCache.self,
            Friendship.self,
            Club.self,
            ActivityItem.self,
            LoggingSession.self,
            WebSDRRecording.self,
            ActivityLog.self,
            CallsignNotesSource.self,
            DismissedSuggestion.self,
            SessionSpot.self,
            SolarSnapshot.self,
            WebSDRFavorite.self,
            CloudSyncMetadata.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        // Apply pending restore BEFORE creating ModelContainer
        restoredBackup = BackupService.applyPendingRestore(
            storeURL: modelConfiguration.url
        )

        do {
            sharedModelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    // MARK: Internal

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Restore info if a backup was just applied on this launch
    let restoredBackup: PendingRestore?

    var sharedModelContainer: ModelContainer

    var body: some Scene {
        WindowGroup {
            ContentView(
                tourState: tourState,
                restoredBackup: restoredBackup
            )
            .sunlightMode(isSunlightMode)
            .preferredColorScheme(colorScheme)
            .task {
                // Run one-time data repairs before sync starts
                DataRepairService.runPendingRepairs()

                // Start iCloud settings sync (register callbacks before start)
                let syncContainer = sharedModelContainer
                SettingsSyncService.shared.onPull {
                    CallsignNotesSourceSync.reconcileFromDefaults(
                        modelContext: syncContainer.mainContext
                    )
                }
                SettingsSyncService.shared.start()

                // Register for remote notifications (CKSyncEngine push)
                UIApplication.shared.registerForRemoteNotifications()

                // Yield so the first frame commits before heavy initialization
                await Task.yield()

                // Mirror existing callsign notes sources to UserDefaults
                // so they get pushed to iCloud on first sync
                CallsignNotesSourceSync.mirrorToDefaults(
                    modelContext: sharedModelContainer.mainContext
                )

                // Activate WatchConnectivity for Apple Watch companion
                PhoneSessionDelegate.shared.activate()

                // Yield between initialization blocks to avoid starving the main run loop.
                // Without these yields, all operations serialize on the main actor
                // with no opportunity for UI updates or deep link processing.
                await Task.yield()

                // Start hourly solar conditions polling
                SolarPollingService.shared.configure(container: sharedModelContainer)

                // Start contest calendar polling (6-hour interval)
                ContestPollingService.shared.configure()

                // Start iCloud QSO sync (CKSyncEngine — heavyweight init)
                CloudSyncService.shared.configure(container: sharedModelContainer)

                await Task.yield()

                // Seed QRQ Crew callsign notes source on first launch
                QRQCrewService.seedNotesSourceIfNeeded(
                    modelContext: sharedModelContainer.mainContext
                )

                // Load SCP callsign database (from disk, then check remote if stale)
                await SCPService.shared.loadAndRefresh()
                await SCPService.shared.loadUserCallsigns(container: sharedModelContainer)

                // Preload caches concurrently (loads from disk, refreshes in background)
                async let parksLoad: Void = POTAParksCache.shared.ensureLoaded()
                async let summitsLoad: Void = SOTASummitsCache.shared.ensureLoaded()
                async let wwffLoad: Void = WWFFReferencesCache.shared.ensureLoaded()
                // Fetch sources on main actor, then pass to cache actor
                let sources = NotesSourceInfo.fetchAll(
                    modelContext: sharedModelContainer.mainContext
                )
                async let notesLoad: Void = CallsignNotesCache.shared
                    .ensureLoaded(sources: sources)
                _ = await (parksLoad, summitsLoad, wwffLoad, notesLoad)
            }
            .task {
                // Launch backup runs off the main thread to avoid blocking UI
                guard UserDefaults.standard.object(
                    forKey: "autoBackupEnabled"
                ) as? Bool ?? true,
                    let storeURL = sharedModelContainer
                    .configurations.first?.url
                else {
                    return
                }

                let container = sharedModelContainer
                let count = await Task.detached {
                    BackupService.visibleQSOCount(in: container)
                }.value
                await BackupService.shared.snapshot(
                    trigger: .launch,
                    storeURL: storeURL,
                    qsoCount: count
                )
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await CloudSyncService.shared.fetchChangesFromCloud()
                    }
                }
            }
            .onOpenURL { url in
                handleURL(url)
            }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: Private

    @Environment(\.scenePhase) private var scenePhase
    @State private var tourState = TourState()
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    private var isSunlightMode: Bool {
        appearanceMode == "sunlight"
    }

    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        case "sunlight": .light // Sunlight mode forces light scheme
        default: nil
        }
    }

    private func handleURL(_ url: URL) {
        // Check if it's a challenge invite link
        if url.scheme == "carrierwave", url.host == "challenge" {
            handleChallengeURL(url)
            return
        }

        // Check if it's a friend invite link (carrierwave://invite/{token})
        if url.scheme == "carrierwave", url.host == "invite" {
            handleFriendInviteURL(url)
            return
        }

        // Check for HTTPS friend invite link (https://*.carrierwave.app/invite/{token})
        if let host = url.host, host.hasSuffix("carrierwave.app"),
           url.pathComponents.count >= 2, url.pathComponents[1] == "invite"
        {
            handleFriendInviteURL(url)
            return
        }

        // Check for widget deep links (carrierwave://activitylog, dashboard, logger)
        if url.scheme == "carrierwave",
           let host = url.host,
           ["activitylog", "dashboard", "logger"].contains(host)
        {
            NotificationCenter.default.post(
                name: .didReceiveWidgetDeepLink,
                object: nil,
                userInfo: ["target": host]
            )
            return
        }

        // Otherwise treat as ADIF file
        NotificationCenter.default.post(
            name: .didReceiveADIFFile,
            object: url
        )
    }

    private func handleFriendInviteURL(_ url: URL) {
        // Parse invite token from URL
        // Formats:
        // - carrierwave://invite/{token}
        // - https://*.carrierwave.app/invite/{token}
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        var token: String?

        if url.scheme == "carrierwave" {
            // carrierwave://invite/{token} - token is in host or first path component
            if let host = url.host, host != "invite" {
                token = host
            } else if let first = pathComponents.first {
                token = first
            }
        } else {
            // https://*.carrierwave.app/invite/{token}
            if let inviteIndex = pathComponents.firstIndex(of: "invite"),
               inviteIndex + 1 < pathComponents.count
            {
                token = pathComponents[inviteIndex + 1]
            }
        }

        guard let inviteToken = token, !inviteToken.isEmpty else {
            return
        }

        NotificationCenter.default.post(
            name: .didReceiveFriendInvite,
            object: nil,
            userInfo: ["token": inviteToken]
        )
    }

    private func handleChallengeURL(_ url: URL) {
        // Parse carrierwave://challenge/join?source=...&id=...&token=...
        guard url.path == "/join" else {
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        var params: [String: String] = [:]
        for item in queryItems {
            if let value = item.value {
                params[item.name] = value
            }
        }

        guard let source = params["source"],
              let idString = params["id"],
              let challengeId = UUID(uuidString: idString)
        else {
            return
        }

        let token = params["token"]

        NotificationCenter.default.post(
            name: .didReceiveChallengeInvite,
            object: nil,
            userInfo: [
                "source": source,
                "challengeId": challengeId,
                "token": token as Any,
            ]
        )
    }
}

extension Notification.Name {
    static let didReceiveADIFFile = Notification.Name("didReceiveADIFFile")
    static let didReceiveChallengeInvite = Notification.Name(
        "didReceiveChallengeInvite"
    )
    static let didReceiveFriendInvite = Notification.Name(
        "didReceiveFriendInvite"
    )
    static let didReceiveWidgetDeepLink = Notification.Name(
        "didReceiveWidgetDeepLink"
    )
    nonisolated static let didSyncQSOs = Notification.Name("didSyncQSOs")
    static let didDetectActivities = Notification.Name("didDetectActivities")
    static let didClearQSOs = Notification.Name("didClearQSOs")
    static let didReceiveWatchStartSession = Notification.Name(
        "didReceiveWatchStartSession"
    )
    static let didRestoreFromBackup = Notification.Name(
        "didRestoreFromBackup"
    )
}
