import CarrierWaveCore
import CarrierWaveData
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "SatellitePass")

// MARK: - SatellitePassModel

/// Main-actor state for the Satellites workspace: the upcoming-pass list,
/// the selected pass, and a 1 Hz `SatellitePassFrame` with live look angles,
/// Doppler, and the predicted/flown sky tracks. Also the single place that
/// pushes the frame to CAT (`SatelliteCATController`) and the rotator
/// (`RotatorController`), so tracking keeps running when the operator
/// switches to another sidebar item.
///
/// Observer location comes from Settings → General → Grid (`myGrid`). All
/// orbital math is the shared Rust engine (`SatelliteApi`); the blocking
/// sync calls run off-main.
@MainActor
@Observable
final class SatellitePassModel {
    // MARK: Lifecycle

    init(radioManager: RadioManager, cat: SatelliteCATController, rotator: RotatorController) {
        self.radioManager = radioManager
        self.cat = cat
        self.rotator = rotator
        minimumPeakElevationDeg = UserDefaults.standard.object(forKey: Keys.minPeak) as? Double ?? 10
    }

    // MARK: Internal

    /// Lead time before AOS at which the rotator is sent to the rise azimuth.
    static let prePositionLead: TimeInterval = 5 * 60
    /// How far ahead the sidebar looks.
    static let upcomingWindowHours = 6.0

    private(set) var state: LoadState = .idle
    private(set) var satellites: [Int: SweepSatellite] = [:]
    private(set) var tlesFetchedAt: Date?
    private(set) var tlesStale = false
    private(set) var observerGrid: String?
    private(set) var observer: FfiObserver?
    /// Passes in the next `upcomingWindowHours`, in-progress first then by AOS.
    private(set) var upcoming: [SweepPass] = []
    private(set) var selectedPass: SweepPass?
    private(set) var frame = SatellitePassFrame(now: Date())
    private(set) var isRunning = false
    private(set) var lastRefreshAt: Date?

    /// Move to the next pass automatically after LOS.
    var autoAdvance = true

    let radioManager: RadioManager
    let cat: SatelliteCATController
    let rotator: RotatorController

    /// Hide passes peaking below this (handheld-yagi workability floor).
    var minimumPeakElevationDeg: Double {
        didSet {
            UserDefaults.standard.set(minimumPeakElevationDeg, forKey: Keys.minPeak)
            Task { await refreshUpcoming() }
        }
    }

    var selectedSatellite: SweepSatellite? {
        selectedPass.flatMap { satellites[$0.noradID] }
    }

    /// Begin loading + ticking. Idempotent; tracking continues until `stop()`.
    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        loopTask = Task { [weak self] in
            await self?.load()
            var tickCount = 0
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                if tickCount.isMultiple(of: 60) {
                    await refreshUpcoming()
                }
                await tick(includeAltitude: tickCount.isMultiple(of: 5))
                tickCount += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        isRunning = false
    }

    /// Force a SatNOGS/TLE refresh.
    func reload() async {
        await load(forceRefresh: true)
        await refreshUpcoming()
    }

    func select(_ pass: SweepPass) {
        guard pass != selectedPass else {
            return
        }
        selectedPass = pass
        flown.removeAll()
        predicted.removeAll()
        Task { await rebuildTrack(for: pass) }
    }

    /// Rebuild the sidebar list and keep the selection sane.
    func refreshUpcoming() async {
        refreshObserver()
        guard state == .loaded, let observer, let api = try? await SweepSatelliteEngine.api() else {
            upcoming = []
            return
        }
        let now = Date()
        do {
            let ffiPasses = try await api.upcomingPasses(
                observer: observer,
                startEpoch: Int64(now.timeIntervalSince1970),
                hours: Self.upcomingWindowHours,
                favorites: []
            )
            let floor = minimumPeakElevationDeg
            var passes = ffiPasses
                .map { SweepPass(noradID: Int($0.noradId), name: $0.name, ffi: $0.pass) }
                .filter { $0.peakElevationDeg >= floor && $0.los > now }
            passes.sort { lhs, rhs in
                let lhsActive = lhs.isActive(at: now)
                let rhsActive = rhs.isActive(at: now)
                if lhsActive != rhsActive {
                    return lhsActive
                }
                return lhsActive ? lhs.los < rhs.los : lhs.aos < rhs.aos
            }
            upcoming = passes
            lastRefreshAt = now
        } catch {
            logger.error("upcoming passes failed: \(error.localizedDescription)")
        }
        if let current = selectedPass, let refreshed = upcoming.first(where: { $0.id == current.id }) {
            selectedPass = refreshed
        } else if selectedPass == nil || selectedPass.map({ $0.los < now }) == true {
            if autoAdvance, let next = upcoming.first {
                select(next)
            }
        }
    }

