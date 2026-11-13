import CarrierWaveCwFfi
import CarrierWaveData
import Foundation
import Observation

// MARK: - PropagationCheckConfig

/// Frozen-at-start configuration for a propagation check.
///
/// The Rust `PropagationApi` owns the polling / windowing / enrichment; this
/// Swift config keeps the host-only fields the engine has no opinion on
/// (`transmitMode` drives the Swift Auto-CQ controller; `durationCap` drives
/// the live view's auto-stop timer).
nonisolated struct PropagationCheckConfig: Hashable {
    var callsign: String
    var bands: [String]
    var transmitMode: PropagationTransmitMode
    var userGrid: String
    var startedAt: Date
    var durationCap: TimeInterval?

    /// Suffix-tolerant matcher: `^<base>(\/[A-Z0-9]+)?$`, case-insensitive.
    /// Catches `/P`, `/M`, `/MM`, `/QRP` portable suffixes. Mirrors the Rust
    /// engine's `callsign_matches`; kept here for the config-match unit tests.
    func matches(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespaces).uppercased()
        let base = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        if trimmed == base {
            return true
        }
        if trimmed.hasPrefix("\(base)/") {
            let suffix = trimmed.dropFirst(base.count + 1)
            // Allow letters/digits in suffix, no further slashes.
            return !suffix.isEmpty
                && suffix.allSatisfy { $0.isLetter || $0.isNumber }
        }
        return false
    }
}

// MARK: - PropagationCheckSession

/// Live ingestion session for a propagation check.
///
/// A thin `@Observable` host wrapper over the shared Rust `PropagationApi`:
/// it starts the session, drives `poll()` on the ported cadence, and mirrors
/// the returned `FfiPropagationState` into the observable surface the live
/// view reads (spots, headline counters, connectivity). The RBN / PSK Reporter
/// fetch, dedup, windowing, and grid enrichment all live in Rust now.
///
/// Two things stay host-side on purpose:
/// - **Solar snapshot.** The `autoRecordConditions` gate + HamQSL fetch run in
///   Swift at start and are handed into `FfiPropagationConfig.solar`; the
///   engine stays store-/`UserDefaults`-free.
/// - **Auto-CQ.** `PropagationAutoCQController` drives the radio bridge, not the
///   ingestion engine, so it stays Swift and interacts through this wrapper.
///
/// Lifecycle:
/// - `start(config:)` — captures solar, starts the Rust session, begins polling.
/// - `stop(reason:)` — stops the session and returns a finalized `Snapshot`
///   built from `PropagationApi.results()`.
@MainActor
@Observable
final class PropagationCheckSession {
    // MARK: Lifecycle

