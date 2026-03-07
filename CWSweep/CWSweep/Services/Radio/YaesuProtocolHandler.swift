import CarrierWaveCore
import Foundation

/// Yaesu CAT protocol handler.
/// Commands are ASCII text terminated with ';'.
/// Uses the IF command for efficient polling (reads freq, mode, RIT, XIT, offset in one shot).
struct YaesuProtocolHandler: RadioProtocolHandler {
    func encodeReadFrequency() -> Data? {
        // Use IF command to read all state at once.
        // decodeFrequency/decodeMode/decodeRIT/etc all parse the IF response.
        YaesuProtocol.readInformation().data(using: .ascii)
    }

    func encodeReadMode() -> Data? {
        // Mode is decoded from the IF response sent by encodeReadFrequency.
        nil
    }

    func encodeSetFrequency(_ freqMHz: Double) -> Data {
        let freqHz = UInt64(freqMHz * 1_000_000)
        let cmd = YaesuProtocol.setFrequency(hz: freqHz)
        return cmd.data(using: .ascii) ?? Data()
    }

    func encodeSetMode(_ mode: String) -> Data {
        let yaesuMode = YaesuMode.from(carrierWaveMode: mode) ?? .cwU
        let cmd = YaesuProtocol.setMode(yaesuMode)
        return cmd.data(using: .ascii) ?? Data()
    }

    func encodeSetPTT(_ on: Bool) -> Data {
        let cmd = YaesuProtocol.setPTT(on: on)
        return cmd.data(using: .ascii) ?? Data()
    }

    func encodeSendCW(_ text: String) -> Data? {
        YaesuProtocol.sendCW(text).data(using: .ascii)
    }

    func encodeAbortCW() -> Data? {
        // Stop TX to abort CW — Yaesu has no dedicated CW abort command
        YaesuProtocol.setPTT(on: false).data(using: .ascii)
    }

    // MARK: - RIT/XIT

    func encodeSetXIT(_ on: Bool) -> Data? {
        YaesuProtocol.setXIT(on: on).data(using: .ascii)
    }

    func encodeSetXITOffset(_ hz: Int) -> Data? {
        // Yaesu uses RU (up) / RD (down) for offset adjustment.
        // Clear first, then set to absolute value.
        var cmd = YaesuProtocol.clearClarifier()
        if hz > 0 {
            cmd += YaesuProtocol.clarifierUp(hz: hz)
        } else if hz < 0 {
            cmd += YaesuProtocol.clarifierDown(hz: abs(hz))
        }
        return cmd.data(using: .ascii)
    }

    func encodeClearRITXIT() -> Data? {
        YaesuProtocol.clearClarifier().data(using: .ascii)
    }

    func encodeReadXIT() -> Data? {
        // XIT state is decoded from the IF response sent by encodeReadFrequency.
        nil
    }

    func encodeReadRIT() -> Data? {
        // RIT state is decoded from the IF response sent by encodeReadFrequency.
        nil
    }

    func encodeReadRITXITOffset() -> Data? {
        // Offset is decoded from the IF response sent by encodeReadFrequency.
        nil
    }

    // MARK: - Decoding

    func decodeFrequency(from data: Data) -> Double? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = YaesuProtocol.extractResponses(from: str)
        for response in responses.responses {
            // Try IF response first (comprehensive)
            if let info = YaesuProtocol.parseInformationResponse(response) {
                return Double(info.frequencyHz) / 1_000_000.0
            }
            // Fall back to FA response
            if let hz = YaesuProtocol.parseFrequencyResponse(response) {
                return Double(hz) / 1_000_000.0
            }
        }
        return nil
    }

    func decodeMode(from data: Data) -> String? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = YaesuProtocol.extractResponses(from: str)
        for response in responses.responses {
            // Try IF response first
            if let info = YaesuProtocol.parseInformationResponse(response) {
                return info.mode?.carrierWaveMode
            }
            // Fall back to MD response
            if let mode = YaesuProtocol.parseModeResponse(response) {
                return mode.carrierWaveMode
            }
        }
        return nil
    }

    func decodePTTState(from data: Data) -> Bool? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = YaesuProtocol.extractResponses(from: str)
        for response in responses.responses {
            if let tx = YaesuProtocol.parseTXResponse(response) {
                return tx
            }
        }
        return nil
    }

    func decodeXITState(from data: Data) -> Bool? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = YaesuProtocol.extractResponses(from: str)
        for response in responses.responses {
            if let info = YaesuProtocol.parseInformationResponse(response) {
                return info.txClarifier
            }
            if let state = YaesuProtocol.parseXITResponse(response) {
                return state
            }
        }
        return nil
    }

    func decodeRITState(from data: Data) -> Bool? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = YaesuProtocol.extractResponses(from: str)
        for response in responses.responses {
            if let info = YaesuProtocol.parseInformationResponse(response) {
                return info.rxClarifier
            }
            if let state = YaesuProtocol.parseRITResponse(response) {
                return state
            }
        }
        return nil
    }

    func decodeRITXITOffset(from data: Data) -> Int? {
        guard let str = String(data: data, encoding: .ascii) else {
            return nil
        }
        let responses = YaesuProtocol.extractResponses(from: str)
        for response in responses.responses {
            if let info = YaesuProtocol.parseInformationResponse(response) {
                return info.clarifierOffset
            }
        }
        return nil
    }
}