    // MARK: Private

    private var loopTask: Task<Void, Never>?
    private var predicted: [SkyTrackPoint] = []
    private var flown: [SkyTrackPoint] = []
    private var lastAltitudeKm: Double?

    /// Show the catalog as fast as possible, then bring it up to date. A
    /// normal start builds it from the engine's cache (any age, no network)
    /// and refreshes in the background, so a slow SatNOGS download never
    /// holds tracking on "loading". Only a cold cache or `forceRefresh`
    /// (Reload) waits on the network.
    private func load(forceRefresh: Bool = false) async {
        if satellites.isEmpty {
            state = .loading
        }
        let api: SatelliteApi
        do {
            api = try await SweepSatelliteEngine.api()
        } catch {
            logger.error("satellite engine unavailable: \(error.localizedDescription)")
            if satellites.isEmpty {
                state = .failed(error.localizedDescription)
            }
            return
        }
        if forceRefresh {
            await refreshFromNetwork(api, force: true)
            return
        }
        if satellites.isEmpty, let cached = try? await api.loadCached() {
            await applyCatalog(from: api, summary: cached)
        }
        if satellites.isEmpty {
            await refreshFromNetwork(api, force: false)
        } else {
            // The engine coalesces concurrent refreshes and backs off after
            // failures; newer TLEs re-run the pass list.
            Task { [weak self] in
                guard let self else {
                    return
                }
                let before = tlesFetchedAt
                await refreshFromNetwork(api, force: false)
                if tlesFetchedAt != before {
                    await refreshUpcoming()
                }
            }
        }
    }

