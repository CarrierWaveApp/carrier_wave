import Foundation

// MARK: - CIVScopeBand

/// Which receiver a scope frame or command refers to. Single-receiver radios
/// (IC-7300, IC-705) always report `.main`; the IC-9700 reports whichever
/// band its scope is currently streaming.
public enum CIVScopeBand: UInt8, Sendable, Equatable, CaseIterable {
    case main = 0x00
    case sub = 0x01

    // MARK: Public

    public var label: String {
        switch self {
        case .main: "Main"
        case .sub: "Sub"
        }
    }
}

// MARK: - CIVScopeMode

/// Scope display mode byte reported in the first division of a waveform frame.
public enum CIVScopeMode: UInt8, Sendable, Equatable {
    case center = 0x00
    case fixed = 0x01
    case scrollCenter = 0x02
    case scrollFixed = 0x03
}

// MARK: - CIVScopeFrame

/// One `27 00` waveform frame from an Icom radio (IC-7300 / IC-705 / IC-9700
/// family), before reassembly into a full spectrum line.
///
/// Over USB the radio splits a sweep into 11 divisions: division 1 carries
/// only the header (mode, frequencies, out-of-range flag), divisions 2–10
/// carry 50 samples each, and division 11 carries the final 25. Over LAN
/// (RS-BA1) the whole sweep arrives as a single frame with `division == 1`
/// and `divisionMax == 1`. `CIVScopeAccumulator` handles both.
public struct CIVScopeFrame: Sendable, Equatable {
    // MARK: Lifecycle

    /// Parse a scope waveform frame. Returns nil for any other CI-V frame.
    public init?(frame: CIVFrame) {
        guard frame.command == CIVScope.command,
              frame.data.count >= 4,
              frame.data[0] == CIVScope.subWaveformData
        else {
            return nil
        }
        let payload = Array(frame.data.dropFirst())
        guard let band = CIVScopeBand(rawValue: payload[0]) else {
            return nil
        }
        self.band = band
        division = CIVScope.decodeBCDByte(payload[1])
        divisionMax = CIVScope.decodeBCDByte(payload[2])

        if division == 1 {
            // Full header: mode, two 5-byte BCD frequencies, out-of-range flag.
            guard payload.count >= 15 else {
                return nil
            }
            mode = CIVScopeMode(rawValue: payload[3])
            firstFrequencyHz = CIVProtocol.parseBCDFrequency(Array(payload[4 ..< 9]))
            secondFrequencyHz = CIVProtocol.parseBCDFrequency(Array(payload[9 ..< 14]))
            isOutOfRange = payload[14] == 0x01
            samples = Array(payload.dropFirst(15))
        } else {
            mode = nil
            firstFrequencyHz = nil
            secondFrequencyHz = nil
            isOutOfRange = false
            samples = Array(payload.dropFirst(3))
        }
    }

    // MARK: Public

    public let band: CIVScopeBand
    /// 1-based division index within the sweep.
    public let division: Int
    /// Number of divisions per sweep (11 over USB, 1 over LAN).
    public let divisionMax: Int
    /// Present only on division 1.
    public let mode: CIVScopeMode?
    /// Center frequency (center modes) or lower edge (fixed modes). Division 1 only.
    public let firstFrequencyHz: UInt64?
    /// Span half-width (center modes) or upper edge (fixed modes). Division 1 only.
    public let secondFrequencyHz: UInt64?
    /// Radio reports the scope window is outside the current band; no samples follow.
    public let isOutOfRange: Bool
    /// Raw amplitude samples, `0...CIVScope.maxSampleLevel`.
    public let samples: [UInt8]
}

// MARK: - CIVScopeLine

