import CarrierWaveCore
import Foundation

/// CI-V protocol handler for Icom radios.
/// Delegates byte-level encoding/decoding to CarrierWaveCore's CIVProtocol.
struct CIVProtocolHandler: RadioProtocolHandler {
    let civAddress: UInt8
    let controllerAddress: UInt8 = CIVProtocol.controllerAddress

    func encodeReadFrequency() -> Data? {
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: CIVProtocol.cmdReadFreq
        )
        return Data(frame)
    }

    func encodeReadMode() -> Data? {
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: CIVProtocol.cmdReadMode
        )
        return Data(frame)
    }

    func encodeSetFrequency(_ freqMHz: Double) -> Data {
        let freqHz = CIVProtocol.mhzToHz(freqMHz)
        let bcd = CIVProtocol.encodeBCDFrequency(freqHz)
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: CIVProtocol.cmdSetFreq,
            data: bcd
        )
        return Data(frame)
    }

    func encodeSetMode(_ mode: String) -> Data {
        let civMode = CIVMode.from(carrierWaveMode: mode) ?? .cw
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: CIVProtocol.cmdSetMode,
            data: [civMode.rawValue]
        )
        return Data(frame)
    }

    func encodeSetPTT(_ on: Bool) -> Data {
        // CI-V PTT: command 0x1C, sub-command 0x00, data 0x01 (TX) or 0x00 (RX)
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: 0x1C,
            data: [0x00, on ? 0x01 : 0x00]
        )
        return Data(frame)
    }

    func encodeSendCW(_ text: String) -> Data? {
        // CI-V command 0x17: Send CW message
        let textBytes = Array(text.uppercased().utf8)
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: 0x17,
            data: textBytes
        )
        return Data(frame)
    }

    func encodeAbortCW() -> Data? {
        // CI-V command 0x17 with FF to abort
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: 0x17,
            data: [0xFF]
        )
        return Data(frame)
    }

    func decodeFrequency(from data: Data) -> Double? {
        let bytes = [UInt8](data)
        let frames = CIVProtocol.extractFrames(from: bytes)
        for frame in frames.frames {
            if frame.command == CIVProtocol.cmdReadFreq || frame.command == CIVProtocol.cmdSetFreq {
                if let hz = CIVProtocol.parseBCDFrequency(frame.data) {
                    return CIVProtocol.hzToMHz(hz)
                }
            }
        }
        return nil
    }

    func decodeMode(from data: Data) -> String? {
        let bytes = [UInt8](data)
        let frames = CIVProtocol.extractFrames(from: bytes)
        for frame in frames.frames {
            if frame.command == CIVProtocol.cmdReadMode || frame.command == CIVProtocol.cmdSetMode,
               let first = frame.data.first,
               let mode = CIVMode(rawValue: first)
            {
                return mode.carrierWaveMode
            }
        }
        return nil
    }

    func decodePTTState(from data: Data) -> Bool? {
        let bytes = [UInt8](data)
        let frames = CIVProtocol.extractFrames(from: bytes)
        for frame in frames.frames {
            if frame.command == 0x1C, frame.data.count >= 2, frame.data[0] == 0x00 {
                return frame.data[1] == 0x01
            }
        }
        return nil
    }
}