    /// Cache-through engine refresh; a failure only surfaces with nothing on
    /// screen (otherwise the engine has already degraded to the cache).
    private func refreshFromNetwork(_ api: SatelliteApi, force: Bool) async {
        do {
            let summary = try await api.refresh(force: force)
            await applyCatalog(from: api, summary: summary)
        } catch {
            logger.error("satellite catalog load failed: \(error.localizedDescription)")
            if satellites.isEmpty {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func applyCatalog(from api: SatelliteApi, summary: FfiSatelliteRefreshSummary) async {
        let catalog = await Task.detached(priority: .userInitiated) { api.catalog() }.value
        satellites = Dictionary(
            catalog.map { (Int($0.noradId), SweepSatellite(summary: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
        tlesFetchedAt = Date(timeIntervalSince1970: TimeInterval(summary.tlesFetchedAtEpoch))
        tlesStale = summary.tlesStale
        state = .loaded
    }

    private func refreshObserver() {
        let grid = UserDefaults.standard.string(forKey: "myGrid")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !grid.isEmpty, let coordinate = MaidenheadConverter.coordinate(from: grid) else {
            observerGrid = nil
            observer = nil
            return
        }
        observerGrid = grid.uppercased()
        observer = FfiObserver(latDeg: coordinate.latitude, lonDeg: coordinate.longitude)
    }

    private func tick(includeAltitude: Bool) async {
        let now = Date()
        // Advance past a finished pass after a short grace period.
        if autoAdvance, let pass = selectedPass, now.timeIntervalSince(pass.los) > 20 {
            if let next = upcoming.first(where: { $0.los > now && $0.id != pass.id }) {
                select(next)
            }
        }
        guard let api = try? await SweepSatelliteEngine.api() else {
            return
        }
        var look: SatelliteLiveLook?
        if let pass = selectedPass, let observer {
            let norad = UInt32(pass.noradID)
            let epoch = Int64(now.timeIntervalSince1970)
            let ffiLook = await Task.detached(priority: .userInitiated) {
                api.look(noradId: norad, epochSecs: epoch, observer: observer)
            }.value
            if includeAltitude || lastAltitudeKm == nil {
                let positions = await Task.detached(priority: .utility) {
                    api.positions(epochSecs: epoch, observer: observer)
                }.value
                lastAltitudeKm = positions.first { $0.noradId == norad }?.altKm
            }
            if let ffiLook {
                look = SatelliteLiveLook(
                    at: now,
                    azimuthDeg: ffiLook.azimuthDeg,
                    elevationDeg: ffiLook.elevationDeg,
                    rangeKm: ffiLook.rangeKm,
                    rangeRateKmPerSec: ffiLook.rangeRateKmPerSec,
                    azRateDegPerSec: ffiLook.azRateDegPerSec,
                    elRateDegPerSec: ffiLook.elRateDegPerSec,
                    altitudeKm: lastAltitudeKm
                )
                if pass.isActive(at: now), ffiLook.elevationDeg >= 0 {
                    flown.append(SkyTrackPoint(
                        time: now, azimuthDeg: ffiLook.azimuthDeg, elevationDeg: ffiLook.elevationDeg
                    ))
                }
            }
        }
        frame = buildFrame(now: now, look: look)
        await cat.apply(frame: frame, radioManager: radioManager)
        await steerRotator(frame: frame)
    }

    private func buildFrame(now: Date, look: SatelliteLiveLook?) -> SatellitePassFrame {
        var next = SatellitePassFrame(now: now)
        next.pass = selectedPass
        next.satellite = selectedSatellite
        next.look = look
        next.predictedTrack = predicted
        next.flownTrack = flown
        let downlink = radioManager.slotStates[cat.downlinkSlot]
        next.isTransmitting = downlink?.isTransmitting ?? radioManager.isTransmitting
        if radioManager.isConnected, let rigMHz = downlink?.frequency ?? Optional(radioManager.frequency), rigMHz > 0 {
            next.rigFrequencyHz = rigMHz * 1_000_000
        }
        next.isDuplexCAT = cat.isEnabled && cat.isDuplex
        if let satellite = selectedSatellite {
            next.toneHz = Self.tonesHz[satellite.noradID]
            if let transmitter = SweepTransmitter.primary(in: satellite.transmitters) {
                next.transmitter = transmitter
                next.doppler = SatelliteDopplerReadout(
                    transmitter: transmitter,
                    rangeRateKmPerSec: look?.rangeRateKmPerSec ?? 0,
                    dialOffsetHz: cat.dialOffsetHz
                )
            }
        }
        if let look, look.isAboveHorizon {
            next.signalStrength = SatelliteWaterfallSynth.strength(rangeKm: look.rangeKm)
        }
        return next
    }

    /// Follow the satellite while it is up; pre-position to the AOS azimuth
    /// in the last minutes before the pass.
    private func steerRotator(frame: SatellitePassFrame) async {
        guard rotator.isConnected else {
            return
        }
        if let look = frame.look, look.isAboveHorizon {
            await rotator.setTarget(RotatorPosition(azimuthDeg: look.azimuthDeg, elevationDeg: look.elevationDeg))
        } else if let pass = frame.pass, let toAOS = frame.secondsToAOS, toAOS <= Self.prePositionLead {
            await rotator.setTarget(RotatorPosition(azimuthDeg: pass.aosAzimuthDeg, elevationDeg: 0))
        }
    }

    /// Predicted sky track for a pass: 30 s samples from the engine's
    /// forward ground track anchored just before AOS, clipped to the pass.
    private func rebuildTrack(for pass: SweepPass) async {
        guard let observer, let api = try? await SweepSatelliteEngine.api() else {
            return
        }
        let start = pass.aos.addingTimeInterval(-30)
        let norad = UInt32(pass.noradID)
        let epoch = Int64(start.timeIntervalSince1970)
        let samples = await Task.detached(priority: .userInitiated) {
            api.groundTrack(noradId: norad, epochSecs: epoch, observer: observer)
        }.value
        var points: [SkyTrackPoint] = []
        for (index, sample) in samples.enumerated() {
            let time = start.addingTimeInterval(Double(index) * 30)
            guard time <= pass.los.addingTimeInterval(30),
                  let az = sample.azimuthDeg, let el = sample.elevationDeg, el >= -0.5
            else {
                continue
            }
            points.append(SkyTrackPoint(time: time, azimuthDeg: az, elevationDeg: el))
        }
        guard selectedPass?.id == pass.id else {
            return
        }
        predicted = points
    }
}
