import CarrierWaveCore
import CoreLocation
import UIKit

// MARK: - Pass prediction & planner accessors

/// Pass-forecast, all-sky, and mutual-pass entry points over the shared
/// Rust engine, split out of the main model file. The async FFI calls run
/// on the engine's own pool — nothing here blocks the main actor.
extension SatelliteTrackerModel {
    /// Search window and result cap for the pass list UI (mirrors the
    /// engine's `pass_predictor` defaults).
    nonisolated static let passLookAheadHours = 48.0
    nonisolated static let maxForecastPasses: UInt32 = 12

    /// Upcoming horizon passes for a satellite over the observer's QTH,
    /// from the simulated "now". Empty when the observer location or the
    /// satellite is unknown.
    func passForecast(for noradID: Int) async -> SatellitePassForecast {
        guard let observer = ffiObserver(), let api = try? await SatelliteEngine.api() else {
            return .empty
        }
        guard let forecast = try? await api.passForecast(
            noradId: UInt32(noradID),
            observer: observer,
            startEpoch: simulatedEpoch(),
            hours: Self.passLookAheadHours,
            maxPasses: Self.maxForecastPasses
        ) else {
            return .empty
        }
        return SatellitePassForecast(
            passes: forecast.passes.map(SatellitePass.init(ffi:)),
            isAlwaysVisible: forecast.isAlwaysVisible
        )
    }

    /// Every pass of a satellite over the observer between two instants
    /// (past or future — the engine propagates from `from`), ascending.
    /// Used to shade your passes behind the community-activity chart.
    func passes(for noradID: Int, from: Date, to: Date) async -> [SatellitePass] {
        guard let observer = ffiObserver(), let api = try? await SatelliteEngine.api(),
              to > from
        else {
            return []
        }
        let hours = to.timeIntervalSince(from) / 3_600
        guard let forecast = try? await api.passForecast(
            noradId: UInt32(noradID),
            observer: observer,
            startEpoch: Int64(from.timeIntervalSince1970),
            hours: hours,
            maxPasses: 120
        ) else {
            return []
        }
        return forecast.passes.map(SatellitePass.init(ffi:))
    }

    /// Upcoming passes across every satellite carrying an active amateur
    /// transmitter, within the window, sorted by rise time.
    func upcomingPasses(withinHours hours: Double = 6) async -> [UpcomingSatellitePass] {
        guard let observer = ffiObserver(), let api = try? await SatelliteEngine.api() else {
            return []
        }
        let passes = try? await api.upcomingPasses(
            observer: observer,
            startEpoch: simulatedEpoch(),
            hours: hours,
            favorites: []
        )
        return (passes ?? []).map(UpcomingSatellitePass.init(ffi:))
    }

    /// Mutual windows between the observer QTH and a second station, across
    /// all satellites with an active transmitter in one of the requested
    /// mode categories, sorted by start.
    func mutualPasses(
        with other: CLLocationCoordinate2D,
        modes: Set<SatelliteModeCategory> = Set(SatelliteModeCategory.allCases)
    ) async -> [MutualPass] {
        guard let observer = ffiObserver(), let api = try? await SatelliteEngine.api() else {
            return []
        }
        let passes = try? await api.mutualPasses(
            siteA: observer,
            siteB: FfiObserver(latDeg: other.latitude, lonDeg: other.longitude),
            startEpoch: simulatedEpoch(),
            hours: 24,
            categories: modes.map(\.ffi)
        )
        return (passes ?? []).map(MutualPass.init(ffi:))
    }

    /// Fine-grained samples of one mutual pass for the profile view.
    func mutualProfileSamples(
        for pass: MutualPass,
        other: CLLocationCoordinate2D
    ) async -> [MutualPassSample] {
        guard let observer = ffiObserver(), let api = try? await SatelliteEngine.api() else {
            return []
        }
        let samples = try? await api.mutualProfile(
            noradId: UInt32(pass.noradID),
            startEpoch: Int64(pass.start.timeIntervalSince1970),
            endEpoch: Int64(pass.end.timeIntervalSince1970),
            siteA: observer,
            siteB: FfiObserver(latDeg: other.latitude, lonDeg: other.longitude)
        )
        return (samples ?? []).map(MutualPassSample.init(ffi:))
    }
}

// MARK: - SatelliteSkySample

/// One 30 s step of a satellite's path across the observer's sky.
nonisolated struct SatelliteSkySample: Sendable, Equatable {
    let date: Date
    let azimuthDeg: Double
    let elevationDeg: Double
}

// MARK: - Sky arc

extension SatelliteTrackerModel {
    /// The engine's ground-track sampling step.
    nonisolated static let skyArcStep: TimeInterval = 30
    /// How many leading below-horizon samples to skip (AOS rounding) before
    /// giving up — never run on into a later pass.
    nonisolated private static let skyArcLeadIn = 4

    /// The sky path of one above-horizon stretch starting at `start` (a
    /// pass's AOS): 30 s az/el samples from the engine's ground track, cut
    /// at the first horizon crossing. Empty when the observer is unknown or
    /// the bird is not up within 2 min of `start`.
    func skyArc(for noradID: Int, from start: Date) async -> [SatelliteSkySample] {
        guard let observer = ffiObserver(), let api = try? await SatelliteEngine.api() else {
            return []
        }
        let startEpoch = Int64(start.timeIntervalSince1970)
        let track = await Task.detached(priority: .userInitiated) {
            api.groundTrack(noradId: UInt32(noradID), epochSecs: startEpoch, observer: observer)
        }.value
        var samples = [SatelliteSkySample]()
        for (index, point) in track.enumerated() {
            guard let azimuth = point.azimuthDeg, let elevation = point.elevationDeg else {
                continue
            }
            if elevation <= 0 {
                if samples.isEmpty, index < Self.skyArcLeadIn {
                    continue
                }
                break
            }
            samples.append(
                SatelliteSkySample(
                    date: start.addingTimeInterval(Double(index) * Self.skyArcStep),
                    azimuthDeg: azimuth,
                    elevationDeg: elevation
                )
            )
        }
        return samples
    }
}
