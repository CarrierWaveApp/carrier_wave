import CarrierWaveCwFfi
import Foundation

// MARK: - SDRInputSettings

/// Persisted configuration for the external SDR waterfall input. The SDR
/// either watches the rig's IF output (Elecraft K3 IF OUT, 8.215 MHz) or an
/// antenna directly; either way CAT state drives the frequency mapping, so
/// the same settings work for any radio + SDR pairing.
struct SDRInputSettings: Codable, Equatable {
    // MARK: Internal

    enum SourceKind: String, Codable, CaseIterable, Identifiable {
        case soapy
        case rtlTcp
        case tone

        // MARK: Internal

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .soapy: "SoapySDR (SDRplay, RTL-SDR, Airspy HF+)"
            case .rtlTcp: "rtl_tcp / rsp_tcp server"
            case .tone: "Test tones (no hardware)"
            }
        }
    }

    enum TuningKind: String, Codable, CaseIterable, Identifiable {
        case ifTap
        case directRF

        // MARK: Internal

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .ifTap: "Radio IF output"
            case .directRF: "Antenna (follow VFO)"
            }
        }
    }

    static let storageKey = "sdrInputSettings"

    /// Elecraft K3/K3S (KXV3) IF output center frequency.
    static let k3IFHz: Double = 8_215_000

    static let sampleRateChoices: [Int] = [192_000, 250_000, 1_024_000, 2_000_000, 2_048_000, 2_400_000]
    static let spanChoicesHz: [Double] = [24_000, 48_000, 96_000, 192_000]

    var enabled = false

    var sourceKind: SourceKind = .soapy
    var soapyArgs = "driver=sdrplay"
    var rtlTcpHost = "127.0.0.1"
    var rtlTcpPort = 1_234
    var sampleRate = 2_000_000
    var autoGain = true
    var gainDB = 30.0
    /// rtl_tcp direct sampling (0 off, 1 I, 2 Q) — Q branch for HF on RTL-SDR.
    var directSampling = 0
    /// Added to every hardware tune, e.g. 125 MHz for an upconverter.
    var deviceOffsetHz = 0.0

    var tuningKind: TuningKind = .ifTap
    var ifHz = SDRInputSettings.k3IFHz
    var ifInverted = true
    /// Parks the SDR's own DC spike away from the signal under the VFO.
    var loOffsetHz = 20_000.0
    /// Receive-frequency offset from `ifHz`, keyed by uppercase CAT mode.
    var calibrationHzByMode: [String: Double] = [:]

    var spanHz = 96_000.0
    var fps = 25.0

    // MARK: FFI conversion

    var ffiDevice: FfiPanadapterDevice {
        FfiPanadapterDevice(
            source: ffiSource,
            sampleRate: UInt32(clamping: sampleRate),
            gainDb: autoGain ? nil : gainDB,
            directSampling: UInt8(clamping: directSampling),
            deviceOffsetHz: deviceOffsetHz
        )
    }

    var ffiTuningMode: FfiTuningMode {
        switch tuningKind {
        case .ifTap:
            .ifTap(ifHz: ifHz, inverted: ifInverted, loOffsetHz: loOffsetHz, calHzByMode: calibrationHzByMode)
        case .directRF:
            .directRf(loOffsetHz: loOffsetHz)
        }
    }

    var ffiDisplay: FfiPanadapterDisplay {
        FfiPanadapterDisplay(
            spanHz: spanHz,
            bins: 1_024,
            fps: fps,
            autoFloor: true,
            floorDb: -110,
            rangeDb: 60
        )
    }

    // MARK: Persistence

    static func load(from defaults: UserDefaults = .standard) -> SDRInputSettings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(SDRInputSettings.self, from: data)
        else {
            return SDRInputSettings()
        }
        return settings
    }

    static func modeKey(_ mode: String) -> String {
        mode.trimmingCharacters(in: .whitespaces).uppercased()
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: Presets

    /// Elecraft K3/K3S with the KXV3 IF output.
    mutating func applyK3Preset() {
        tuningKind = .ifTap
        ifHz = Self.k3IFHz
        ifInverted = true
        loOffsetHz = 20_000
    }

    // MARK: Calibration

    func calibrationHz(forMode mode: String) -> Double {
        calibrationHzByMode[Self.modeKey(mode)] ?? 0
    }

    // MARK: Private

    private var ffiSource: FfiPanadapterSource {
        switch sourceKind {
        case .soapy:
            .soapy(args: soapyArgs)
        case .rtlTcp:
            .rtlTcp(host: rtlTcpHost, port: UInt16(clamping: rtlTcpPort))
        case .tone:
            // Relative to the SDR center: with the IF tap parked at IF + LO
            // offset, `-loOffsetHz` lands exactly under the VFO.
            .tone(offsetsHz: [-loOffsetHz, -loOffsetHz + 1_500, -loOffsetHz - 7_200, -loOffsetHz + 21_000])
        }
    }
}
