// MARK: - CIVProtocol

/// CI-V protocol encoding/decoding for Icom/Xiegu radios.
///
/// CI-V frames: `FE FE <to> <from> <cmd> [<sub>] [<data>…] FD`
/// Frequencies are 5-byte BCD (LSB-first, 1 Hz resolution).
public enum CIVProtocol {
    // MARK: Public

    // MARK: - Constants

    /// Preamble byte (two required)
    public static let preamble: UInt8 = 0xFE

    /// End-of-message terminator
    public static let terminator: UInt8 = 0xFD

    /// Controller address (PC / app side)
    public static let controllerAddress: UInt8 = 0xE0

    // MARK: - Commands

    /// Read operating frequency
    public static let cmdReadFreq: UInt8 = 0x03

    /// Read operating mode
    public static let cmdReadMode: UInt8 = 0x04

    /// Set operating frequency
    public static let cmdSetFreq: UInt8 = 0x05

    /// Set operating mode
    public static let cmdSetMode: UInt8 = 0x06

    // MARK: - Frame Building

    /// Build a CI-V command frame.
    public static func buildFrame(
        to: UInt8,
        from: UInt8 = controllerAddress,
        command: UInt8,
        data: [UInt8] = []
    ) -> [UInt8] {
        var frame: [UInt8] = [preamble, preamble, to, from, command]
        frame.append(contentsOf: data)
        frame.append(terminator)
        return frame
    }

    // MARK: - Frame Parsing

    /// Extract complete CI-V frames from a byte buffer.
    /// Returns parsed frames and the number of bytes consumed.
    /// Unconsumed bytes should be retained for subsequent calls (streaming reassembly).
    public static func extractFrames(from buffer: [UInt8]) -> (frames: [CIVFrame], consumed: Int) {
        var frames: [CIVFrame] = []
        var consumed = 0
        var pos = 0

        while pos < buffer.count {
            // Scan for preamble pair
            guard let start = findPreamble(in: buffer, from: pos) else {
                break
            }

            // Need at least: FE FE to from cmd FD = 6 bytes
            guard start + 5 < buffer.count else {
                break
            }

            // Find terminator
            guard let endIdx = buffer[(start + 4)...].firstIndex(of: terminator) else {
                break
            }

            let to = buffer[start + 2]
            let from = buffer[start + 3]
            let command = buffer[start + 4]
            let dataRange = (start + 5) ..< endIdx
            let data = Array(buffer[dataRange])

            let frame = CIVFrame(to: to, from: from, command: command, data: data)
            frames.append(frame)
            consumed = endIdx + 1
            pos = consumed
        }

        return (frames, consumed)
    }

    // MARK: - BCD Frequency

    /// Parse a 5-byte BCD frequency (LSB-first) into Hz.
    /// Each byte encodes two BCD digits: low nibble is the less-significant digit.
    public static func parseBCDFrequency(_ data: [UInt8]) -> UInt64? {
        guard data.count >= 5 else {
            return nil
        }

        var freq: UInt64 = 0
        var multiplier: UInt64 = 1

        for i in 0 ..< 5 {
            let byte = data[i]
            let lo = UInt64(byte & 0x0F)
            let hi = UInt64((byte >> 4) & 0x0F)

            // Validate BCD digits
            guard lo <= 9, hi <= 9 else {
                return nil
            }

            freq += lo * multiplier
            multiplier *= 10
            freq += hi * multiplier
            multiplier *= 10
        }

        return freq
    }

    /// Encode a frequency in Hz to 5-byte BCD (LSB-first).
    public static func encodeBCDFrequency(_ frequencyHz: UInt64) -> [UInt8] {
        var hz = frequencyHz
        var bytes: [UInt8] = []

        for _ in 0 ..< 5 {
            let lo = UInt8(hz % 10)
            hz /= 10
            let hi = UInt8(hz % 10)
            hz /= 10
            bytes.append((hi << 4) | lo)
        }

        return bytes
    }

    /// Convert Hz to MHz as a Double.
    public static func hzToMHz(_ hz: UInt64) -> Double {
        Double(hz) / 1_000_000.0
    }

    /// Convert MHz to Hz.
    public static func mhzToHz(_ mhz: Double) -> UInt64 {
        UInt64(mhz * 1_000_000.0)
    }

    // MARK: Private

    /// Find the next preamble pair (FE FE) starting at `from`.
    private static func findPreamble(in buffer: [UInt8], from start: Int) -> Int? {
        var i = start
        while i + 1 < buffer.count {
            if buffer[i] == preamble, buffer[i + 1] == preamble {
                // Skip additional preamble bytes (some radios send >2)
                var actual = i
                while actual + 2 < buffer.count, buffer[actual + 2] == preamble {
                    actual += 1
                }
                return actual
            }
            i += 1
        }
        return nil
    }
}

// MARK: - CIVFrame

/// A parsed CI-V protocol frame.
public struct CIVFrame: Equatable, Sendable {
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
        command == 0xFB
    }

    /// Whether this is a NAK (command 0xFA, no data)
    public var isNak: Bool {
        command == 0xFA
    }
}

// MARK: - CIVMode

/// CI-V mode byte mapping to Carrier Wave mode strings.
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
        switch self {
        case .lsb: "LSB"
        case .usb: "USB"
        case .am: "AM"
        case .cw,
             .cwR: "CW"
        case .rtty,
             .rttyR: "RTTY"
        case .fm: "FM"
        case .wfm: "FM"
        }
    }

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .lsb: "LSB"
        case .usb: "USB"
        case .am: "AM"
        case .cw: "CW"
        case .rtty: "RTTY"
        case .fm: "FM"
        case .wfm: "WFM"
        case .cwR: "CW-R"
        case .rttyR: "RTTY-R"
        }
    }

    /// Create from a Carrier Wave mode string.
    /// Returns nil for modes without a CI-V equivalent.
    public static func from(carrierWaveMode: String) -> CIVMode? {
        switch carrierWaveMode.uppercased() {
        case "LSB": .lsb
        case "USB",
             "SSB": .usb
        case "AM": .am
        case "CW": .cw
        case "RTTY": .rtty
        case "FM": .fm
        default: nil
        }
    }
}