    init(
        noaaClient: NOAAClient = NOAAClient(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.noaaClient = noaaClient
        self.clock = clock
    }

    // MARK: Internal

    // MARK: - Snapshot

    /// Finalized session result. Built from `PropagationApi.results()` at stop.
    nonisolated struct Snapshot {
        var spots: [PropagationSpotEntry]
        var gaps: [PropagationConnectivityGap]
        var endedAt: Date
        var stopReason: PropagationStopReason = .user

        // Denormalized headline totals, straight off the Rust results.
        var totalSpots: Int = 0
        var uniqueSkimmers: Int = 0
        var bandsWithActivity: [String] = []
        var maxDistanceKm: Double = 0
        var peakSNRdB: Double = 0

        // Solar / space weather captured at session start (host-supplied,
        // threaded through the Rust results verbatim). nil if the fetch failed,
        // the user disabled auto-recording, or the network was offline.
        var solarKIndex: Double?
        var solarAIndex: Int?
        var solarFlux: Double?
        var solarSunspots: Int?
        var solarPropagationRating: String?
        var solarBandConditions: String?
        var solarTimestamp: Date?
    }

    enum LogLevel { case info, error }

    // Live, observable state mirrored from the latest `FfiPropagationState`.
    var config: PropagationCheckConfig?
    var spots: [PropagationSpotEntry] = []
    var enrichedSpots: [PropagationEnrichedSpot] = []
    var rbnConnected = true
    var pskrConnected = true
    var lastError: String?
    var isRunning = false
    var stopReason: PropagationStopReason = .user

    let autoCQ = PropagationAutoCQController()

    // MARK: - Headline live stats (mirrored from the latest poll state)

    var totalSpots: Int {
        liveTotalSpots
    }

    var uniqueSkimmers: Int {
        liveUniqueSkimmers
    }

    var bandsWithActivity: [String] {
        liveBandsWithActivity
    }

    var maxDistanceKm: Double {
        liveMaxDistanceKm
    }

    var peakSNRdB: Double {
        livePeakSNRdB
    }

    /// Recent spots (last `seconds`) — drives the live map's freshness fade.
    func recentSpots(within seconds: TimeInterval) -> [PropagationSpotEntry] {
        let now = clock()
        return spots.filter { now.timeIntervalSince($0.timestamp) < seconds }
    }

    func start(config: PropagationCheckConfig) {
        guard !isRunning else {
            return
        }
        self.config = config
        isRunning = true
        spots = []
        enrichedSpots = []
        lastError = nil
        rbnConnected = true
        pskrConnected = true

        log(.info, "Propagation check started for \(config.callsign), bands: \(config.bands.joined(separator: ","))")

        // Capture solar host-side (gate + HamQSL fetch), then start the Rust
        // session with the snapshot frozen into the config, then begin polling.
        pollingTask = Task { [weak self] in
            guard let self else {
                return
            }
            let solar = await captureSolar()
            await beginSession(config: config, solar: solar)
            await pollLoop()
        }

        let shouldAutoCQ = config.transmitMode != .passive
            && PropagationAutoCQController.isAvailable(for: config.transmitMode)
        if shouldAutoCQ {
            autoCQ.start(
                mode: config.transmitMode,
                callsign: config.callsign
            ) { [weak self] in
                guard let self else {
                    return
                }
                _ = stop(reason: .radioFault)
            }
        }
    }

    /// Stop the Rust session and return a finalized `Snapshot` from
    /// `PropagationApi.results()`. Idempotent-ish: safe to call twice, the
    /// second call returns whatever `results()` last produced (or an empty
    /// snapshot if the session never started).
    func stop(reason: PropagationStopReason) -> Snapshot {
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
        stopReason = reason
        if autoCQ.isRunning {
            autoCQ.stop()
        }

        guard let api else {
            return Snapshot(spots: [], gaps: [], endedAt: clock(), stopReason: reason)
        }

        do {
            try api.stop(reason: reason.ffiStopReason)
            let results = try api.results()
            let snapshot = Self.snapshot(from: results, endedAt: clock())
            log(
                .info,
                "Propagation check stopped (\(reason.rawValue)); "
                    + "\(snapshot.spots.count) spots, \(snapshot.uniqueSkimmers) skimmers"
            )
            return snapshot
        } catch {
            log(.error, "Propagation stop/results failed: \(error.localizedDescription)")
            return Snapshot(spots: spots, gaps: [], endedAt: clock(), stopReason: reason)
        }
    }

    // MARK: Private

    private let noaaClient: NOAAClient
    private let clock: @Sendable () -> Date

    private var api: PropagationApi?
    private var pollingTask: Task<Void, Never>?

    private var liveTotalSpots = 0
    private var liveUniqueSkimmers = 0
    private var liveBandsWithActivity: [String] = []
    private var liveMaxDistanceKm: Double = 0
    private var livePeakSNRdB: Double = 0

    /// Whether the user has opted into auto-recording solar/weather conditions.
    /// Shared key with `LoggingSessionManager+Conditions`; defaults to true.
    private var autoRecordConditions: Bool {
        if UserDefaults.standard.object(forKey: "autoRecordConditions") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "autoRecordConditions")
    }

