import CarrierWaveCore
import CoreLocation
import UIKit

// MARK: - SatellitePosition

/// A satellite's geodetic position at a moment in time, plus its ground
/// velocity so the map can interpolate motion between propagation syncs.
nonisolated struct SatellitePosition: Identifiable, Sendable, Equatable {
    let noradID: Int
    /// Short display name (OSCAR designator when derivable).
    let name: String
    /// De-emphasized long mission name, when it differs from `name`.
    var detailName: String?
    let latitude: Double
    let longitude: Double
    let altitudeKm: Double
    var latRateDegPerSec = 0.0
    var lonRateDegPerSec = 0.0
    /// Observer-relative sky position, present when an observer location is
    /// known. Rates support frame interpolation in the sky dome.
    var azimuthDeg: Double?
    var elevationDeg: Double?
    var rangeKm: Double?
    var azRateDegPerSec = 0.0
    var elRateDegPerSec = 0.0
    /// Slant-range rate (km/s, positive = receding) for Doppler correction.
    var rangeRateKmPerSec = 0.0

    var isAboveHorizon: Bool {
        (elevationDeg ?? -90) > 0
    }

    var id: Int {
        noradID
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Ground-coverage (footprint) radius in meters: the great-circle
    /// distance from the subsatellite point to the 0° elevation horizon.
    var coverageRadiusMeters: Double {
        let earthRadius = 6_371_000.0
        let orbitRadius = earthRadius + altitudeKm * 1_000
        guard orbitRadius > earthRadius else {
            return 0
        }
        return earthRadius * acos(earthRadius / orbitRadius)
    }
}

nonisolated extension SatellitePosition {
    /// Bridge from the shared Rust engine's position record.
    init(ffi: FfiSatellitePosition) {
        self.init(
            noradID: Int(ffi.noradId),
            name: ffi.name,
            detailName: ffi.detailName,
            latitude: ffi.latDeg,
            longitude: ffi.lonDeg,
            altitudeKm: ffi.altKm
        )
        latRateDegPerSec = ffi.latRateDegPerSec
        lonRateDegPerSec = ffi.lonRateDegPerSec
        azimuthDeg = ffi.azimuthDeg
        elevationDeg = ffi.elevationDeg
        rangeKm = ffi.rangeKm
        azRateDegPerSec = ffi.azRateDegPerSec
        elRateDegPerSec = ffi.elRateDegPerSec
        rangeRateKmPerSec = ffi.rangeRateKmPerSec
    }
}

// MARK: - SatelliteLook

/// Where a satellite sits in the observer's sky.
nonisolated struct SatelliteLook: Sendable, Equatable {
    let azimuthDeg: Double
    let elevationDeg: Double
    let rangeKm: Double

    var isAboveHorizon: Bool {
        elevationDeg > 0
    }
}

// MARK: - SatelliteModeCategory

/// Operator-facing buckets for SatNOGS transmitter mode strings, for
/// filtering satellites by what you can actually work through them.
nonisolated enum SatelliteModeCategory: String, CaseIterable, Sendable, Identifiable {
    case voiceFM = "FM"
    case linear = "SSB"
    case morse = "CW"
    case digital = "DIGI"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        rawValue
    }

    /// Bucket a raw SatNOGS mode string (e.g. "FM", "USB", "AFSK1k2",
    /// "GMSK", "SSTV"). Anything that isn't voice or CW counts as digital.
    static func category(for mode: String?) -> SatelliteModeCategory {
        guard let mode = mode?.uppercased(), !mode.isEmpty else {
            return .digital
        }
        if mode.hasPrefix("FM") {
            return .voiceFM
        }
        let ssbMarkers = ["SSB", "USB", "LSB", "TRANSPONDER", "LINEAR"]
        if ssbMarkers.contains(where: { mode.contains($0) }) {
            return .linear
        }
        if mode.hasPrefix("CW") {
            return .morse
        }
        return .digital
    }

    /// Bucket a whole transmitter: the mode string decides, but a
    /// transponder whose mode didn't parse as voice/CW is a linear bird
    /// (SatNOGS records some linear transponders with sparse mode fields).
    static func category(for transmitter: SatNOGSTransmitter) -> SatelliteModeCategory {
        let byMode = category(for: transmitter.mode)
        if byMode == .digital, transmitter.type.uppercased().contains("TRANSPONDER") {
            return .linear
        }
        return byMode
    }

    /// Persistence helpers for @AppStorage (comma-joined raw values).
    static func decodeSet(_ encoded: String) -> Set<SatelliteModeCategory> {
        Set(encoded.split(separator: ",").compactMap { SatelliteModeCategory(rawValue: String($0)) })
    }

    static func encode(_ set: Set<SatelliteModeCategory>) -> String {
        set.map(\.rawValue).sorted().joined(separator: ",")
    }
}

