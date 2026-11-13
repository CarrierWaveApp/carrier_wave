import CarrierWaveCore
import Foundation

/// Kenwood CAT protocol handler.
/// Commands are ASCII text terminated with ';'.
public struct KenwoodProtocolHandler: RadioProtocolHandler {
    // MARK: Lifecycle

    /// `isYaesu` routes mode parsing through the Yaesu `MD0<char>;` format.
    /// Yaesu radios speak Kenwood-compatible CAT but answer `MD` with a leading
    /// band digit, which the Kenwood mode parser would misread (reading the
    /// band digit as the mode → mode never resolves).
    public init(isYaesu: Bool = false) {
        self.isYaesu = isYaesu
    }

    // MARK: Public

    public let isYaesu: Bool

    public func encodeReadFrequency() -> Data? {
        KenwoodProtocol.readFrequency().data(using: .ascii)
    }

    public func encodeReadMode() -> Data? {
        KenwoodProtocol.readMode().data(using: .ascii)
    }

    public func encodeSetFrequency(_ freqMHz: Double) -> Data {
        let freqHz = UInt64((freqMHz * 1_000_000).rounded())
        let cmd = KenwoodProtocol.setFrequency(hz: freqHz)
        return cmd.data(using: .ascii) ?? Data()
    }

    public func encodeSetMode(_ mode: String) -> Data {
        let kenwoodMode = KenwoodMode.from(carrierWaveMode: mode) ?? .cw
        let cmd = KenwoodProtocol.setMode(kenwoodMode)
        return cmd.data(using: .ascii) ?? Data()
    }

    public func encodeSetPTT(_ on: Bool) -> Data {
        let cmd = on ? "TX;" : "RX;"
        return cmd.data(using: .ascii) ?? Data()
    }

    public func encodeSendCW(_ text: String) -> Data? {
        // KY command: sends CW text via internal keyer
        "KY \(text);".data(using: .ascii)
    }

    public func encodeAbortCW() -> Data? {
        // KY0; stops CW sending on Kenwood
        "KY0;".data(using: .ascii)
    }

    public func encodeSetXIT(_ on: Bool) -> Data? {
        KenwoodProtocol.setXIT(on: on).data(using: .ascii)
    }

    public func encodeSetXITOffset(_ hz: Int) -> Data? {
        KenwoodProtocol.setRITXITOffset(hz: hz).data(using: .ascii)
    }

    public func encodeClearRITXIT() -> Data? {
        KenwoodProtocol.clearRITXIT().data(using: .ascii)
    }

    public func encodeReadXIT() -> Data? {
        KenwoodProtocol.readXIT().data(using: .ascii)
    }

    public func encodeReadRIT() -> Data? {
        KenwoodProtocol.readRIT().data(using: .ascii)
    }

    public func encodeReadRITXITOffset() -> Data? {
        KenwoodProtocol.readRITXITOffset().data(using: .ascii)
    }

    public func encodeReadPowerLevel() -> Data? {
        KenwoodProtocol.readPowerLevel().data(using: .ascii)
    }

    public func decodeFrequency(from data: Data) -> Double? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = KenwoodProtocol.extractResponses(from: str)
        for response in responses.responses {
            if let hz = KenwoodProtocol.parseFrequencyResponse(response) {
                return Double(hz) / 1_000_000.0
            }
        }
        return nil
    }

    public func decodeMode(from data: Data) -> String? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = KenwoodProtocol.extractResponses(from: str)
        for response in responses.responses {
            // Yaesu answers MD with a leading band digit ("MD0<char>;"), so
            // parse it with the Yaesu mode table; Kenwood uses "MD<digit>;".
            if isYaesu {
                if let mode = YaesuProtocol.parseModeResponse(response) {
                    return mode.carrierWaveMode
                }
            } else if let mode = KenwoodProtocol.parseModeResponse(response) {
                return mode.carrierWaveMode
            }
        }
        return nil
    }

    public func decodePTTState(from data: Data) -> Bool? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = KenwoodProtocol.extractResponses(from: str)
        for response in responses.responses where response.hasPrefix("TX") {
            return response.contains("1")
        }
        return nil
    }

    public func decodeXITState(from data: Data) -> Bool? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = KenwoodProtocol.extractResponses(from: str)
        for response in responses.responses {
            if let state = KenwoodProtocol.parseXITResponse(response) {
                return state
            }
        }
        return nil
    }

    public func decodeRITState(from data: Data) -> Bool? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = KenwoodProtocol.extractResponses(from: str)
        for response in responses.responses {
            if let state = KenwoodProtocol.parseRITResponse(response) {
                return state
            }
        }
        return nil
    }

    public func decodeRITXITOffset(from data: Data) -> Int? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = KenwoodProtocol.extractResponses(from: str)
        for response in responses.responses {
            if let offset = KenwoodProtocol.parseRITXITOffsetResponse(response) {
                return offset
            }
        }
        return nil
    }

    public func decodePowerLevel(from data: Data) -> UInt8? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = KenwoodProtocol.extractResponses(from: str)
        for response in responses.responses {
            if let watts = KenwoodProtocol.parsePowerLevelResponse(response) {
                return watts
            }
        }
        return nil
    }
}
