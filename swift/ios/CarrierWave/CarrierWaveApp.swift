import CarrierWaveCore
import CarrierWaveData
import CoreSpotlight
import MetricKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

// MARK: - CarrierWaveApp

@main
struct CarrierWaveApp: App {
    // MARK: Lifecycle

    init() {
        // Begin startup profiling if enabled (must be first)
        StartupProfiler.shared.beginIfEnabled()

        // Register MetricKit subscriber for performance monitoring
        PerfMetricsSubscriber.shared.register()

        // BGTaskScheduler launch handlers must be registered before the app
        // finishes launching (Phase 7.3 server-sync background refresh +
        // satellite pass-alert refresh).
        SyncBackgroundRefresh.register()
        ServerSyncHostHooks.install()
        SatellitePassBackgroundRefresh.register()

        let profiler = StartupProfiler.shared

        // One-time tab migration: unhide Sessions tab for existing users
        TabConfiguration.migrateLoggerToSessions()
        profiler.record("init.tabMigration")

        // Migrate legacy single-file QSO ledger to monthly directory
        QSOLedger.migrateIfNeeded()

        // Mirror existing credentials to shared iCloud Keychain group for QSO Ledger
        KeychainHelper.shared.migrateExistingToSharedGroup()
        profiler.record("init.keychainMigration")

        // Set default cw-swl server URL if not yet configured
        if (UserDefaults.standard.string(forKey: "cwswlServerURL") ?? "").isEmpty {
            UserDefaults.standard.set("https://swl.carrierwave.app", forKey: "cwswlServerURL")
        }

        let schema = Schema(AppSchema.models)
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        profiler.record("init.schemaBuilt")

        // Apply pending restore BEFORE creating ModelContainer
        restoredBackup = BackupService.applyPendingRestore(
            storeURL: modelConfiguration.url
        )
        profiler.record("init.restoreCheck")

        storeURL = modelConfiguration.url
        sharedModelContainer = ContainerSetup.createModelContainer(
            schema: schema, configuration: modelConfiguration
        )
        profiler.record("init.modelContainer")

        // Detect a pending init-failure record from this or a prior
        // launch. Its presence routes the WindowGroup into
        // `RecoveryModeView` instead of the normal app surface.
        pendingInitFailure = ContainerSetup.loadPendingFailureRecord()
    }

    // MARK: Internal

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State var qsoMirror: CwStoreMirror?

    /// Restore info if a backup was just applied on this launch
    let restoredBackup: PendingRestore?

    /// Persisted record of a `ModelContainer.init` failure from this
    /// launch (or any prior launch the user hasn't acknowledged yet).
    /// `nil` in the steady-state happy path.
    let pendingInitFailure: ContainerInitFailureRecord?

    /// On-disk URL of the SwiftData store. Captured in `init` so the
    /// recovery view can stage a restore or perform a confirmed reset
    /// against the right path even when `sharedModelContainer` is
    /// the in-memory fallback.
    let storeURL: URL

    var sharedModelContainer: ModelContainer

    var body: some Scene {
        WindowGroup {
            Group {
                if let pendingInitFailure {
                    // Container init failed — present recovery UI instead
                    // of ContentView. The in-memory fallback container is
                    // attached so any incidental SwiftData calls don't
                    // crash, but the user can't reach ContentView until
                    // they restore or explicitly reset.
                    RecoveryModeView(
                        failureRecord: pendingInitFailure,
                        storeURL: storeURL
                    )
                    .modelContainer(sharedModelContainer)
                } else {
                    normalRootView
                }
            }
            .whatsNewPresenter()
        }
    }

    // MARK: Private

    @State private var showEquipmentMigration = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var tourState = TourState()
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    /// Default `.on` (Phase 1c) — drives `applyQSOMirrorMode` at launch; must match
    /// `CwStoreQSOMode.current`'s default so the mirror/import actually spin up.
    @AppStorage(CwStoreQSOMode.appStorageKey) private var qsoMode = CwStoreQSOMode.on

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