// MARK: - SatelliteSearchItem

/// Lightweight entry for the satellite search list.
nonisolated struct SatelliteSearchItem: Identifiable, Sendable {
    let noradID: Int
    /// Short display name (OSCAR designator when derivable).
    let name: String
    /// De-emphasized long mission name, when it differs from `name`.
    let detailName: String?

    var id: Int {
        noradID
    }
}

// MARK: - SatNOGSTransmitter

/// One amateur transmitter of a catalog satellite, bridged from the shared
/// Rust engine (which fetches, filters, and orders SatNOGS data).
nonisolated struct SatNOGSTransmitter: Sendable {
    // MARK: Lifecycle

    init(ffi: FfiSatTransmitter) {
        description = ffi.description
        type = ffi.transmitterType
        alive = ffi.alive
        isActive = ffi.isActive
        mode = ffi.mode
        uplinkLow = ffi.uplinkLowHz
        downlinkLow = ffi.downlinkLowHz
        amsatTracked = ffi.amsatTracked
        amsatLastHeardAt = ffi.amsatLastHeardEpoch
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    // MARK: Internal

    let description: String
    let type: String
    let alive: Bool
    let isActive: Bool
    let mode: String?
    let uplinkLow: Int64?
    let downlinkLow: Int64?
    /// AMSAT tracks this transmitter's mode category (untracked = no
    /// heard/silent signal, benefit of the doubt).
    let amsatTracked: Bool
    /// Freshest positive AMSAT report for this capability.
    let amsatLastHeardAt: Date?

    /// Community-confirmed within the last 24 h — the green dot.
    var amsatHeardToday: Bool {
        guard let heard = amsatLastHeardAt else {
            return false
        }
        return heard > Date(timeIntervalSinceNow: -24 * 3_600)
    }
}

// MARK: - AmsatSatelliteStatus

/// Satellite-level AMSAT community summary bridged from the engine's
/// catalog (the engine aggregates the server's amsat-status rows).
nonisolated struct AmsatSatelliteStatus: Sendable, Equatable {
    // MARK: Lifecycle

    /// Nil when the catalog carries no AMSAT signal for the bird.
    init?(summary: FfiSatelliteSummary) {
        guard summary.amsatLastHeardEpoch != nil || summary.amsatTotalReports24h > 0 else {
            return nil
        }
        lastHeardAt = summary.amsatLastHeardEpoch
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
        totalReports24h = Int(summary.amsatTotalReports24h)
        heardReports24h = Int(summary.amsatHeardReports24h)
        lastReport = summary.amsatLastReport
    }

    // MARK: Internal

    let lastHeardAt: Date?
    let totalReports24h: Int
    let heardReports24h: Int
    /// Most recent verdict verbatim ("Heard", "Not Heard", "Telemetry Only", …).
    let lastReport: String?

    /// The bird's last 24 h in AMSAT's legend colours: heard beats
    /// telemetry-only beats not-heard; no reports at all is quiet.
    var dayStatus: CommunityActivityStatus {
        if heardReports24h > 0 {
            return .heard
        }
        guard totalReports24h > 0 else {
            return .quiet
        }
        if lastReport?.lowercased().contains("telemetry") == true {
            return .telemetryOnly
        }
        return .notHeard
    }
}

// MARK: - SatellitePass

/// One horizon-to-horizon pass of a satellite over the observer, with the
/// geometry an operator needs to work it.
nonisolated struct SatellitePass: Identifiable, Sendable, Equatable {
    // MARK: Lifecycle

    init(ffi: FfiSatellitePass) {
        aos = Date(timeIntervalSince1970: TimeInterval(ffi.aosEpoch))
        aosAzimuthDeg = ffi.aosAzimuthDeg
        peak = Date(timeIntervalSince1970: TimeInterval(ffi.peakEpoch))
        peakAzimuthDeg = ffi.peakAzimuthDeg
        peakElevationDeg = ffi.peakElevationDeg
        peakRangeKm = ffi.peakRangeKm
        los = Date(timeIntervalSince1970: TimeInterval(ffi.losEpoch))
        losAzimuthDeg = ffi.losAzimuthDeg
    }

    // MARK: Internal

    let aos: Date
    let aosAzimuthDeg: Double
    let peak: Date
    let peakAzimuthDeg: Double
    let peakElevationDeg: Double
    let peakRangeKm: Double
    let los: Date
    let losAzimuthDeg: Double

    var id: Date {
        aos
    }

    var duration: TimeInterval {
        los.timeIntervalSince(aos)
    }

    func isInProgress(at date: Date) -> Bool {
        date >= aos && date <= los
    }
}

// MARK: - SatellitePassForecast

/// Result of a pass search over a fixed look-ahead window.
nonisolated struct SatellitePassForecast: Sendable, Equatable {
    static let empty = SatellitePassForecast(passes: [], isAlwaysVisible: false)

    let passes: [SatellitePass]
    /// True when the satellite never dropped below the horizon during the
    /// whole search window (e.g. a geostationary bird in view of the QTH).
    let isAlwaysVisible: Bool
}

// MARK: - UpcomingSatellitePass

/// One pass in the cross-satellite "what's next" schedule.
nonisolated struct UpcomingSatellitePass: Identifiable, Sendable, Equatable {
    // MARK: Lifecycle

    init(ffi: FfiUpcomingPass) {
        noradID = Int(ffi.noradId)
        name = ffi.name
        detailName = ffi.detailName
        pass = SatellitePass(ffi: ffi.pass)
    }

    // MARK: Internal

    let noradID: Int
    let name: String
    let detailName: String?
    let pass: SatellitePass

    var id: String {
        "\(noradID)-\(pass.aos.timeIntervalSince1970)"
    }
}

// MARK: - MutualPass

/// A window during which a satellite is above the horizon at BOTH stations
/// simultaneously — the time two operators can work each other through it.
nonisolated struct MutualPass: Identifiable, Sendable, Hashable {
    // MARK: Lifecycle

    init(ffi: FfiMutualPass) {
        noradID = Int(ffi.noradId)
        name = ffi.name
        detailName = ffi.detailName
        start = Date(timeIntervalSince1970: TimeInterval(ffi.startEpoch))
        end = Date(timeIntervalSince1970: TimeInterval(ffi.endEpoch))
        peakDate = Date(timeIntervalSince1970: TimeInterval(ffi.peakEpoch))
        peakMinElevationDeg = ffi.peakMinElevationDeg
        peakElevationADeg = ffi.peakElevationADeg
        peakElevationBDeg = ffi.peakElevationBDeg
        startAzimuthADeg = ffi.startAzimuthADeg
        peakAzimuthADeg = ffi.peakAzimuthADeg
        endAzimuthADeg = ffi.endAzimuthADeg
    }

    // MARK: Internal

    let noradID: Int
    let name: String
    let detailName: String?
    let start: Date
    let end: Date
    /// Moment the limiting (lower) elevation peaks — the best of the window.
    let peakDate: Date
    let peakMinElevationDeg: Double
    let peakElevationADeg: Double
    let peakElevationBDeg: Double
    /// Window geometry from YOUR sky (station A), ° clockwise from north.
    let startAzimuthADeg: Double
    let peakAzimuthADeg: Double
    let endAzimuthADeg: Double

    var id: String {
        "\(noradID)-\(start.timeIntervalSince1970)"
    }

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    func isInProgress(at date: Date) -> Bool {
        date >= start && date <= end
    }
}

// MARK: - MutualPassSample

/// One time-step of a pass for the profile visualization: the satellite's
/// geodetic position plus its elevation from each station.
nonisolated struct MutualPassSample: Sendable, Equatable {
    // MARK: Lifecycle

    init(ffi: FfiMutualSample) {
        date = Date(timeIntervalSince1970: TimeInterval(ffi.epoch))
        latitude = ffi.latDeg
        longitude = ffi.lonDeg
        altitudeKm = ffi.altKm
        elevationADeg = ffi.elevationADeg
        elevationBDeg = ffi.elevationBDeg
    }

    // MARK: Internal

    let date: Date
    let latitude: Double
    let longitude: Double
    let altitudeKm: Double
    let elevationADeg: Double
    let elevationBDeg: Double

    var bothVisible: Bool {
        elevationADeg > 0 && elevationBDeg > 0
    }

    var eitherVisible: Bool {
        elevationADeg > 0 || elevationBDeg > 0
    }
}

nonisolated extension SatelliteModeCategory {
    /// The engine-side mode bucket for pass sweeps.
    var ffi: FfiSatModeCategory {
        switch self {
        case .voiceFM:
            .voiceFm
        case .linear:
            .linear
        case .morse:
            .morse
        case .digital:
            .digital
        }
    }
}
