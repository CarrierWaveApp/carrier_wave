import Foundation

// MARK: - RadioProtocolHandler

/// Protocol handler abstraction for radio CAT commands.
/// Each radio family (CI-V, Kenwood, Yaesu, Flex) provides a concrete implementation.
public protocol RadioProtocolHandler: Sendable {
    // MARK: - Encoding (Commands to Radio)

    func encodeReadFrequency() -> Data?
    func encodeReadMode() -> Data?
    func encodeSetFrequency(_ freqMHz: Double) -> Data
    func encodeSetMode(_ mode: String) -> Data
    func encodeSetPTT(_ on: Bool) -> Data

    // MARK: - CW Keying

    func encodeSendCW(_ text: String) -> Data?
    func encodeAbortCW() -> Data?

    // MARK: - XIT/RIT

    func encodeSetXIT(_ on: Bool) -> Data?
    func encodeSetXITOffset(_ hz: Int) -> Data?
    func encodeClearRITXIT() -> Data?
    func encodeReadXIT() -> Data?
    func encodeReadRIT() -> Data?
    func encodeReadRITXITOffset() -> Data?

    // MARK: - Power Level

    func encodeReadPowerLevel() -> Data?

    // MARK: - PTT state

    /// Poll the transmit state (CI-V `1C 00`). Nil when the protocol has no
    /// read, in which case `isTransmitting` only tracks our own PTT sets.
    func encodeReadPTT() -> Data?

    // MARK: - Decoding (Responses from Radio)

    func decodeFrequency(from data: Data) -> Double?
    func decodeMode(from data: Data) -> String?
    func decodePTTState(from data: Data) -> Bool?
    func decodeXITState(from data: Data) -> Bool?
    func decodeRITState(from data: Data) -> Bool?
    func decodeRITXITOffset(from data: Data) -> Int?
    func decodePowerLevel(from data: Data) -> UInt8?
}

/// Default implementations for optional capabilities
public extension RadioProtocolHandler {
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

    func decodeXITState(from data: Data) -> Bool? {
        nil
    }

    func decodeRITState(from data: Data) -> Bool? {
        nil
    }

    func decodeRITXITOffset(from data: Data) -> Int? {
        nil
    }

    func encodeReadPowerLevel() -> Data? {
        nil
    }

    func decodePowerLevel(from data: Data) -> UInt8? {
        nil
    }

    func encodeReadPTT() -> Data? {
        nil
    }
}
