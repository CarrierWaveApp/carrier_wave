import Foundation

// MARK: - RadioProtocolHandler

/// Protocol handler abstraction for radio CAT commands.
/// Each radio family (CI-V, Kenwood, Yaesu) provides a concrete implementation.
protocol RadioProtocolHandler: Sendable {
    // MARK: - Encoding (Commands to Radio)

    func encodeReadFrequency() -> Data?
    func encodeReadMode() -> Data?
    func encodeSetFrequency(_ freqMHz: Double) -> Data
    func encodeSetMode(_ mode: String) -> Data
    func encodeSetPTT(_ on: Bool) -> Data

    // MARK: - CW Keying

    /// Encode a CW text message for the radio's internal keyer.
    /// Returns nil if the radio doesn't support CW sending via CAT.
    func encodeSendCW(_ text: String) -> Data?

    /// Encode an abort command to stop CW sending.
    func encodeAbortCW() -> Data?

    // MARK: - XIT/RIT

    /// Encode a set-XIT on/off command.
    /// Returns nil if the radio doesn't support XIT via CAT.
    func encodeSetXIT(_ on: Bool) -> Data?

    /// Encode an absolute XIT offset command in Hz (-9999...+9999).
    /// Returns nil if the radio doesn't support XIT via CAT.
    func encodeSetXITOffset(_ hz: Int) -> Data?

    /// Encode a clear RIT/XIT offset command (sets offset to zero).
    /// Returns nil if the radio doesn't support RIT/XIT clearing via CAT.
    func encodeClearRITXIT() -> Data?

    // MARK: - XIT/RIT Reading

    /// Encode a read-XIT command. Returns nil if unsupported.
    func encodeReadXIT() -> Data?

    /// Encode a read-RIT command. Returns nil if unsupported.
    func encodeReadRIT() -> Data?

    /// Encode a read-RIT/XIT offset command. Returns nil if unsupported.
    func encodeReadRITXITOffset() -> Data?

    // MARK: - Decoding (Responses from Radio)

    func decodeFrequency(from data: Data) -> Double?
    func decodeMode(from data: Data) -> String?
    func decodePTTState(from data: Data) -> Bool?
    func decodeXITState(from data: Data) -> Bool?
    func decodeRITState(from data: Data) -> Bool?
    func decodeRITXITOffset(from data: Data) -> Int?
}

/// Default implementations
extension RadioProtocolHandler {
    func encodeSendCW(_ text: String) -> Data? {
        nil
    }

    func encodeAbortCW() -> Data? {
        nil
    }

    func encodeSetXIT(_ on: Bool) -> Data? {
        nil
    }

    func encodeSetXITOffset(_ hz: Int) -> Data? {
        nil
    }

    func encodeClearRITXIT() -> Data? {
        nil
    }

    func encodeReadXIT() -> Data? {
        nil
    }

    func encodeReadRIT() -> Data? {
        nil
    }

    func encodeReadRITXITOffset() -> Data? {
        nil
    }

    func decodeXITState(from _: Data) -> Bool? {
        nil
    }

    func decodeRITState(from _: Data) -> Bool? {
        nil
    }

    func decodeRITXITOffset(from _: Data) -> Int? {
        nil
    }
}