/// A complete reassembled spectrum sweep.
public struct CIVScopeLine: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        band: CIVScopeBand,
        mode: CIVScopeMode?,
        centerHz: UInt64,
        spanHz: UInt64,
        samples: [UInt8]
    ) {
        self.band = band
        self.mode = mode
        self.centerHz = centerHz
        self.spanHz = spanHz
        self.samples = samples
    }

    // MARK: Public

    public let band: CIVScopeBand
    public let mode: CIVScopeMode?
    /// Center of the displayed window in Hz.
    public let centerHz: UInt64
    /// Full width of the displayed window in Hz (edge to edge).
    public let spanHz: UInt64
    /// Raw amplitude samples, `0...CIVScope.maxSampleLevel`, lowest frequency first.
    public let samples: [UInt8]

    public var centerMHz: Double {
        Double(centerHz) / 1_000_000
    }

    public var spanKHz: Double {
        Double(spanHz) / 1_000
    }

    /// Samples normalized to `0...1` where 1 is the strongest signal.
    public var normalizedMagnitudes: [Float] {
        let scale = Float(CIVScope.maxSampleLevel)
        return samples.map { min(1, Float($0) / scale) }
    }
}

// MARK: - CIVScopeAccumulator

/// Reassembles `CIVScopeFrame`s into complete `CIVScopeLine`s, one buffer
/// per band so interleaved Main/Sub frames on an IC-9700 don't corrupt each
/// other.
public struct CIVScopeAccumulator: Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Feed one frame. Returns a full line when the sweep is complete.
    public mutating func ingest(_ frame: CIVScopeFrame) -> CIVScopeLine? {
        if frame.division == 1 {
            guard !frame.isOutOfRange,
                  let geometry = CIVScope.geometry(for: frame)
            else {
                pending[frame.band] = nil
                return nil
            }
            var line = PendingLine(
                mode: frame.mode,
                centerHz: geometry.centerHz,
                spanHz: geometry.spanHz,
                samples: frame.samples,
                divisionMax: frame.divisionMax
            )
            if frame.divisionMax <= 1 {
                pending[frame.band] = nil
                return line.finish(band: frame.band)
            }
            pending[frame.band] = line
            return nil
        }

        guard var line = pending[frame.band] else {
            // Missed the header for this sweep; wait for the next division 1.
            return nil
        }
        line.samples.append(contentsOf: frame.samples)
        if frame.division >= line.divisionMax {
            pending[frame.band] = nil
            return line.finish(band: frame.band)
        }
        pending[frame.band] = line
        return nil
    }

    public mutating func reset() {
        pending.removeAll()
    }

    // MARK: Private

    private struct PendingLine {
        var mode: CIVScopeMode?
        var centerHz: UInt64
        var spanHz: UInt64
        var samples: [UInt8]
        var divisionMax: Int

        mutating func finish(band: CIVScopeBand) -> CIVScopeLine {
            CIVScopeLine(
                band: band, mode: mode, centerHz: centerHz, spanHz: spanHz, samples: samples
            )
        }
    }

    private var pending: [CIVScopeBand: PendingLine] = [:]
}

// MARK: - CIVScope

/// Constants and command encoders for the Icom `0x27` spectrum scope command.
/// Data arrays returned by the encoders are passed to
/// `CIVProtocol.buildFrame(to:command:data:)` with `command: CIVScope.command`.
public enum CIVScope {
    // MARK: Public

    /// Preset spans for center modes, expressed as the ± half-width in Hz
    /// the radio's SPAN menu shows (±2.5 kHz … ±500 kHz).
    public enum Span: UInt64, Sendable, CaseIterable {
        case k2p5 = 2_500
        case k5 = 5_000
        case k10 = 10_000
        case k25 = 25_000
        case k50 = 50_000
        case k100 = 100_000
        case k250 = 250_000
        case k500 = 500_000
    }

    /// Scope command byte.
    public static let command: UInt8 = 0x27
    /// Sub-command carrying waveform data (radio → controller).
    public static let subWaveformData: UInt8 = 0x00
    /// Highest amplitude value the IC-7300 / IC-705 / IC-9700 family reports.
    public static let maxSampleLevel: UInt8 = 0xA0
    /// Bins per sweep on the IC-7300 / IC-705 / IC-9700 family.
    public static let binsPerSweep = 475

    /// `27 10` read — reply is `27 10 00|01`.
    public static let readScopeDisplay: [UInt8] = [0x10]

    /// `27 11` read — reply is `27 11 00|01`.
    public static let readWaveformOutput: [UInt8] = [0x11]

    /// `27 10` — scope display on/off.
    public static func scopeDisplay(on: Bool) -> [UInt8] {
        [0x10, on ? 0x01 : 0x00]
    }

