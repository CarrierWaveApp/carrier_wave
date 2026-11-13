import UIKit

// MARK: - SatelliteDuplexController

/// Full-duplex FM satellite tuning across two CW Bridges, one per handheld:
/// the uplink radio and the downlink radio each get a `RadioLink`. Every
/// second the controller takes the tracker's slant-range rate for the
/// selected satellite, computes the Doppler-corrected downlink and uplink
/// from its primary transmitter, and pushes them over CAT.
///
/// Two modes:
/// - `auto`: both radios follow the prediction.
/// - `manualDownlink`: the operator tunes the downlink by ear; the app
///   reads it back, takes the offset from the predicted downlink as the
///   prediction error, and slaves the uplink to the mirrored, frequency-
///   scaled correction. The downlink radio is never commanded.
///
/// Frequencies are rounded to 10 Hz and only re-sent when they move by more
/// than `deadbandHz` — the Quansheng CAT build writes EEPROM on every set.
@MainActor
@Observable
final class SatelliteDuplexController {
    // MARK: Lifecycle

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Keys.mode),
           let stored = TuningMode(rawValue: raw)
        {
            mode = stored
        }
        tonesTenthsHzByNorad = Self.loadTones()
    }

    // MARK: Internal

    enum TuningMode: String, CaseIterable, Identifiable {
        case auto
        case manualDownlink

        // MARK: Internal

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .auto: "Auto"
            case .manualDownlink: "Manual downlink"
            }
        }

        var detail: String {
            switch self {
            case .auto: "Both radios follow the pass prediction."
            case .manualDownlink: "Tune the downlink by ear; the uplink follows your correction."
            }
        }
    }

    /// Live readout for the UI.
    struct Readout: Equatable {
        var satelliteName: String?
        var transmitterDescription: String?
        var predictedDownlinkHz: UInt64?
        var predictedUplinkHz: UInt64?
        var commandedDownlinkHz: UInt64?
        var commandedUplinkHz: UInt64?
        /// Operator's offset from the predicted downlink (manual mode).
        var manualOffsetHz: Int64?
        var dopplerShiftHz: Int64?
        var lastTickAt: Date?
    }

    static let shared = SatelliteDuplexController()

    static let lightSpeedKmPerSec = 299_792.458

    let uplink = RadioLink(keyPrefix: "satDuplex.uplink", label: "Uplink")
    let downlink = RadioLink(keyPrefix: "satDuplex.downlink", label: "Downlink")

    private(set) var isTuning = false
    private(set) var readout = Readout()
    private(set) var statusMessage: String?

    /// Uplink CTCSS in tenths of Hz keyed by NORAD ID (e.g. SO-50 → 670).
    private(set) var tonesTenthsHzByNorad: [Int: Int]

    var mode: TuningMode = .auto {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode) }
    }

    var hasBothRadios: Bool {
        uplink.isConfigured && downlink.isConfigured
    }

    // MARK: - Shared tuning math

    /// The transmitter the pointing screen and this controller both tune:
    /// the first active one with a downlink, else any with a downlink.
    static func primaryTransmitter(in transmitters: [SatNOGSTransmitter]) -> SatNOGSTransmitter? {
        transmitters.first { $0.isActive && $0.downlinkLow != nil }
            ?? transmitters.first { $0.downlinkLow != nil }
    }

    /// Doppler factor from the propagated slant-range rate (positive when
    /// approaching): downlink × (1 + f), uplink × (1 − f).
    static func dopplerFactor(rangeRateKmPerSec: Double) -> Double {
        -rangeRateKmPerSec / lightSpeedKmPerSec
    }

    static func roundTo10Hz(_ hz: Double) -> UInt64 {
        UInt64(max(0, (hz / 10).rounded()) * 10)
    }

    /// Uplink tone for a satellite, falling back to the built-in defaults.
    func toneTenthsHz(for noradID: Int) -> Int? {
        tonesTenthsHzByNorad[noradID] ?? Self.defaultTonesTenthsHz[noradID]
    }

    func setTone(tenthsHz: Int?, for noradID: Int) {
        if let tenthsHz, tenthsHz > 0 {
            tonesTenthsHzByNorad[noradID] = tenthsHz
        } else {
            tonesTenthsHzByNorad[noradID] = 0
        }
        Self.saveTones(tonesTenthsHzByNorad)
    }

    /// Connect both configured bridges (no-op for unconfigured ones).
    func connectRadios() {
        uplink.connect()
        downlink.connect()
    }

    func disconnectRadios() {
        stop()
        uplink.disconnect()
        downlink.disconnect()
    }

    /// Exchange the uplink and downlink bridge bindings.
    func swapRoles() {
        let wasTuning = isTuning
        stop()
        let upUUID = uplink.savedDeviceUUID
        let upName = uplink.savedDeviceName
        let downUUID = downlink.savedDeviceUUID
        let downName = downlink.savedDeviceName
        uplink.adopt(deviceUUID: downUUID, deviceName: downName)
        downlink.adopt(deviceUUID: upUUID, deviceName: upName)
        connectRadios()
        if wasTuning, let model = trackerModel {
            start(model: model)
        }
    }

    /// Begin the tuning loop against the tracker's selected satellite.
    func start(model: SatelliteTrackerModel) {
        stop()
        trackerModel = model
        isTuning = true
        statusMessage = nil
        lastCommandedDownlinkHz = nil
        lastCommandedUplinkHz = nil
        connectRadios()
        tickTask = Task {
            await self.prepareRadios()
            while !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        isTuning = false
        preparedForNorad = nil
    }

    // MARK: Private

    private enum Keys {
        static let mode = "satDuplex.mode"
        static let tones = "satDuplex.tonesTenthsHz"
    }

    /// Built-in uplink tones for the common FM birds (tenths of Hz).
    private static let defaultTonesTenthsHz: [Int: Int] = [
        27_607: 670, // SO-50
        25_544: 670, // ISS cross-band repeater
        43_017: 670, // AO-91
        43_137: 670, // AO-92
        44_909: 1_413, // PO-101
    ]

    private static let deadbandHz: UInt64 = 100

    private var trackerModel: SatelliteTrackerModel?
    private var tickTask: Task<Void, Never>?
    private var lastCommandedDownlinkHz: UInt64?
    private var lastCommandedUplinkHz: UInt64?
    private var preparedForNorad: Int?

    private static func loadTones() -> [Int: Int] {
        guard let data = UserDefaults.standard.data(forKey: Keys.tones),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            return [:]
        }
        var result: [Int: Int] = [:]
        for (key, value) in decoded {
            if let norad = Int(key) {
                result[norad] = value
            }
        }
        return result
    }

    private static func saveTones(_ tones: [Int: Int]) {
        var encoded: [String: Int] = [:]
        for (key, value) in tones {
            encoded[String(key)] = value
        }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: Keys.tones)
        }
    }

    /// Put both radios in FM and program the uplink tone once per satellite.
    private func prepareRadios() async {
        guard let model = trackerModel, let position = model.selectedPosition else {
            return
        }
        guard preparedForNorad != position.noradID else {
            return
        }
        var readyCount = 0
        if downlink.isRadioReady {
            await downlink.setMode("FM")
            readyCount += 1
        }
        if uplink.isRadioReady {
            await uplink.setMode("FM")
            if let tenths = toneTenthsHz(for: position.noradID), tenths > 0 {
                await uplink.sendRawCAT(String(format: "CT%04d;", tenths))
            } else {
                await uplink.sendRawCAT("OF;")
            }
            readyCount += 1
        }
        if readyCount == 2 {
            preparedForNorad = position.noradID
        }
    }

    private func tick() async {
        guard let model = trackerModel else {
            return
        }
        if Date().timeIntervalSince(model.positionsSyncedAt) > 4 {
            await model.refreshPositions()
        }
        guard let position = model.selectedPosition else {
            statusMessage = "No satellite selected"
            return
        }
        guard let primary = Self.primaryTransmitter(in: model.transmitters(for: position.noradID)),
              let downlinkHz = primary.downlinkLow
        else {
            statusMessage = "No transmitter frequencies for \(position.name)"
            return
        }
        if preparedForNorad != position.noradID {
            await prepareRadios()
        }
        statusMessage = position.isAboveHorizon ? nil : "\(position.name) is below the horizon"

        let factor = Self.dopplerFactor(rangeRateKmPerSec: position.rangeRateKmPerSec)
        let predictedDownlink = Double(downlinkHz) * (1 + factor)
        let predictedUplink = primary.uplinkLow.map { Double($0) * (1 - factor) }

        var next = readout
        next.satelliteName = position.name
        next.transmitterDescription = primary.description
        next.predictedDownlinkHz = Self.roundTo10Hz(predictedDownlink)
        next.predictedUplinkHz = predictedUplink.map(Self.roundTo10Hz)
        next.dopplerShiftHz = Int64((Double(downlinkHz) * factor).rounded())
        next.lastTickAt = Date()

        let offsetHz = await steerDownlink(predicted: predictedDownlink, into: &next)
        if let predictedUplink, let uplinkHz = primary.uplinkLow {
            // Mirror the operator's downlink correction, scaled by the
            // frequency ratio, since Doppler is proportional to frequency.
            let scaled = offsetHz * Double(uplinkHz) / Double(downlinkHz)
            let target = Self.roundTo10Hz(predictedUplink - scaled)
            lastCommandedUplinkHz = await command(target, on: uplink, last: lastCommandedUplinkHz)
            next.commandedUplinkHz = lastCommandedUplinkHz
        }
        readout = next
    }

    /// Auto mode commands the downlink; manual mode reads it back and
    /// returns the operator's offset from the prediction in Hz.
    private func steerDownlink(predicted predictedDownlink: Double, into next: inout Readout) async -> Double {
        switch mode {
        case .auto:
            let target = Self.roundTo10Hz(predictedDownlink)
            lastCommandedDownlinkHz = await command(target, on: downlink, last: lastCommandedDownlinkHz)
            next.commandedDownlinkHz = lastCommandedDownlinkHz
            next.manualOffsetHz = nil
            return 0
        case .manualDownlink:
            next.commandedDownlinkHz = nil
            guard let tunedMHz = downlink.frequencyMHz, downlink.isRadioReady else {
                next.manualOffsetHz = nil
                return 0
            }
            let offsetHz = tunedMHz * 1_000_000 - predictedDownlink
            next.manualOffsetHz = Int64(offsetHz.rounded())
            return offsetHz
        }
    }

    /// Send `targetHz` when it moved past the deadband and the link is
    /// ready. Returns the frequency the radio is now known to hold (the
    /// previous one inside the deadband, the new one after a verified set,
    /// nil when the link isn't ready or the set failed).
    private func command(_ targetHz: UInt64, on link: RadioLink, last: UInt64?) async -> UInt64? {
        guard link.isRadioReady else {
            return nil
        }
        if let last, abs(Int64(targetHz) - Int64(last)) < Int64(Self.deadbandHz) {
            return last
        }
        return await link.setFrequency(hz: targetHz) ? targetHz : nil
    }
}
