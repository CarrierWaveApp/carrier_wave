import CarrierWaveData
import UIKit

// MARK: - SatelliteRotatorService

/// Drives a LAN rotator (CSN S.A.T., WA4MCM PSR-100, Hamlib `rotctld`) from
/// the tracker's selected satellite. Owns the app's one
/// `TrackerDiscoveryService` (LAN sweep) and one `RotatorController` (link +
/// follow mode), plus the 1 s feed loop that turns the selected satellite's
/// live az/el into rotator targets. Below the horizon it pre-positions to the
/// next pass's rise azimuth at the horizon once AOS is within five minutes,
/// so the antenna is already waiting when the bird comes up.
///
/// Follow mode stays explicit on the controller: the loop feeds targets
/// whenever a rotator is linked, but the antenna only moves after the
/// operator turns Follow on (`RotatorController.startFollowing()`).
@MainActor
@Observable
final class SatelliteRotatorService {
    // MARK: Lifecycle

    private init() {
        autoDetect = TrackerAutoDetector(discovery: discovery, rotator: rotator)
    }

    // MARK: Internal

    static let shared = SatelliteRotatorService()

    /// Pre-position to the rise azimuth this long before AOS.
    static let prePositionLeadSeconds: TimeInterval = 5 * 60

    let discovery = TrackerDiscoveryService()
    let rotator = RotatorController()
    /// Hands-free detection: sweeps on start / network change, re-links the
    /// remembered unit, and raises `pending` ("S.A.T. detected — Connect?").
    let autoDetect: TrackerAutoDetector

    /// The feed loop is running (a tracker model is attached).
    private(set) var isRunning = false

    /// What Follow would send right now: the selected satellite's live az/el
    /// while it is up, or the rise azimuth at the horizon in the last five
    /// minutes before AOS. Computed every second whether or not a rotator is
    /// linked, so the sheet can show it ahead of time.
    private(set) var desiredTarget: RotatorPosition?
    /// Where `desiredTarget` comes from ("ISS · above horizon", "AO-91 · AOS
    /// in 3 min, waiting at rise azimuth") or why there is none.
    private(set) var desiredTargetSource = "Select a satellite"

    /// Targets are being fed and the rotator is in follow mode — the antenna
    /// is actually moving with the satellite.
    var isFollowing: Bool {
        isRunning && rotator.isFollowing
    }

    /// One-line caption: "S.A.T. · tracking · 214° / 38°".
    var statusLine: String {
        guard let endpoint = rotator.endpoint else {
            return "No rotator"
        }
        var parts = [endpoint.kind.shortLabel, rotator.state.label.lowercased()]
        if let position = rotator.position ?? rotator.target {
            parts.append(String(format: "%03.0f° / %.0f°", position.azimuthDeg, position.elevationDeg))
        }
        return parts.joined(separator: " · ")
    }

    /// Reconnect to the remembered rotator, once per launch.
    func connectSavedIfNeeded() async {
        guard !connectSavedAttempted else {
            return
        }
        connectSavedAttempted = true
        await rotator.connectSaved()
    }

    /// Begin background detection while the satellite feature is on screen;
    /// a remembered unit re-links by itself and starts the feed loop.
    func startDetection(model: SatelliteTrackerModel) {
        autoDetect.start()
        // The feed loop always runs with a model attached: it computes the
        // desired target for the UI and pushes it only while a rotator is
        // linked (and only moves the antenna while Follow is on).
        if !isRunning || trackerModel !== model {
            start(model: model)
        }
    }

    func stopDetection() {
        autoDetect.stop()
    }

    /// Operator tapped Connect on the detection prompt.
    func acceptDetected(model: SatelliteTrackerModel) async {
        await autoDetect.accept()
        if rotator.isConnected {
            start(model: model)
        }
    }

    /// Link a unit and, once linked, start feeding it targets.
    func connect(to endpoint: TrackerEndpoint, model: SatelliteTrackerModel) async {
        await rotator.connect(to: endpoint)
        if rotator.isConnected {
            start(model: model)
        }
    }

    func disconnect() async {
        stop()
        await rotator.disconnect()
    }

    /// Begin the 1 s target feed against the tracker's selected satellite.
    func start(model: SatelliteTrackerModel) {
        stop()
        trackerModel = model
        isRunning = true
        loopTask = Task {
            while !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        isRunning = false
        forecast = .empty
        forecastNorad = nil
    }

    // MARK: Private

    /// Re-fetch the pass forecast when older than this (seconds).
    private static let forecastMaxAge: TimeInterval = 60

    private var trackerModel: SatelliteTrackerModel?
    private var loopTask: Task<Void, Never>?
    private var connectSavedAttempted = false
    private var forecast = SatellitePassForecast.empty
    private var forecastNorad: Int?
    private var forecastFetchedAt = Date.distantPast

    private func tick() async {
        guard let model = trackerModel else {
            return
        }
        if Date().timeIntervalSince(model.positionsSyncedAt) > 4 {
            await model.refreshPositions()
        }
        guard let position = model.selectedPosition else {
            await publish(nil, source: "Select a satellite")
            return
        }
        if position.isAboveHorizon, let azimuth = position.azimuthDeg, let elevation = position.elevationDeg {
            await publish(
                RotatorPosition(azimuthDeg: azimuth, elevationDeg: elevation),
                source: "\(position.name) · above horizon"
            )
            return
        }
        // Below the horizon: wait at the rise point once AOS is close.
        guard let next = await nextPass(for: position.noradID, model: model) else {
            await publish(nil, source: "\(position.name) · no pass predicted")
            return
        }
        let minutes = max(0, Int(next.aos.timeIntervalSinceNow / 60))
        guard next.aos.timeIntervalSinceNow <= Self.prePositionLeadSeconds else {
            await publish(nil, source: "\(position.name) · below horizon, AOS in \(minutes) min")
            return
        }
        await publish(
            RotatorPosition(azimuthDeg: next.aosAzimuthDeg, elevationDeg: 0),
            source: "\(position.name) · AOS in \(minutes) min, waiting at rise azimuth"
        )
    }

    /// Record the desired target for the UI and hand it to the rotator when
    /// one is linked (it moves only while Follow is on).
    private func publish(_ target: RotatorPosition?, source: String) async {
        desiredTarget = target
        desiredTargetSource = source
        guard rotator.isConnected else {
            return
        }
        if let target {
            await rotator.setTarget(target)
        } else {
            rotator.clearTarget()
        }
    }

    /// The selected satellite's next (or in-progress) pass, from a forecast
    /// cached per satellite and refreshed once a minute.
    private func nextPass(for noradID: Int, model: SatelliteTrackerModel) async -> SatellitePass? {
        let now = Date()
        if forecastNorad != noradID || now.timeIntervalSince(forecastFetchedAt) > Self.forecastMaxAge {
            forecast = await model.passForecast(for: noradID)
            forecastNorad = noradID
            forecastFetchedAt = Date()
        }
        return forecast.passes.first { $0.los > now }
    }
}

// MARK: - TrackerKind + shortLabel

extension TrackerKind {
    /// Compact label for captions and pickers: "S.A.T.", "PSR-100", "rotctld".
    var shortLabel: String {
        switch self {
        case .csnSAT: "S.A.T."
        case .psr100: "PSR-100"
        case .hamlibRotctld: "rotctld"
        }
    }
}