    /// `27 11` — waveform data output to the controller on/off.
    public static func waveformOutput(on: Bool) -> [UInt8] {
        [0x11, on ? 0x01 : 0x00]
    }

    /// Parse the on/off reply to a `27 10` / `27 11` read from `radio`.
    /// Returns nil for anything else, including transceive broadcasts
    /// (`to == 00`) and NG.
    public static func parseOnOffReply(
        _ frame: CIVFrame,
        subcommand: UInt8,
        radio: UInt8
    ) -> Bool? {
        guard frame.command == command,
              frame.to == CIVProtocol.controllerAddress,
              frame.from == radio,
              frame.data.count == 2,
              frame.data[0] == subcommand,
              frame.data[1] <= 0x01
        else {
            return nil
        }
        return frame.data[1] == 0x01
    }

    /// `27 12` — which band's scope is displayed and streamed (IC-9700).
    public static func selectBand(_ band: CIVScopeBand) -> [UInt8] {
        [0x12, band.rawValue]
    }

    /// `27 14` — scope mode for a band.
    public static func setMode(_ mode: CIVScopeMode, band: CIVScopeBand = .main) -> [UInt8] {
        [0x14, band.rawValue, mode.rawValue]
    }

    /// `27 15` — center-mode span for a band.
    public static func setSpan(_ span: Span, band: CIVScopeBand = .main) -> [UInt8] {
        [0x15, band.rawValue] + CIVProtocol.encodeBCDFrequency(span.rawValue)
    }

    // MARK: Internal

    /// Decode a two-digit BCD byte (`0x11` → 11).
    static func decodeBCDByte(_ byte: UInt8) -> Int {
        Int(byte >> 4) * 10 + Int(byte & 0x0F)
    }

    /// Derive center and full span from a division-1 frame.
    static func geometry(for frame: CIVScopeFrame) -> (centerHz: UInt64, spanHz: UInt64)? {
        guard let first = frame.firstFrequencyHz,
              let second = frame.secondFrequencyHz
        else {
            return nil
        }
        switch frame.mode {
        case .fixed,
             .scrollFixed:
            guard second > first else {
                return nil
            }
            return (centerHz: (first + second) / 2, spanHz: second - first)
        case .center,
             .scrollCenter,
             .none:
            // Second field is the ± half-width shown in the radio's SPAN menu.
            return (centerHz: first, spanHz: second * 2)
        }
    }
}

// MARK: - CIVScopeRestorePlan

/// What a client changes in the radio's scope state on connect, and how to
/// put it back on disconnect. Built from `27 10` / `27 11` reads taken before
/// touching anything (nil = the read timed out or got NG).
///
/// Waveform output is always enabled on connect and always turned off on
/// disconnect. The IC-9700 keeps `27 11` per CI-V port (LAN and USB read
/// independently on the bench), and output only goes to the requesting port,
/// so an ON read over LAN is a previous client's leftover (wfview leaves it
/// on), not state worth restoring. Scope display is turned on only when it
/// read OFF, and turned back off on disconnect. An unknown display state is
/// never written: wfview was seen leaving the scope on after disconnect.
public struct CIVScopeRestorePlan: Sendable, Equatable {
    // MARK: Lifecycle

    public init(scopeDisplayOn: Bool?, waveformOutputOn: Bool?) {
        self.scopeDisplayOn = scopeDisplayOn
        self.waveformOutputOn = waveformOutputOn
    }

    // MARK: Public

    /// `27 10` as read on connect.
    public let scopeDisplayOn: Bool?
    /// `27 11` as read on connect.
    public let waveformOutputOn: Bool?

    /// `27` payloads to send on connect, in order.
    public var connectCommands: [[UInt8]] {
        var commands: [[UInt8]] = []
        if scopeDisplayOn == false {
            commands.append(CIVScope.scopeDisplay(on: true))
        }
        commands.append(CIVScope.waveformOutput(on: true))
        return commands
    }

    /// `27` payloads to send on disconnect, in order: output off for this
    /// port, then the display back off if this client turned it on.
    public var disconnectCommands: [[UInt8]] {
        var commands: [[UInt8]] = [CIVScope.waveformOutput(on: false)]
        if scopeDisplayOn == false {
            commands.append(CIVScope.scopeDisplay(on: false))
        }
        return commands
    }
}
