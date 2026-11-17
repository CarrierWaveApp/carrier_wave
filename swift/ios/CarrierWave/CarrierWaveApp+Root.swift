import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Scene root

extension CarrierWaveApp {
    var body: some Scene {
        WindowGroup {
            if Self.isHostingUnitTests {
                Color.clear
            } else {
                appRoot
            }
        }
    }

    var appRoot: some View {
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

// MARK: - Unit-test host mode

extension CarrierWaveApp {
    /// True when XCTest launched this process to host `CarrierWaveTests`.
    ///
    /// The unit tests run inside the app binary (TEST_HOST), so without this
    /// every test run also performed the full launch: keychain/ledger
    /// migrations, BGTask registration, opening the real on-disk store, the
    /// park/summit cache hydration, the repair chain, NOAA fetches and sync.
    /// That made runs take most of an hour and raced the tests (e.g. a
    /// conditions fetch writing to a session after its test store was gone).
    /// Tests build their own containers, so the host does none of it.
    ///
    /// XCTest sets `XCTestConfigurationFilePath` only in a unit-test host; UI
    /// tests launch the app as a normal separate process and are unaffected.
    static let isHostingUnitTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Wire the cw-store registries to a throwaway in-memory `FieldStore`.
    ///
    /// The logger is Rust-only (`logQSO` goes through `SessionApiRegistry`), so
    /// the session/QSO tests need these registries. A normal launch binds them
    /// to the real app-group store in `applyQSOMirrorMode`, which meant the
    /// tests were writing into the simulator's real log. Same wiring here, but
    /// in memory and without the first-run import or follower reconcile.
    static func installTestHostStore() {
        guard ExperimentalFeature.isEnabled(.rustStoreQSO) else {
            return
        }
        do {
            let store = try FieldStore.openInMemory(key: "unit-test-host")
            let mirror = CwStoreMirror(store: store)
            mirror.start()
            CwStoreMirrorRegistry.current = mirror
            QSOWriteSinkRegistry.current = QSOWriteSink(store: store, mirror: mirror)
            ServicePresenceWriteSinkRegistry.current = ServicePresenceWriteSink(store: store, mirror: mirror)
            SeamWriteBatchRegistry.current = (store, mirror)
            OffMainStoreSeam.activate(store: store, mirror: mirror)
            EntityWriteSinkFactory.registerAll(store: store, mirror: mirror)
            ActivityLogApiRegistry.current = ActivityLogApi(store: store)
            SessionApiRegistry.current = SessionApi(store: store)
            LoggerCommandApiRegistry.current = LoggerCommandApi(store: store)
        } catch {
            CwStoreWriteLog.shared.record("Test host store setup failed: \(error.localizedDescription)")
        }
    }

    /// Throwaway in-memory container for the test host, so nothing the host
    /// touches reads or writes the simulator's real store.
    static func makeTestHostContainer() -> (container: ModelContainer, url: URL) {
        let schema = Schema(AppSchema.models)
        // A distinct name keeps this store apart from the in-memory
        // containers tests create under the default configuration name.
        let configuration = ModelConfiguration(
            "UnitTestHost",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = ContainerSetup.createModelContainer(schema: schema, configuration: configuration)
        return (container, configuration.url)
    }
}
