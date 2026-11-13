import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - SatelliteModeKind

/// Operator-facing transponder mode bucket, driving signal width and the
/// mode line. Bridged from the engine's category.
enum SatelliteModeKind: String, Sendable, CaseIterable {
    case fm = "FM"
    case ssb = "SSB"
    case cw = "CW"
    case digital = "DIGI"

    // MARK: Lifecycle

    init(ffi: FfiSatModeCategory) {
        switch ffi {
        case .voiceFm: self = .fm
        case .linear: self = .ssb
        case .morse: self = .cw
        case .digital: self = .digital
        }
    }

    // MARK: Internal

    /// CAT mode string for the downlink (RX) side.
    var radioMode: String {
        switch self {
        case .fm: "FM"
        case .ssb: "USB"
        case .cw: "CW"
        case .digital: "USB"
        }
    }

    /// CAT mode string for the uplink (TX) side. Linear birds are worked
    /// USB on the downlink and LSB on the uplink by convention.
    var uplinkRadioMode: String {
        switch self {
        case .fm: "FM"
        case .ssb: "LSB"
        case .cw: "CW"
        case .digital: "USB"
        }
    }
}

// MARK: - SweepTransmitter

/// One amateur transmitter / transponder of a satellite (from SatNOGS via
/// the Rust engine).
struct SweepTransmitter: Sendable, Equatable, Identifiable {
    // MARK: Lifecycle

    init(ffi: FfiSatTransmitter) {
        description = ffi.description
        type = ffi.transmitterType
        alive = ffi.alive
        isActive = ffi.isActive
        mode = ffi.mode
        kind = SatelliteModeKind(ffi: ffi.modeCategory)
        uplinkHz = ffi.uplinkLowHz.map(Double.init)
        downlinkHz = ffi.downlinkLowHz.map(Double.init)
        uplinkHighHz = ffi.uplinkHighHz.map(Double.init)
        downlinkHighHz = ffi.downlinkHighHz.map(Double.init)
        invert = ffi.invert
    }

    init(
        description: String,
        type: String,
        alive: Bool = true,
        isActive: Bool = true,
        mode: String?,
        kind: SatelliteModeKind,
        uplinkHz: Double?,
        downlinkHz: Double?,
        uplinkHighHz: Double? = nil,
        downlinkHighHz: Double? = nil,
        invert: Bool = false
    ) {
        self.description = description
        self.type = type
        self.alive = alive
        self.isActive = isActive
        self.mode = mode
        self.kind = kind
        self.uplinkHz = uplinkHz
        self.downlinkHz = downlinkHz
        self.uplinkHighHz = uplinkHighHz
        self.downlinkHighHz = downlinkHighHz
        self.invert = invert
    }

    // MARK: Internal

    let description: String
    let type: String
    let alive: Bool
    let isActive: Bool
    let mode: String?
    let kind: SatelliteModeKind
    let uplinkHz: Double?
    let downlinkHz: Double?
    /// Upper passband edges (linear transponders only).
    let uplinkHighHz: Double?
    let downlinkHighHz: Double?
    /// Inverting transponder: dial up on the downlink = dial down on the uplink.
    let invert: Bool

    /// Width of the downlink passband in Hz, nil for single-channel birds.
    var downlinkPassbandHz: Double? {
        guard let downlinkHz, let downlinkHighHz, downlinkHighHz > downlinkHz else {
            return nil
        }
        return downlinkHighHz - downlinkHz
    }

    /// Linear transponders let the operator pick a spot in the passband;
    /// FM channels and beacons do not.
    var supportsDialFollowing: Bool {
        kind != .fm && uplinkHz != nil && downlinkHz != nil
    }

    var id: String {
        "\(description)|\(downlinkHz ?? 0)|\(uplinkHz ?? 0)"
    }

    /// e.g. "FM cross-band repeater" — the SatNOGS description already reads
    /// this way for most birds; fall back to mode + type.
    var modeLine: String {
        if !description.isEmpty {
            return description
        }
        return [mode, type].compactMap { $0 }.joined(separator: " ")
    }

    /// The transmitter the pass view tunes: first active one with a
    /// downlink, else any with a downlink (mirrors the iOS duplex rule).
    static func primary(in transmitters: [SweepTransmitter]) -> SweepTransmitter? {
        transmitters.first { $0.isActive && $0.downlinkHz != nil }
            ?? transmitters.first { $0.downlinkHz != nil }
    }
}

// MARK: - SweepSatellite

