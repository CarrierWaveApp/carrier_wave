import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CarrierWaveData", category: "FlexProtocol")

// MARK: - FlexProtocolHandler

/// Protocol handler for FlexRadio SmartSDR TCP/IP API.
///
/// SmartSDR uses ASCII text commands over TCP port 4992.
/// Commands: `C<seq>|<command>\n`
/// Responses: `R<seq>|<hex_code>|<message>\n`
/// Status: `S<handle>|<key=value pairs>\n`
public struct FlexProtocolHandler: RadioProtocolHandler {
    // MARK: Lifecycle

    public init(sliceIndex: Int = 0) {
        self.sliceIndex = sliceIndex
    }

    // MARK: Public

    /// The active slice index to control (default: first slice 0)
    public let sliceIndex: Int

    // MARK: - Flex-Specific Decoding

    /// Parse the version line sent on initial connection: `V1.4.0.0`
    public static func decodeVersion(from line: String) -> String? {
        guard line.hasPrefix("V") else {
            return nil
        }
        return String(line.dropFirst())
    }

    /// Parse the handle line sent on initial connection: `H12345678`
    public static func decodeHandle(from line: String) -> UInt32? {
        guard line.hasPrefix("H") else {
            return nil
        }
        return UInt32(line.dropFirst(), radix: 16)
    }

    /// Parse a response line: `R<seq>|<hex_code>|<message>`
    public static func decodeResponse(from line: String) -> FlexResponse? {
        guard line.hasPrefix("R") else {
            return nil
        }
        let parts = line.dropFirst().split(separator: "|", maxSplits: 2)
        guard parts.count >= 2,
              let seq = UInt32(parts[0]),
              let code = UInt32(parts[1], radix: 16)
        else {
            return nil
        }
        let message = parts.count > 2 ? String(parts[2]) : ""
        return FlexResponse(sequence: seq, code: code, message: message)
    }

