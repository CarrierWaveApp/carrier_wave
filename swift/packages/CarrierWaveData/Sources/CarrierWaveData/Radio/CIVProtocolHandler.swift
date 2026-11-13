import CarrierWaveCore
import Foundation

/// CI-V protocol handler for Icom radios.
/// Delegates byte-level encoding/decoding to CarrierWaveCore's CIVProtocol.
public struct CIVProtocolHandler: RadioProtocolHandler {
    // MARK: Lifecycle

    public init(civAddress: UInt8 = 0xA4) {
        self.civAddress = civAddress
    }

    // MARK: Public

    public let civAddress: UInt8
    public let controllerAddress: UInt8 = CIVProtocol.controllerAddress

    public func encodeReadFrequency() -> Data? {
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: CIVProtocol.cmdReadFreq
        )
        return Data(frame)
    }

    public func encodeReadMode() -> Data? {
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: CIVProtocol.cmdReadMode
        )
        return Data(frame)
    }

    public func encodeSetFrequency(_ freqMHz: Double) -> Data {
        let freqHz = CIVProtocol.mhzToHz(freqMHz)
        let bcd = CIVProtocol.encodeBCDFrequency(freqHz)
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: CIVProtocol.cmdSetFreq,
            data: bcd
        )
        return Data(frame)
    }

    public func encodeSetMode(_ mode: String) -> Data {
        let civMode = CIVMode.from(carrierWaveMode: mode) ?? .cw
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: CIVProtocol.cmdSetMode,
            data: [civMode.rawValue]
        )
        return Data(frame)
    }

    public func encodeSetPTT(_ on: Bool) -> Data {
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: 0x1C,
            data: [0x00, on ? 0x01 : 0x00]
        )
        return Data(frame)
    }

    public func encodeSendCW(_ text: String) -> Data? {
        let textBytes = Array(text.uppercased().utf8)
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: 0x17,
            data: textBytes
        )
        return Data(frame)
    }

    public func encodeAbortCW() -> Data? {
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: 0x17,
            data: [0xFF]
        )
        return Data(frame)
    }

    public func encodeReadPTT() -> Data? {
        Data(CIVProtocol.buildFrame(to: civAddress, command: CIVDuplex.statusCommand, data: CIVDuplex.readPTT))
    }

    public func encodeReadPowerLevel() -> Data? {
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: CIVProtocol.cmdLevel,
            data: [CIVProtocol.subPowerLevel]
        )
        return Data(frame)
    }

    public func decodeFrequency(from data: Data) -> Double? {
        let bytes = [UInt8](data)
        let frames = CIVProtocol.extractFrames(from: bytes)
        for frame in frames.frames {
            if frame.command == CIVProtocol.cmdReadFreq
                || frame.command == CIVProtocol.cmdSetFreq
            {
                if let hz = CIVProtocol.parseBCDFrequency(frame.data) {
                    return CIVProtocol.hzToMHz(hz)
                }
            }
        }
        return nil
    }

    public func decodeMode(from data: Data) -> String? {
        let bytes = [UInt8](data)
        let frames = CIVProtocol.extractFrames(from: bytes)
        for frame in frames.frames {
            if frame.command == CIVProtocol.cmdReadMode
                || frame.command == CIVProtocol.cmdSetMode,
                let first = frame.data.first,
                let mode = CIVMode(rawValue: first)
            {
                return mode.carrierWaveMode
            }
        }
        return nil
    }

    public func decodePTTState(from data: Data) -> Bool? {
        let bytes = [UInt8](data)
        let frames = CIVProtocol.extractFrames(from: bytes)
        for frame in frames.frames {
            if frame.command == 0x1C,
               frame.data.count >= 2,
               frame.data[0] == 0x00
            {
                return frame.data[1] == 0x01
            }
        }
        return nil
    }

    public func decodePowerLevel(from data: Data) -> UInt8? {
        let bytes = [UInt8](data)
        let frames = CIVProtocol.extractFrames(from: bytes)
        for frame in frames.frames {
            // Response to 0x14 0x0A: data is [0x0A, bcd_lo, bcd_hi]
            if frame.command == CIVProtocol.cmdLevel,
               frame.data.count >= 3,
               frame.data[0] == CIVProtocol.subPowerLevel
            {
                let bcdLo = frame.data[1]
                let bcdHi = frame.data[2]
                let scaled = Int(bcdHi >> 4) * 100
                    + Int(bcdHi & 0x0F) * 10
                    + Int(bcdLo >> 4)
                // Convert 0-255 scale back to 0-100 percentage
                let watts = scaled * 100 / 255
                return UInt8(min(watts, 100))
            }
        }
        return nil
    }
}