struct SweepSatellite: Sendable, Identifiable, Equatable {
    // MARK: Lifecycle

    init(summary: FfiSatelliteSummary) {
        noradID = Int(summary.noradId)
        name = summary.name
        detailName = summary.detailName
        transmitters = summary.transmitters.map(SweepTransmitter.init(ffi:))
    }

    init(noradID: Int, name: String, detailName: String? = nil, transmitters: [SweepTransmitter]) {
        self.noradID = noradID
        self.name = name
        self.detailName = detailName
        self.transmitters = transmitters
    }

    // MARK: Internal

    let noradID: Int
    let name: String
    let detailName: String?
    let transmitters: [SweepTransmitter]

    var id: Int {
        noradID
    }

    /// "ISS (ZARYA)" style long name when the catalog has one.
    var displayName: String {
        if let detailName, !detailName.isEmpty, detailName != name {
            return "\(name) (\(detailName))"
        }
        return name
    }
}

// MARK: - SweepPass

/// One predicted pass over the station.
struct SweepPass: Sendable, Identifiable, Equatable, Hashable {
    // MARK: Lifecycle

    init(noradID: Int, name: String, ffi: FfiSatellitePass) {
        self.noradID = noradID
        self.name = name
        aos = Date(timeIntervalSince1970: TimeInterval(ffi.aosEpoch))
        aosAzimuthDeg = ffi.aosAzimuthDeg
        peak = Date(timeIntervalSince1970: TimeInterval(ffi.peakEpoch))
        peakAzimuthDeg = ffi.peakAzimuthDeg
        peakElevationDeg = ffi.peakElevationDeg
        peakRangeKm = ffi.peakRangeKm
        los = Date(timeIntervalSince1970: TimeInterval(ffi.losEpoch))
        losAzimuthDeg = ffi.losAzimuthDeg
    }

    init(
        noradID: Int,
        name: String,
        aos: Date,
        aosAzimuthDeg: Double,
        peak: Date,
        peakAzimuthDeg: Double,
        peakElevationDeg: Double,
        peakRangeKm: Double,
        los: Date,
        losAzimuthDeg: Double
    ) {
        self.noradID = noradID
        self.name = name
        self.aos = aos
        self.aosAzimuthDeg = aosAzimuthDeg
        self.peak = peak
        self.peakAzimuthDeg = peakAzimuthDeg
        self.peakElevationDeg = peakElevationDeg
        self.peakRangeKm = peakRangeKm
        self.los = los
        self.losAzimuthDeg = losAzimuthDeg
    }

    // MARK: Internal

    let noradID: Int
    let name: String
    let aos: Date
    let aosAzimuthDeg: Double
    let peak: Date
    let peakAzimuthDeg: Double
    let peakElevationDeg: Double
    let peakRangeKm: Double
    let los: Date
    let losAzimuthDeg: Double

    var id: String {
        "\(noradID)-\(Int(aos.timeIntervalSince1970))"
    }

    var duration: TimeInterval {
        los.timeIntervalSince(aos)
    }

    /// "m:ss" countdown used in the sidebar and stats row.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    func isActive(at date: Date) -> Bool {
        date >= aos && date <= los
    }

    func isUpcoming(at date: Date) -> Bool {
        date < aos
    }

    /// Seconds until LOS (negative once the pass is over).
    func secondsToLOS(at date: Date) -> TimeInterval {
        los.timeIntervalSince(date)
    }
}

// MARK: - SkyTrackPoint

/// One sample of a pass track in the observer's sky.
struct SkyTrackPoint: Sendable, Equatable {
    let time: Date
    let azimuthDeg: Double
    let elevationDeg: Double
}

// MARK: - SatelliteLiveLook

/// Live look angles + range for the selected satellite.
struct SatelliteLiveLook: Sendable, Equatable {
    let at: Date
    let azimuthDeg: Double
    let elevationDeg: Double
    let rangeKm: Double
    /// km/s, positive = receding.
    let rangeRateKmPerSec: Double
    let azRateDegPerSec: Double
    let elRateDegPerSec: Double
    var altitudeKm: Double?

    var isAboveHorizon: Bool {
        elevationDeg >= 0
    }

