import CarrierWaveCwFfi
import Foundation

// MARK: - CIVProtocol

/// CI-V protocol encoding/decoding for Icom/Xiegu radios.
///
/// CI-V frames: `FE FE <to> <from> <cmd> [<sub>] [<data>…] FD`
/// Frequencies are 5-byte BCD (LSB-first, 1 Hz resolution).
///
/// The byte-level wire logic lives in the shared Rust core (`cw_domain::civ`);
/// this is a thin facade delegating to the generated FFI.
public enum CIVProtocol {
    // MARK: - Constants

    /// Preamble byte (two required)
    public static let preamble: UInt8 = 0xFE

    /// End-of-message terminator
    public static let terminator: UInt8 = 0xFD

    /// Controller address (PC / app side)
    public static let controllerAddress: UInt8 = 0xE0

    /// Destination of unsolicited CI-V Transceive frames (`FE FE 00 <radio> …`)
    public static let broadcastAddress: UInt8 = 0x00

    // MARK: - Commands

    /// Read operating frequency
    public static let cmdReadFreq: UInt8 = 0x03

    /// Read operating mode
    public static let cmdReadMode: UInt8 = 0x04

    /// Set operating frequency
    public static let cmdSetFreq: UInt8 = 0x05

    /// Set operating mode
    public static let cmdSetMode: UInt8 = 0x06

    /// Read/set levels (power, mic gain, etc.)
    public static let cmdLevel: UInt8 = 0x14

    /// Sub-command for RF power level under cmdLevel
    public static let subPowerLevel: UInt8 = 0x0A

    // MARK: - Frame Building

    /// Build a CI-V command frame.
    public static func buildFrame(
        to: UInt8,
        from: UInt8 = controllerAddress,
        command: UInt8,
        data: [UInt8] = []
    ) -> [UInt8] {
        [UInt8](civBuildFrame(to: to, from: from, command: command, data: Data(data)))
    }

    // MARK: - Frame Parsing

    /// Extract complete CI-V frames from a byte buffer.
    /// Returns parsed frames and the number of bytes consumed.
    /// Unconsumed bytes should be retained for subsequent calls (streaming reassembly).
    public static func extractFrames(from buffer: [UInt8]) -> (frames: [CIVFrame], consumed: Int) {
        let result = civExtractFrames(buffer: Data(buffer))
        let frames = result.frames.map { ffi in
            CIVFrame(to: ffi.to, from: ffi.from, command: ffi.command, data: [UInt8](ffi.data))
        }
        return (frames, Int(result.consumed))
    }

    /// True when `buffer` holds only complete CI-V Transceive broadcasts
    /// (`to == 00`), the unsolicited freq/mode frames a radio emits on every
    /// change, e.g. ~2/s per band while a satellite tracker drives an IC-9700.
    /// Used to keep that stream out of command logs; replies to us (`to == E0`)
    /// and partial frames still return false.
    public static func isTransceiveBroadcastOnly(_ buffer: [UInt8]) -> Bool {
        let result = extractFrames(from: buffer)
        return !result.frames.isEmpty
            && result.consumed == buffer.count
            && result.frames.allSatisfy { $0.to == broadcastAddress }
    }

    // MARK: - BCD Frequency

    /// Parse a 5-byte BCD frequency (LSB-first) into Hz.
    /// Each byte encodes two BCD digits: low nibble is the less-significant digit.
    public static func parseBCDFrequency(_ data: [UInt8]) -> UInt64? {
        civParseBcdFrequency(data: Data(data))
    }

    /// Encode a frequency in Hz to 5-byte BCD (LSB-first).
    public static func encodeBCDFrequency(_ frequencyHz: UInt64) -> [UInt8] {
        [UInt8](civEncodeBcdFrequency(frequencyHz: frequencyHz))
    }

    /// Convert Hz to MHz as a Double.
    public static func hzToMHz(_ hz: UInt64) -> Double {
        civHzToMhz(hz: hz)
    }

    /// Convert MHz to Hz.
    public static func mhzToHz(_ mhz: Double) -> UInt64 {
        civMhzToHz(mhz: mhz)
    }
}

// MARK: - CIVFrame

/// A parsed CI-V protocol frame.
public struct CIVFrame: Equatable, Sendable {
    // MARK: Lifecycle

    public init(to: UInt8, from: UInt8, command: UInt8, data: [UInt8]) {
        self.to = to
        self.from = from
        self.command = command
        self.data = data
    }

    // MARK: Public

    /// Destination address
    public let to: UInt8

    /// Source address
    public let from: UInt8

    /// Command byte
    public let command: UInt8

    /// Data payload (may be empty)
    public let data: [UInt8]

    /// Whether this is an ACK (command 0xFB, no data)
    public var isAck: Bool {
        civFrameIsAck(command: command)
    }

    /// Whether this is a NAK (command 0xFA, no data)
    public var isNak: Bool {
        civFrameIsNak(command: command)
    }
}

// MARK: - CIVMode

/// CI-V mode byte mapping to Carrier Wave mode strings.
///
/// The wire byte (`rawValue`) is the enum's identity; the canonical mode-string
/// mappings delegate to the shared Rust core.
public enum CIVMode: UInt8, CaseIterable, Sendable {
    case lsb = 0x00
    case usb = 0x01
    case am = 0x02
    case cw = 0x03
    case rtty = 0x04
    case fm = 0x05
    case wfm = 0x06
    case cwR = 0x07
    case rttyR = 0x08

    // MARK: Public

    /// Carrier Wave mode string
    public var carrierWaveMode: String {
        civModeCarrierWaveMode(byte: rawValue) ?? ""
    }

    /// Human-readable display name
    public var displayName: String {
        civModeDisplayName(byte: rawValue) ?? ""
    }

    /// Create from a Carrier Wave mode string.
    /// Returns nil for modes without a CI-V equivalent.
    public static func from(carrierWaveMode: String) -> CIVMode? {
        civModeByteFromCarrierWaveMode(mode: carrierWaveMode).flatMap { CIVMode(rawValue: $0) }
    }
}
