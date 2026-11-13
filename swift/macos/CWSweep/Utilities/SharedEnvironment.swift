import CarrierWaveData
import SwiftUI

// MARK: - SharedEnvironment

/// App-wide shared state objects injected into all window scenes.
/// Lifting these from WorkspaceView to the app level ensures auxiliary
/// windows (Band Map, Spot Cluster, QSO Entry) have access to the same
/// instances — preventing crashes when macOS restores windows on launch.
@MainActor
final class SharedEnvironment: Observable {
    // MARK: Lifecycle

    private init() {
        savedQueryStore = Self.makeSavedQueryStore()
        remoteOpService.radioManager = radioManager
        remoteOpService.winKeyerManager = winKeyerManager
        remoteOpService.spotAggregator = spotAggregator
        remoteOpService.savedQueryStore = savedQueryStore
        remoteOpService.queryRunner = bandScopeQueryRunner
        remoteOpService.cwKeyerService = cwKeyerService
        remoteOpService.selectionState = selectionState
        jttyService.radioManager = radioManager
        remoteOpPublishers = RemoteOpPublishers(service: remoteOpService)
        remoteOpSessionBroadcaster = RemoteOpSessionBroadcaster(service: remoteOpService)
        trackerAutoDetector = TrackerAutoDetector(discovery: trackerDiscovery, rotator: rotatorController)
        satellitePassModel = SatellitePassModel(
            radioManager: radioManager, cat: satelliteCAT, rotator: rotatorController
        )
        satLogListenerService.didLogQSO = { [selectionState] qso in
            QueryFacade.mirrorQSO(qso)
            selectionState.logInsertedQSORow = QSOTableRow(from: qso)
        }
    }

    // MARK: Internal

    static let shared = SharedEnvironment()

    let radioManager = RadioManager()
    let portMonitor = SerialPortMonitor()
    let spotAggregator = SpotAggregator()
    let dxccLookup = DXCCLookupService()
    let neededChecker = DXCCNeededChecker()
    let clusterManager = ClusterManager()
    let layoutStore = LayoutStore()
    let selectionState = SelectionState()
    let winKeyerManager = WinKeyerManager()
    let bridgeDiscovery = BridgeDiscoveryService()
    let savedQueryStore: SavedQueryStore
    /// Shared SQL filter runner — lifted out of BandMapView so the
    /// contest scope, stacked scope, and band map all read from a
    /// single QueryReader and a single polling task. Whichever view
    /// has the mode picker visible drives `setQuery`.
    let bandScopeQueryRunner = BandScopeQueryRunner()
    let cwKeyerService = CWKeyerService()
    let remoteOpService = RemoteOpService()
    /// Lifted from `WorkspaceView` so every scene (activator layout,
    /// custom layouts, vim executor, popup windows) talks to the same
    /// instance — otherwise the activator header was creating one copy
    /// for the timer countdown and the vim executor was creating
    /// another for `:spot`, and neither was ever `configureForSession`'d.
    let potaSpotService = POTASpotService()
    /// CSN S.A.T. satellite-tracker ADIF listener (CAR-343). Started at
    /// launch when enabled in Settings → S.A.T.
    let satLogListenerService = SatLogListenerService()
    /// WSJT-X UDP listener → log (CAR-282). Configured and started from
    /// `CWSweepApp.configureWsjtxIngest()`; driven by Settings → WSJT-X.
    let wsjtxIngest = WsjtxIngestService()
    /// JTTY modem (CAR-351): jtty-sidecar helper + audio + terminal state.
    let jttyService = JttyService()
    /// LAN sweep for CSN S.A.T. / PSR-100 rotators (Settings → Trackers).
    let trackerDiscovery = TrackerDiscoveryService()
    /// The station rotator link; `connectSaved()` at launch re-links the
    /// remembered unit. Driven by `satellitePassModel` while a pass is up.
    let rotatorController = RotatorController()
    /// Hands-free "S.A.T. detected — Connect?" (sweeps at launch, on network
    /// changes, every 3 min; re-links the remembered unit silently).
    let trackerAutoDetector: TrackerAutoDetector
    /// Doppler CAT pushes for the Satellites workspace.
    let satelliteCAT = SatelliteCATController()
    /// Pass list + 1 Hz tracking frame behind the Satellites sidebar item.
    let satellitePassModel: SatellitePassModel
    private(set) var remoteOpPublishers: RemoteOpPublishers!
    private(set) var remoteOpSessionBroadcaster: RemoteOpSessionBroadcaster!

    // MARK: Private

    private static func makeSavedQueryStore() -> SavedQueryStore {
        let directory: URL
        if let iCloud = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.com.jsvana.FullDuplex"
        ) {
            directory = iCloud.appendingPathComponent("Documents/Queries", isDirectory: true)
        } else {
            let appSupport = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            directory = appSupport
                .appendingPathComponent("CWSweep", isDirectory: true)
                .appendingPathComponent("Queries", isDirectory: true)
        }
        return SavedQueryStore(directory: directory)
    }
}

// MARK: - SavedQueryStoreKey

/// `SavedQueryStore` is an `actor`, not `@Observable`, so it can't be
/// injected via the new `.environment(_:)` Observable overload. Use a
/// classic `EnvironmentKey` instead.
private struct SavedQueryStoreKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: SavedQueryStore? = nil
}

extension EnvironmentValues {
    var savedQueryStore: SavedQueryStore? {
        get { self[SavedQueryStoreKey.self] }
        set { self[SavedQueryStoreKey.self] = newValue }
    }
}

extension View {
    /// Inject all shared environment objects into the view hierarchy.
    func sharedEnvironments() -> some View {
        let env = SharedEnvironment.shared
        return environment(env.radioManager)
            .environment(env.portMonitor)
            .environment(env.spotAggregator)
            .environment(env.dxccLookup)
            .environment(env.neededChecker)
            .environment(env.clusterManager)
            .environment(env.layoutStore)
            .environment(env.selectionState)
            .environment(env.winKeyerManager)
            .environment(env.bridgeDiscovery)
            .environment(env.bandScopeQueryRunner)
            .environment(env.remoteOpService)
            .environment(env.potaSpotService)
            .environment(env.satLogListenerService)
            .environment(env.wsjtxIngest)
            .environment(SpotEntryBridge.shared)
            .environment(\.savedQueryStore, env.savedQueryStore)
    }
}