    /// Build the `Snapshot` (host artifact shape) from the Rust results.
    ///
    /// Persist the *enriched* spot list: `skimmerGrid` is patched from the
    /// engine's `effectiveGrid` fallback (callbook cache / QRZ locate) when the
    /// source didn't report one, so the saved-results view keeps every
    /// resolvable spot on the map / distance breakdown without re-enriching.
    /// The blob shape (`[PropagationSpotEntry]`) is unchanged.
    private static func snapshot(from results: FfiPropagationResults, endedAt: Date) -> Snapshot {
        let spots = results.enrichedSpots.map { enriched -> PropagationSpotEntry in
            var entry = PropagationSpotEntry(ffi: enriched.spot)
            if entry.skimmerGrid == nil {
                entry.skimmerGrid = enriched.effectiveGrid
            }
            return entry
        }
        let gaps = results.connectivityGaps.map(PropagationConnectivityGap.init(ffi:))
        let solar = results.solar
        return Snapshot(
            spots: spots,
            gaps: gaps,
            endedAt: endedAt,
            stopReason: PropagationStopReason(ffi: results.stopReason),
            totalSpots: Int(results.totalSpots),
            uniqueSkimmers: Int(results.uniqueSkimmers),
            bandsWithActivity: results.bandsWithActivity,
            maxDistanceKm: results.maxDistanceKm,
            peakSNRdB: results.peakSnrDb,
            solarKIndex: solar?.kIndex,
            solarAIndex: solar?.aIndex.map(Int.init),
            solarFlux: solar?.flux,
            solarSunspots: solar?.sunspots.map(Int.init),
            solarPropagationRating: solar?.propagationRating,
            solarBandConditions: solar?.bandConditions,
            solarTimestamp: solar?.timestampEpoch.map { Date(timeIntervalSince1970: $0) }
        )
    }

    /// Host-side solar capture: gate on `autoRecordConditions`, fetch HamQSL via
    /// NOAAClient, and shape into the FFI solar record. Failures yield nil.
    private func captureSolar() async -> FfiPropagationSolar? {
        guard autoRecordConditions else {
            return nil
        }
        do {
            let solar = try await noaaClient.fetchSolarConditions()
            log(.info, "Recorded solar conditions: \(solar.description)")
            return FfiPropagationSolar(
                kIndex: solar.kIndex,
                aIndex: solar.aIndex.map(Int32.init),
                flux: solar.solarFlux,
                sunspots: solar.sunspots.map(Int32.init),
                propagationRating: solar.propagationRating,
                bandConditions: solar.bandConditions,
                timestampEpoch: solar.timestamp.timeIntervalSince1970
            )
        } catch {
            log(.error, "Solar conditions fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Construct the Rust `PropagationApi` and start the session.
    private func beginSession(config: PropagationCheckConfig, solar: FfiPropagationSolar?) async {
        do {
            let store = try await CwStoreProvider.shared.store()
            let qrz = try QrzApi(secure: KeychainSecureStore())
            let baseURL = ActivitiesClient.normalizeBase(ActivitiesClient.resolvedBaseURL)
            let created = try PropagationApi(store: store, qrz: qrz, baseUrl: baseURL)
            let ffiConfig = FfiPropagationConfig(
                callsign: config.callsign,
                bands: config.bands,
                userGrid: config.userGrid,
                startedAtEpoch: config.startedAt.timeIntervalSince1970,
                solar: solar
            )
            try created.startSession(config: ffiConfig)
            api = created
        } catch {
            log(.error, "Propagation session start failed: \(error.localizedDescription)")
            isRunning = false
        }
    }

    /// Drive `poll()` on the ported cadence. A single call maps to one iteration
    /// of the Swift `pollLoop` body; the engine enforces the PSK Reporter floor.
    private func pollLoop() async {
        guard let api else {
            return
        }
        let cadence = propagationPollCadence()
        // The engine schedules RBN vs PSKR internally; the host just needs to
        // re-poll at the RBN cadence (the tighter of the two).
        let pollInterval = max(1, cadence.rbnIntervalSecs)

        while !Task.isCancelled, isRunning {
            do {
                let state = try await api.poll()
                apply(state)
            } catch {
                lastError = error.localizedDescription
                log(.error, "Propagation poll failed: \(error.localizedDescription)")
            }
            if Task.isCancelled {
                break
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    /// Mirror the latest poll state into the observable surface.
    private func apply(_ state: FfiPropagationState) {
        enrichedSpots = state.enrichedSpots.map(PropagationEnrichedSpot.init(ffi:))
        spots = enrichedSpots.map(\.entry)
        liveTotalSpots = Int(state.totalSpots)
        liveUniqueSkimmers = Int(state.uniqueSkimmers)
        liveBandsWithActivity = state.bandsWithActivity
        liveMaxDistanceKm = state.maxDistanceKm
        livePeakSNRdB = state.peakSnrDb
        rbnConnected = state.rbnConnected
        pskrConnected = state.pskrConnected
        lastError = state.lastError
    }

    private func log(_ level: LogLevel, _ message: String) {
        // Route through the in-app log surface per project rule.
        switch level {
        case .info:
            RadioService.shared.addLog(.info, message)
        case .error:
            RadioService.shared.addLog(.error, message)
        }
    }
}