    /// Dead-reckon by `dt` seconds for smooth animation between 1 Hz syncs.
    func advanced(by dt: TimeInterval) -> SatelliteLiveLook {
        var az = azimuthDeg + azRateDegPerSec * dt
        az = az.truncatingRemainder(dividingBy: 360)
        if az < 0 {
            az += 360
        }
        return SatelliteLiveLook(
            at: at.addingTimeInterval(dt),
            azimuthDeg: az,
            elevationDeg: elevationDeg + elRateDegPerSec * dt,
            rangeKm: rangeKm + rangeRateKmPerSec * dt,
            rangeRateKmPerSec: rangeRateKmPerSec,
            azRateDegPerSec: azRateDegPerSec,
            elRateDegPerSec: elRateDegPerSec,
            altitudeKm: altitudeKm
        )
    }
}

// MARK: - SatelliteDopplerReadout

/// The pass-detail RX/TX rows.
struct SatelliteDopplerReadout: Sendable, Equatable {
    // MARK: Lifecycle

    /// `dialOffsetHz` is the operator's position inside a linear passband,
    /// relative to the transmitter's low edge; the uplink follows it the
    /// other way on inverting transponders. Zero for FM and beacons.
    init(transmitter: SweepTransmitter, rangeRateKmPerSec: Double, dialOffsetHz: Double = 0) {
        let down = (transmitter.downlinkHz ?? 0) + dialOffsetHz
        nominalDownlinkHz = down
        correctedDownlinkHz = SatelliteDoppler.correctedDownlinkHz(
            nominalHz: down, rangeRateKmPerSec: rangeRateKmPerSec
        )
        downlinkShiftHz = correctedDownlinkHz - down
        self.dialOffsetHz = dialOffsetHz
        isInverting = transmitter.invert
        if let upLow = transmitter.uplinkHz {
            let up = upLow + (transmitter.invert ? -dialOffsetHz : dialOffsetHz)
            nominalUplinkHz = up
            let corrected = SatelliteDoppler.correctedUplinkHz(nominalHz: up, rangeRateKmPerSec: rangeRateKmPerSec)
            correctedUplinkHz = corrected
            uplinkShiftHz = corrected - up
        } else {
            nominalUplinkHz = nil
            correctedUplinkHz = nil
            uplinkShiftHz = nil
        }
    }

    // MARK: Internal

    let nominalDownlinkHz: Double
    let correctedDownlinkHz: Double
    let downlinkShiftHz: Double
    let nominalUplinkHz: Double?
    let correctedUplinkHz: Double?
    let uplinkShiftHz: Double?
    /// Operator's offset into the passband that these numbers include.
    let dialOffsetHz: Double
    let isInverting: Bool
}

// MARK: - SatellitePassFrame

/// Everything the Satellites views render for one tick. Built by
/// `SatellitePassModel`; views never reach back into the engine.
struct SatellitePassFrame: Sendable, Equatable {
    var now: Date
    var satellite: SweepSatellite?
    var pass: SweepPass?
    var look: SatelliteLiveLook?
    var transmitter: SweepTransmitter?
    var doppler: SatelliteDopplerReadout?
    /// Predicted sky track for the pass (AOS→LOS, 30 s samples).
    var predictedTrack: [SkyTrackPoint] = []
    /// Where the satellite has actually been during this pass (1 Hz).
    var flownTrack: [SkyTrackPoint] = []
    /// Uplink CTCSS in Hz when the bird needs one.
    var toneHz: Double?
    var isTransmitting = false
    /// 0…1 synthetic signal strength from range (drives S-meter + waterfall).
    var signalStrength: Double = 0
    /// Frequency the rig reports (Hz), when a CAT link is up.
    var rigFrequencyHz: Double?
    /// True when the CAT controller also drives the uplink (second radio or
    /// the IC-9700 Sub band).
    var isDuplexCAT = false

    var isPassActive: Bool {
        pass?.isActive(at: now) ?? false
    }

    var secondsToLOS: TimeInterval? {
        guard let pass, isPassActive else {
            return nil
        }
        return pass.secondsToLOS(at: now)
    }

    var secondsToAOS: TimeInterval? {
        guard let pass, pass.isUpcoming(at: now) else {
            return nil
        }
        return pass.aos.timeIntervalSince(now)
    }

    /// S-meter reading: S1…S9, then "+dB" above S9.
    var sMeterLabel: String {
        guard look?.isAboveHorizon == true, signalStrength > 0 else {
            return "S0"
        }
        let units = signalStrength * 11 // S9+10 at full scale
        if units <= 9 {
            return "S\(max(1, Int(units.rounded())))"
        }
        return "S9+\(Int(((units - 9) * 5).rounded()))"
    }
}
