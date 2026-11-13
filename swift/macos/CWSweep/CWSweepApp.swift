import AppKit
import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - AppDelegate

/// Kept for `@NSApplicationDelegateAdaptor`; CloudKit push handling left with
/// the iCloud sync engine (Carrier Wave Sync polls instead).
class AppDelegate: NSObject, NSApplicationDelegate {}

// MARK: - CWSweepApp

@main
struct CWSweepApp: App {
    // MARK: Lifecycle

    init() {
        // Before any store opens: move data from the iOS-style App Group
        // container into the team-prefixed one (see MacGroupContainerMigration).
        MacGroupContainerMigration.runIfNeeded()
        ServerSyncLog.install(SweepSyncLogSink())

        let schema = Schema(CarrierWaveSchema.models)
        let config = ModelConfiguration(
            "CWSweep",
            schema: schema,
            cloudKitDatabase: .none
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        let storeOpt: QueryStore? = Self.makeQueryStore()
        if let store = storeOpt {
            QueryFacade.register(store)
        }
        queryStore = storeOpt
        let savedQueryStore = SharedEnvironment.shared.savedQueryStore
        if let store = storeOpt {
            querySeedCoordinator = QuerySeedCoordinator(
                store: store,
                container: modelContainer,
                loggerSubsystem: "com.jsvana.CWSweep"
            )
            workbenchModel = QueryWorkbenchModel(store: store, savedQueryStore: savedQueryStore)
        } else {
            querySeedCoordinator = nil
            workbenchModel = nil
        }

        // Trigger iCloud KVS sync on launch
        NSUbiquitousKeyValueStore.default.synchronize()

        // Observe remote KVS changes
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { _ in
            Task { await PoloNotesStore.shared.forceRefresh() }
        }
    }

    // MARK: Internal

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Strong reference to the live cw-store mirror (the `CwStoreMirrorRegistry`
    /// handle is `weak`). `nil` when `CwStoreQSOMode == .off`. See
    /// `applyCwStoreMirrorMode()`.
    @State var cwStoreMirror: CwStoreMirror?

    let modelContainer: ModelContainer
    let queryStore: QueryStore?
    let querySeedCoordinator: QuerySeedCoordinator?
    let workbenchModel: QueryWorkbenchModel?

    var body: some Scene {
        Window("CW Sweep", id: "workspace") {
            WorkspaceView()
                .environment(vimEngine)
                .environment(SharedEnvironment.shared.jttyService)
                .task {
                    vimInterceptor.install(engine: vimEngine)
                    vimEngine.isEnabled = UserDefaults.standard.bool(forKey: "vimModeEnabled")
                }
                .task {
                    // Start the shared cw-store mirror in shadow/on mode (no-op when
                    // `cwStoreQSOMode == .off`, the default). See applyCwStoreMirrorMode().
                    await applyCwStoreMirrorMode()
                }
                .task {
                    ServerSyncService.shared.configure(container: modelContainer)
                    SharedEnvironment.shared.remoteOpService.modelContainer = modelContainer
                    SharedEnvironment.shared.remoteOpSessionBroadcaster.start()
                    SharedEnvironment.shared.satLogListenerService.modelContainer = modelContainer
                    SharedEnvironment.shared.satLogListenerService.startIfEnabled()
                    await SharedEnvironment.shared.rotatorController.connectSaved()
                    SharedEnvironment.shared.trackerAutoDetector.start()
                    MacrosRegistryHolder.shared.configure(container: modelContainer)
                    RadioCommandCatalog.shared.loadBundled()
                    await POTAParksCache.shared.ensureLoaded()
                    await CallsignEnrichmentStore.shared.ensureLoaded()
                    await SessionBackfillService.runIfNeeded(
                        modelContext: ModelContext(modelContainer)
                    )
                    await configureWsjtxIngest()
                    await SharedEnvironment.shared.jttyService.startIfEnabled()
                    await runSatelliteSnapshotIfRequested()
                }
                .task {
                    // Kick off the QSO seed at app launch (was lazily on
                    // workbench open) so the workbench is usable
                    // immediately, and prune the transient spot scope on
                    // a 60s cadence so a long session doesn't accumulate
                    // observations indefinitely.
                    querySeedCoordinator?.seedIfNeeded()
                    guard let store = queryStore else {
                        return
                    }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        if Task.isCancelled {
                            break
                        }
                        try? await store.pruneScope(window: 30 * 60)
                    }
                }
                .task {
                    await Task.yield()
                    if whatsNewService.hasPendingEntries {
                        showWhatsNew = true
                    } else {
                        whatsNewService.markFreshInstallIfNeeded()
                    }
                }
                .sheet(isPresented: $showWhatsNew) {
                    WhatsNewSheet(entries: whatsNewService.pendingEntries) {
                        whatsNewService.markCurrentVersionSeen()
                        showWhatsNew = false
                    }
                }
                .onOpenURL { url in
                    if MacroURLHandler.handle(url) {
                        return
                    }
                    EnrichedLinkRouter.handle(url)
                }
                .acceptsCwmacroDrop()
                .sharedEnvironments()
        }
        .handlesExternalEvents(matching: ["link"])
        .modelContainer(modelContainer)
        .defaultSize(width: 1_400, height: 900)
        .commands { CWSweepCommands(updater: appUpdater.updater) }

        Window("Band Map", id: "bandmap") {
            BandMapPanel()
                .sharedEnvironments()
                .floatingWindow()
        }
        .modelContainer(modelContainer)

        Window("Add QSO", id: "qso-entry") {
            QSOEntryPopupView()
                .environment(SpotEntryBridge.shared)
                .sharedEnvironments()
                .floatingWindow()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 520, height: 520)
        .windowResizability(.contentMinSize)

        Window("Spot Cluster", id: "cluster") {
            ClusterPanel()
                .sharedEnvironments()
                .floatingWindow()
        }
        .modelContainer(modelContainer)

        Window("Query Workbench", id: "query-workbench") {
            queryWorkbenchScene
                .sharedEnvironments()
                .onOpenURL { url in
                    if url.scheme == SavedQueryURL.scheme {
                        Task { await workbenchModel?.importFrom(url: url) }
                    }
                }
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1_100, height: 700)
        .handlesExternalEvents(matching: ["import"])

        Settings {
            SettingsView()
                .environment(SharedEnvironment.shared.remoteOpService)
                .environment(SharedEnvironment.shared.satLogListenerService)
                .environment(SharedEnvironment.shared.wsjtxIngest)
                .environment(SharedEnvironment.shared.jttyService)
        }
        .modelContainer(modelContainer)

        Window("Badges", id: "achievements") {
            AchievementShowcaseWindow()
        }
        .defaultSize(width: 560, height: 600)

        Window("Macros", id: "macros") {
            NavigationStack {
                MacrosLibraryView()
            }
            .sharedEnvironments()
            .acceptsCwmacroDrop()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 760, height: 640)

        MenuBarExtra("CW Sweep", systemImage: "antenna.radiowaves.left.and.right") {
            MenuBarExtraView()
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)
    }

    // MARK: Private

    @State private var vimEngine = VimEngine()
    @State private var vimInterceptor = VimKeyInterceptor()
    @State private var whatsNewService = WhatsNewService(platform: .macOS)
    @State private var showWhatsNew = false

    private let appUpdater = AppUpdaterController()

    @ViewBuilder
    private var queryWorkbenchScene: some View {
        if let workbenchModel {
            QueryWorkbenchView(
                model: workbenchModel,
                seedCoordinator: querySeedCoordinator
            )
        } else {
            Text("Query Workbench unavailable: failed to open the local query database.")
                .padding()
        }
    }

    private static func makeQueryStore() -> QueryStore? {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("CWSweep", isDirectory: true)
            let dbURL = appSupport.appendingPathComponent("bandscope.sqlite")
            let cacheDir = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("CWSweep", isDirectory: true)
            let scopeURL = cacheDir.appendingPathComponent("scope.sqlite")
            return try QueryStore(databaseURL: dbURL, scopeURL: scopeURL)
        } catch {
            return nil
        }
    }
}