    /// Parse `display pan create` response message body into a stream handle.
    /// Successful responses look like `R<seq>|0|<panadapter_handle>` where the
    /// payload is the hex handle (with or without `0x` prefix). Returns nil
    /// if the message is not parseable as a handle.
    public static func decodeStreamHandle(from message: String) -> UInt32? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        // Some firmwares answer with "<handle>" alone, others with
        // "<handle> <waterfall_handle>" — first token is the panadapter.
        let first = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? trimmed
        let normalized = first.hasPrefix("0x") || first.hasPrefix("0X")
            ? String(first.dropFirst(2))
            : first
        return UInt32(normalized, radix: 16)
    }

    // MARK: - Encoding (Commands to Radio)

    public func encodeReadFrequency() -> Data? {
        // Flex pushes status via subscriptions, but we can also list slices
        encodeCommand("slice list")
    }

    public func encodeReadMode() -> Data? {
        // Mode comes from slice status subscriptions
        nil
    }

    public func encodeSetFrequency(_ freqMHz: Double) -> Data {
        encodeCommand("slice t \(sliceIndex) \(String(format: "%.6f", freqMHz))")
    }

    public func encodeSetMode(_ mode: String) -> Data {
        let flexMode = mapToFlexMode(mode)
        return encodeCommand("slice s \(sliceIndex) mode=\(flexMode)")
    }

    public func encodeSetPTT(_ on: Bool) -> Data {
        encodeCommand("xmit \(on ? "1" : "0")")
    }

    // MARK: - CW Keying

    public func encodeSendCW(_ text: String) -> Data? {
        // Replace spaces with 0x7F per SmartSDR CWX spec
        let encoded = text.replacingOccurrences(of: " ", with: "\u{7F}")
        return encodeCommand("cwx send \"\(encoded)\"")
    }

    public func encodeAbortCW() -> Data? {
        encodeCommand("cwx clear")
    }

    // MARK: - XIT/RIT

    public func encodeSetXIT(_ on: Bool) -> Data? {
        encodeCommand("slice s \(sliceIndex) xit_on=\(on ? "1" : "0")")
    }

    public func encodeSetXITOffset(_ hz: Int) -> Data? {
        encodeCommand("slice s \(sliceIndex) xit_freq=\(hz)")
    }

    public func encodeClearRITXIT() -> Data? {
        // Clear both RIT and XIT offsets to zero
        encodeCommand("slice s \(sliceIndex) rit_freq=0 xit_freq=0")
    }

    public func encodeReadXIT() -> Data? {
        nil
    }

    public func encodeReadRIT() -> Data? {
        nil
    }

    public func encodeReadRITXITOffset() -> Data? {
        nil
    }

    // MARK: - WAN Commands

    /// Encode the WAN validate command. MUST be the first command sent
    /// after connecting to a radio via SmartLink.
    public func encodeWanValidate(handle: String) -> Data {
        encodeCommand("wan validate handle=\(handle)")
    }

    // MARK: - Subscription Commands

    /// Encode the initial subscription commands sent after connecting.
    /// These tell SmartSDR to push status updates for slices, TX, and radio state.
    public func encodeSubscriptions() -> [Data] {
        [
            encodeCommand("sub slice all"),
            encodeCommand("sub tx all"),
            encodeCommand("sub radio all"),
            encodeCommand("sub client all"),
        ]
    }

    /// Encode the client identification command.
    public func encodeClientSetup(programName: String) -> Data {
        encodeCommand("client program \(programName)")
    }

    // MARK: - Panadapter / Waterfall

    /// Tell SmartSDR which UDP port to send VITA-49 data streams to. Must be
    /// sent before creating any panadapter or waterfall stream so the radio
    /// has a destination to bind to.
    public func encodeClientUdpPort(_ port: UInt16) -> Data {
        encodeCommand("client udpport \(port)")
    }

    /// Create a panadapter (display) stream. SmartSDR responds with the
    /// panadapter handle (e.g. `0x40000001`) which becomes the VITA-49 stream
    /// ID for incoming spectrum frames.
    ///
    /// `binCount` is the number of FFT bins the radio should produce
    /// (typically 1000–2048). `centerMHz` and `bandwidthMHz` control the
    /// frequency window. `fps` caps the update rate.
    public func encodePanadapterCreate(
        binCount: Int,
        centerMHz: Double,
        bandwidthMHz: Double,
        fps: Int = 10
    ) -> Data {
        let parts = [
            "display pan create",
            "x=\(binCount)",
            "freq=\(String(format: "%.6f", centerMHz))",
            "bandwidth=\(String(format: "%.6f", bandwidthMHz))",
            "fps=\(fps)",
        ]
        return encodeCommand(parts.joined(separator: " "))
    }

    /// Adjust an existing panadapter's properties. Used to change FPS or
    /// averaging without tearing down the stream.
    public func encodePanadapterSet(handle: UInt32, fps: Int) -> Data {
        let hex = String(format: "0x%08X", handle)
        return encodeCommand("display pan set \(hex) fps=\(fps)")
    }

    /// Tear down a panadapter stream when the operator disconnects.
    public func encodePanadapterRemove(handle: UInt32) -> Data {
        let hex = String(format: "0x%08X", handle)
        return encodeCommand("display pan remove \(hex)")
    }

    // MARK: - Decoding (Responses from Radio)

    public func decodeFrequency(from data: Data) -> Double? {
        guard let line = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Status messages: S<handle>|slice <n> <key=value ...>
        // Look for RF_frequency=<MHz>
        if let freq = extractValue(from: line, key: "RF_frequency") {
            return Double(freq)
        }

        // Also handle "freq" key in some status formats
        if let freq = extractValue(from: line, key: "freq") {
            return Double(freq)
        }

        return nil
    }

    public func decodeMode(from data: Data) -> String? {
        guard let line = String(data: data, encoding: .utf8) else {
            return nil
        }

        if let mode = extractValue(from: line, key: "mode") {
            return mapFromFlexMode(mode)
        }
        return nil
    }

    public func decodePTTState(from data: Data) -> Bool? {
        guard let line = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Interlock status: state=TRANSMITTING or state=RECEIVE
        if let state = extractValue(from: line, key: "state") {
            if state == "TRANSMITTING" {
                return true
            }
            if state == "RECEIVE" || state == "READY" {
                return false
            }
        }
        return nil
    }

    public func decodeXITState(from data: Data) -> Bool? {
        guard let line = String(data: data, encoding: .utf8) else {
            return nil
        }
        if let val = extractValue(from: line, key: "xit_on") {
            return val == "1"
        }
        return nil
    }

    public func decodeRITState(from data: Data) -> Bool? {
        guard let line = String(data: data, encoding: .utf8) else {
            return nil
        }
        if let val = extractValue(from: line, key: "rit_on") {
            return val == "1"
        }
        return nil
    }

    public func decodeRITXITOffset(from data: Data) -> Int? {
        guard let line = String(data: data, encoding: .utf8) else {
            return nil
        }
        // Try XIT first, then RIT
        if let val = extractValue(from: line, key: "xit_freq") {
            return Int(val)
        }
        if let val = extractValue(from: line, key: "rit_freq") {
            return Int(val)
        }
        return nil
    }

    /// Check if a line is a status message for our target slice
    public func isSliceStatus(line: String) -> Bool {
        line.contains("slice \(sliceIndex) ")
    }

    // MARK: Private

    /// Sequence counter for commands (shared via static to survive handler copies)
    private static let sequenceCounter = FlexSequenceCounter()

    private func encodeCommand(_ command: String) -> Data {
        let seq = Self.sequenceCounter.next()
        let line = "C\(seq)|\(command)\n"
        return Data(line.utf8)
    }

    /// Extract a key=value from a SmartSDR status line
    private func extractValue(from line: String, key: String) -> String? {
        let pattern = "\(key)="
        guard let range = line.range(of: pattern) else {
            return nil
        }
        let valueStart = range.upperBound
        let remaining = line[valueStart...]
        // Value ends at next space or end of line
        let valueEnd = remaining.firstIndex(of: " ") ?? remaining.endIndex
        let value = String(remaining[valueStart ..< valueEnd])
        return value.isEmpty ? nil : value
    }

    /// Map standard amateur mode names to Flex mode strings
    private func mapToFlexMode(_ mode: String) -> String {
        switch mode.uppercased() {
        case "LSB": "LSB"
        case "USB": "USB"
        case "CW",
             "CW-U": "CW"
        case "CW-L": "CWL"
        case "AM": "AM"
        case "FM": "FM"
        case "DIGU",
             "FT8",
             "FT4",
             "RTTY",
             "JTTY": "DIGU"
        case "DIGL": "DIGL"
        case "SAM": "SAM"
        default: mode.uppercased()
        }
    }

    /// Map Flex mode strings back to standard mode names
    private func mapFromFlexMode(_ flexMode: String) -> String {
        switch flexMode.uppercased() {
        case "LSB": "LSB"
        case "USB": "USB"
        case "CW": "CW"
        case "CWL": "CW-L"
        case "AM": "AM"
        case "FM": "FM"
        case "DIGU": "DIGU"
        case "DIGL": "DIGL"
        case "SAM": "SAM"
        case "NFM": "FM"
        case "DFM": "FM"
        default: flexMode
        }
    }
}

// MARK: - FlexResponse

/// Parsed SmartSDR response message
public struct FlexResponse: Sendable {
    // MARK: Lifecycle

    public init(sequence: UInt32, code: UInt32, message: String) {
        self.sequence = sequence
        self.code = code
        self.message = message
    }

    // MARK: Public

    public let sequence: UInt32
    public let code: UInt32
    public let message: String

    public var isSuccess: Bool {
        code == 0
    }
}

// MARK: - FlexSequenceCounter

/// Thread-safe sequence counter for SmartSDR commands
public final class FlexSequenceCounter: @unchecked Sendable {
    // MARK: Public

    public func next() -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        counter += 1
        return counter
    }

    // MARK: Private

    private let lock = NSLock()
    private var counter: UInt32 = 0
}
