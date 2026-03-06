import CarrierWaveCore
import Foundation

/// Kenwood CAT protocol handler.
/// Commands are ASCII text terminated with ';'.
struct KenwoodProtocolHandler: RadioProtocolHandler {
    func encodeReadFrequency() -> Data? {
        KenwoodProtocol.readFrequency().data(using: .ascii)
    }

    func encodeReadMode() -> Data? {
        KenwoodProtocol.readMode().data(using: .ascii)
    }

    func encodeSetFrequency(_ freqMHz: Double) -> Data {
        let freqHz = UInt64(freqMHz * 1_000_000)
        let cmd = KenwoodProtocol.setFrequency(hz: freqHz)
        return cmd.data(using: .ascii) ?? Data()
    }

    func encodeSetMode(_ mode: String) -> Data {
        let kenwoodMode = KenwoodMode.from(carrierWaveMode: mode) ?? .cw
        let cmd = KenwoodProtocol.setMode(kenwoodMode)
        return cmd.data(using: .ascii) ?? Data()
    }

    func encodeSetPTT(_ on: Bool) -> Data {
        let cmd = on ? "TX;" : "RX;"
        return cmd.data(using: .ascii) ?? Data()
    }

    func encodeSendCW(_ text: String) -> Data? {
        // KY command: sends CW text via internal keyer
        "KY \(text);".data(using: .ascii)
    }

    func encodeAbortCW() -> Data? {
        // KY0; stops CW sending on Kenwood
        "KY0;".data(using: .ascii)
    }

    func encodeSetXIT(_ on: Bool) -> Data? {
        KenwoodProtocol.setXIT(on: on).data(using: .ascii)
    }

    func encodeSetXITOffset(_ hz: Int) -> Data? {
        KenwoodProtocol.setRITXITOffset(hz: hz).data(using: .ascii)
    }

    func encodeClearRITXIT() -> Data? {
        KenwoodProtocol.clearRITXIT().data(using: .ascii)
    }

    func decodeFrequency(from data: Data) -> Double? {
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

    func decodeMode(from data: Data) -> String? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = KenwoodProtocol.extractResponses(from: str)
        for response in responses.responses {
            if let mode = KenwoodProtocol.parseModeResponse(response) {
                return mode.carrierWaveMode
            }
        }
        return nil
    }

    func decodePTTState(from data: Data) -> Bool? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = KenwoodProtocol.extractResponses(from: str)
        for response in responses.responses {
            if response.hasPrefix("TX") {
                return response.contains("1")
            }
        }
        return nil
    }
}