    /// Steady-state app root. Extracted from the WindowGroup builder
    /// so the App struct's body length stays under the lint cap.
    private var normalRootView: some View {
        ContentView(
            tourState: tourState,
            restoredBackup: restoredBackup
        )
        .sunlightMode(isSunlightMode)
        .preferredColorScheme(colorScheme)
        .task {
            let profiler = StartupProfiler.shared

            // Run one-time data repairs before sync starts
            DataRepairService.runPendingRepairs()
            await DataRepairService.runAsyncRepairs(
                container: sharedModelContainer
            )

            // Start iCloud settings sync (register callbacks before start)
            let syncContainer = sharedModelContainer
            SettingsSyncService.shared.onPull {
                CallsignNotesSourceSync.reconcileFromDefaults(
                    modelContext: syncContainer.mainContext
                )
                // Migrate equipment to iCloud KVS (one-time)
                EquipmentStorage.migrateToiCloudKVS()
                // Recover equipment from session history if any lists were emptied by sync
                EquipmentStorage.recoverFromSessions(container: syncContainer)
                // Reconcile equipment inventory refs from other devices
                EquipmentInventorySync.pullAllCategories(
                    container: syncContainer
                )
            }
            profiler.record("settingsSync.start")
            SettingsSyncService.shared.start()
            profiler.record("settingsSync.done")

            // Register for remote notifications (CKSyncEngine push)
            UIApplication.shared.registerForRemoteNotifications()
            profiler.record("remoteNotifications.registered")

            // Yield so the first frame commits before heavy initialization
            await Task.yield()
            profiler.record("yield.firstFrame")

            // Mirror existing callsign notes sources to UserDefaults
            // so they get pushed to iCloud on first sync
            CallsignNotesSourceSync.mirrorToDefaults(
                modelContext: sharedModelContainer.mainContext
            )
            profiler.record("notesSources.mirrored")

            // Activate WatchConnectivity for Apple Watch companion
            PhoneSessionDelegate.shared.activate()
            profiler.record("watchConnectivity.activated")

            // Start localhost HTTP bridge for the Pebble companion.
            // Listener naturally suspends with the app; resume happens
            // in the .active scenePhase branch below.
            PebbleBridgeService.shared.start()
            profiler.record("pebbleBridge.started")

            // WSJT-X UDP listener (Settings → Services → WSJT-X). Suspends
            // with the app like the Pebble bridge; resumed in .active below.
            await configureWsjtxIngest()
            profiler.record("wsjtx.configured")

            // Yield between initialization blocks to avoid starving the main run loop.
            // Without these yields, all operations serialize on the main actor
            // with no opportunity for UI updates or deep link processing.
            await Task.yield()
            profiler.record("yield.preServices")

            // Start the shared tick loop that drives all polling services
            PollingCoordinator.shared.start()

            // Start hourly solar conditions polling
            SolarPollingService.shared.configure(container: sharedModelContainer)
            profiler.record("solarPolling.configured")

            // Wire the macros registry service so the Browse + Updates tabs
            // can poll versions/tombstones once configured.
            MacrosRegistryHolder.shared.configure(container: sharedModelContainer)
            profiler.record("macrosRegistry.configured")

            // Load bundled CI-V / Kenwood vendor command catalogs so the
            // macro editor's Vendor Command picker has something to show.
            RadioCommandCatalog.shared.loadBundled()
            profiler.record("radioCommandCatalog.loaded")

            // Start DONKI space weather polling (30-minute interval)
            DONKIPollingService.shared.configure(container: sharedModelContainer)
            profiler.record("donkiPolling.configured")

            // Start contest calendar polling (6-hour interval)
            ContestPollingService.shared.configure()
            profiler.record("contestPolling.configured")

            // Configure iCloud QSO sync (lightweight — engine start deferred
            // until stats pipeline completes to avoid concurrent full-table
            // scans that trigger scene-update watchdog kills).
            CloudSyncService.shared.configure(container: sharedModelContainer)
            profiler.record("cloudSync.configured")

            // Configure clubs sync service (cache rebuild deferred to
            // avoid blocking main thread during startup window).
            ClubsSyncService.shared.configure(container: sharedModelContainer)
            profiler.record("clubsSync.configured")

            CwStoreRecoveryService.shared.configure(container: sharedModelContainer)

            // Friends now live in the Rust store too; rebuild the cache off-main.
            FriendsSyncService.shared.configure()
            // Fire-and-forget: network sync runs in background, doesn't block startup
            Task {
                try? await ClubsSyncService.shared.syncClubs(
                    sourceURL: ActivitiesClient.resolvedBaseURL
                )
                profiler.record("clubsSync.fetched")
            }

            await Task.yield()
            profiler.record("yield.preSCP")

            // Seed QRQ Crew callsign notes source on first launch
            QRQCrewService.seedNotesSourceIfNeeded(
                modelContext: sharedModelContainer.mainContext
            )
            profiler.record("qrqCrew.seeded")

            // Load SCP callsign database (from disk, then check remote if stale)
            await SCPService.shared.loadAndRefresh()

            // Load equipment catalog (from disk, then check remote if stale)
            await EquipmentCatalogService.shared.loadAndRefresh()

            // Backfill inventory weights from the catalog. Cheap (single fetch
            // + dictionary lookup) and only writes items that lack a weight.
            backfillEquipmentWeights()

            // One-time: dedup equipment and re-run migration with improved matcher
            if !UserDefaults.standard.bool(forKey: "equipmentDedup.v1") {
                ContainerSetup.deduplicateEquipment(
                    container: sharedModelContainer
                )
                EquipmentMigration.resetMigration()
                UserDefaults.standard.set(true, forKey: "equipmentDedup.v1")
            }

            // Show interactive migration if user has old equipment data
            if !EquipmentMigration.isMigrated,
               !EquipmentCatalogService.shared.catalog.isEmpty
            {
                showEquipmentMigration = true
            }
            runRadioConfigMigrationIfNeeded()

            // Augment SCP with user's repeat callsigns — fire-and-forget
            // since this only enhances autocomplete, not critical for startup
            let scpContainer = sharedModelContainer
            Task {
                await SCPService.shared.loadUserCallsigns(
                    container: scpContainer
                )
            }

            profiler.finish()
        }
        .task {
            // Preload reference caches concurrently. Binary cache path
            // (normal case after first launch) is lightweight — only the
            // CSV parsing fallback is memory-heavy, and that only runs once.
            let profiler = StartupProfiler.shared
            async let potaLoad: Void = POTAParksCache.shared.ensureLoaded()
            async let sotaLoad: Void = SOTASummitsCache.shared.ensureLoaded()
            async let wwffLoad: Void = WWFFReferencesCache.shared.ensureLoaded()
            async let skccLoad: Void = SKCCMembershipStore.shared.ensureLoaded()
            async let enrichmentLoad: Void = CallsignEnrichmentCache.shared.ensureLoaded()
            _ = await (potaLoad, sotaLoad, wwffLoad, skccLoad, enrichmentLoad)
            profiler.record("cache.refs.done")
            let sources = NotesSourceInfo.fetchAll(
                modelContext: sharedModelContainer.mainContext
            )
            await CallsignNotesCache.shared.ensureLoaded(sources: sources)
            profiler.record("cache.notes")

            // Bring up the operator-profile cache and kick off the
            // QSO-history backfill. Reads are answered from disk so
            // callsign cards render instantly while QRZ/HamDB fan
            // out behind the scenes.
            await OperatorProfileService.shared.start(container: sharedModelContainer)
            profiler.record("cache.operatorProfiles")
        }
        .task {
            // Defer backup until after startup peak to avoid overlapping
            // memory with SCP load, stats, and service configuration.
            // The 2s delay lets startup memory settle before adding
            // backup's file copy + iCloud sync overhead.
            try? await Task.sleep(for: .seconds(2))

            guard UserDefaults.standard.object(
                forKey: "autoBackupEnabled"
            ) as? Bool ?? true,
                let storeURL = sharedModelContainer
                .configurations.first?.url
            else {
                return
            }

            let profiler = StartupProfiler.shared
            profiler.record("backup.start")
            let container = sharedModelContainer
            let count = await Task.detached {
                profiler.record("backup.qsoCount")
                let result = BackupService.visibleQSOCount(in: container)
                profiler.record("backup.qsoCountDone")
                return result
            }.value
            await BackupService.shared.snapshot(
                trigger: .launch,
                storeURL: storeURL,
                qsoCount: count
            )
        }
        .task {
            // Wait for the stats pipeline to finish its full-table scans
            // before starting the CKSyncEngine. This serializes heavy DB
            // work and prevents concurrent scans that block the main thread
            // long enough to trigger the scene-update watchdog (0x8BADF00D).
            // Timeout after 30s so sync still starts even if dashboard
            // is never shown (e.g., deep link to another tab).
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in NotificationCenter.default.notifications(
                        named: .statsPipelineComplete
                    ) {
                        return
                    }
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(30))
                }
                // First to finish wins
                await group.next()
                group.cancelAll()
            }
            let profiler = StartupProfiler.shared
            profiler.record("cloudSync.deferredStart")
            await CloudSyncService.shared.startIfEnabled()
            profiler.record("cloudSync.started")

            // Kick off CoreSpotlight reindex after CloudSync has started
            // so full-table scans remain serialized. Runs in a detached
            // task since indexing is independent of the rest of startup.
            //
            // Priority is `.userInitiated` (not `.utility`) so iOS doesn't
            // aggressively defer it under background pressure — users
            // expect Spotlight results to be available within a reasonable
            // window after launch.
            profiler.record("spotlightReindex.scheduled")
            let spotlightContainer = sharedModelContainer
            Task.detached(priority: .userInitiated) {
                await SpotlightReindexActor.shared.reindexIfNeeded(
                    container: spotlightContainer
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Reconcile callsign stores: UserProfile is canonical;
                // Keychain/UserDefaults are derived caches (CAR-287)
                UserProfileService.shared.reconcileCallsignStores()
                PollingCoordinator.shared.resume()
                AutoSyncService.shared.resume()
                PebbleBridgeService.shared.start()
                Task { await WsjtxFieldService.shared.startIfEnabled() }
                Task {
                    await CloudSyncService.shared.fetchChangesFromCloud()
                    // Remote deletes just merged from iCloud are mirror-blind, so
                    // prune any cw-store rows SwiftData no longer has.
                    reconcileCwStoreFollower()
                }
                Task {
                    try? await ClubsSyncService.shared.syncClubs(
                        sourceURL: ActivitiesClient.resolvedBaseURL
                    )
                }
                Task { await detectHomeScreenWidget() }
                Task {
                    await PerfUploader.shared.flushQueue()
                }
                Task {
                    await MacrosRegistryHolder.shared.pollIfStale()
                    await CallsignCacheForegroundRefresh.run(container: sharedModelContainer)
                }
                SyncBackgroundRefresh.schedule()
                SatellitePassBackgroundRefresh.schedule()
                SatellitePassAlertScheduler.shared.reschedule(trigger: "foreground")
            } else {
                PollingCoordinator.shared.pause()
                AutoSyncService.shared.pause()
                SyncBackgroundRefresh.schedule()
                SatellitePassBackgroundRefresh.schedule()
                Task {
                    // Snapshot cadence check (Phase 7.4). The assertion keeps
                    // the brief cw-store count read suspension-safe.
                    let assertion = BackgroundTaskAssertion(name: "serverSnapshotCheck")
                    defer { assertion.release() }
                    await ServerSnapshotCoordinator.snapshotIfDue(trigger: "background")
                }
            }
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            handleSpotlightActivity(activity)
        }
        .onOpenURL { url in
            handleURL(url)
        }
        .sheet(isPresented: $showEquipmentMigration) {
            EquipmentMigrationSheet {
                showEquipmentMigration = false
            }
        }
        .task {
            await applyQSOMirrorMode(qsoMode)
        }
        .onChange(of: qsoMode) { _, newMode in
            Task {
                await applyQSOMirrorMode(newMode)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CwStoreRecoveryService.didRebuildNotification)) { _ in
            Task { await reestablishMirrorAfterRebuild(mode: qsoMode) }
        }
        .modelContainer(sharedModelContainer)
    }
}

// QSO Mirror extension lives in CarrierWaveApp+QSOMirror.swift
// Notification.Name extensions live in CarrierWaveApp+Notifications.swift
