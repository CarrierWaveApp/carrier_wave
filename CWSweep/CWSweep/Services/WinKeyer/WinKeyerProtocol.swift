import Foundation

// MARK: - WinKeyerCommand

/// Immediate commands (0x01–0x1F) sent as the first byte.
enum WinKeyerCommand: UInt8, Sendable {
    case sidetoneControl = 0x01
    case setSpeed = 0x02
    case setWeighting = 0x03
    case setPTTLeadIn = 0x04
    case setSpeedPot = 0x05
    case pause = 0x06
    case getSpeedPot = 0x07
    case backspace = 0x08
    case pinConfig = 0x09
    case clearBuffer = 0x0A
    case keyImmediate = 0x0B
    case hscwSpeed = 0x0C
    case farnsworth = 0x0D
    case setMode = 0x0E
    case loadDefaults = 0x0F
    case firstExtension = 0x10
    case setKeyComp = 0x11
    case nullPad = 0x12
    case pttControl = 0x13
    case timedKeyDown = 0x14
    case wait = 0x15
    case mergeLetters = 0x16
    case speedChange = 0x17
    case portSelect = 0x18
    case cancelBuffer = 0x19
    case bufferedNOP = 0x1A
}

// MARK: - WinKeyerAdmin

/// Admin sub-commands (prefixed by 0x00).
enum WinKeyerAdmin: UInt8, Sendable {
    case calibrate = 0x00
    case reset = 0x01
    case hostOpen = 0x02
    case hostClose = 0x03
    case echoTest = 0x04
    case paddleA2D = 0x05
    case speedA2D = 0x06
    case getValues = 0x07
    case getCal = 0x09
    case setWK1Mode = 0x0A
    case setWK2Mode = 0x0B
    case dumpEEPROM = 0x0C
    case loadEEPROM = 0x0D
    case sendMsg = 0x0E
    case loadMsg = 0x0F
    case setWK3Mode = 0x10
    case writeWK3Reg = 0x11
    case readWK3Reg = 0x12
}

// MARK: - WinKeyerStatus

/// Decoded status byte flags from WinKeyer.
struct WinKeyerStatus: OptionSet, Sendable, Hashable {
    /// Send buffer full — host must pause sending characters.
    static let xoff = WinKeyerStatus(rawValue: 0x20)
    /// Operator pressed paddles (break-in detected).
    static let breakin = WinKeyerStatus(rawValue: 0x10)
    /// Keyer is actively sending CW.
    static let busy = WinKeyerStatus(rawValue: 0x08)

    let rawValue: UInt8
}

// MARK: - WinKeyerEvent

/// Events emitted by WinKeyerSession for the manager to consume.
enum WinKeyerEvent: Sendable {
    case connected(firmwareVersion: UInt8)
    case disconnected
    case statusChanged(WinKeyerStatus)
    case speedPotChanged(wpm: UInt8)
    case echoCharacter(UInt8)
    case error(String)
}

// MARK: - WinKeyerState

/// Snapshot of WinKeyer state for UI display.
struct WinKeyerState: Sendable {
    var speed: UInt8 = 25
    var status: WinKeyerStatus = []
    var firmwareVersion: UInt8 = 0
    var isConnected: Bool = false
}

// MARK: - WinKeyerProtocolEncoder

/// Static helpers for encoding/decoding the WK3 binary protocol.
enum WinKeyerProtocolEncoder {
    // MARK: - Admin commands

    static func encodeHostOpen() -> Data {
        Data([0x00, WinKeyerAdmin.hostOpen.rawValue])
    }

    static func encodeHostClose() -> Data {
        Data([0x00, WinKeyerAdmin.hostClose.rawValue])
    }

    static func encodeEchoTest(_ byte: UInt8) -> Data {
        Data([0x00, WinKeyerAdmin.echoTest.rawValue, byte])
    }

    static func encodeSendMessage(slot: UInt8) -> Data {
        Data([0x00, WinKeyerAdmin.sendMsg.rawValue, slot])
    }

    static func encodeSetWK3Mode() -> Data {
        Data([0x00, WinKeyerAdmin.setWK3Mode.rawValue])
    }

    // MARK: - Immediate commands

    static func encodeSetSpeed(_ wpm: UInt8) -> Data {
        Data([WinKeyerCommand.setSpeed.rawValue, min(max(wpm, 5), 99)])
    }

    static func encodeSetMode(_ mode: UInt8) -> Data {
        Data([WinKeyerCommand.setMode.rawValue, mode])
    }

    static func encodeClearBuffer() -> Data {
        Data([WinKeyerCommand.clearBuffer.rawValue])
    }

    static func encodeCancelBuffer() -> Data {
        Data([WinKeyerCommand.cancelBuffer.rawValue])
    }

    static func encodeGetSpeedPot() -> Data {
        Data([WinKeyerCommand.getSpeedPot.rawValue])
    }

    static func encodeSetSpeedPot(min: UInt8, range: UInt8) -> Data {
        Data([WinKeyerCommand.setSpeedPot.rawValue, min, range, 0])
    }

    static func encodePause(_ paused: Bool) -> Data {
        Data([WinKeyerCommand.pause.rawValue, paused ? 1 : 0])
    }

    static func encodeKeyImmediate(_ down: Bool) -> Data {
        Data([WinKeyerCommand.keyImmediate.rawValue, down ? 1 : 0])
    }

    static func encodePTTControl(_ on: Bool) -> Data {
        Data([WinKeyerCommand.pttControl.rawValue, on ? 1 : 0])
    }

    static func encodeSidetone(_ value: UInt8) -> Data {
        Data([WinKeyerCommand.sidetoneControl.rawValue, value])
    }

    static func encodeLoadDefaults(_ values: [UInt8]) -> Data {
        var data = Data([WinKeyerCommand.loadDefaults.rawValue])
        // Load Defaults expects exactly 15 bytes
        let padded = values + Array(repeating: UInt8(0), count: max(0, 15 - values.count))
        data.append(contentsOf: padded.prefix(15))
        return data
    }

    static func encodeMergeLetters(_ a: UInt8, _ b: UInt8) -> Data {
        Data([WinKeyerCommand.mergeLetters.rawValue, a, b])
    }

    // MARK: - Decode helpers

    /// Returns true if the byte is a status byte (top 2 bits = 11).
    static func isStatusByte(_ byte: UInt8) -> Bool {
        (byte & 0xC0) == 0xC0
    }

    /// Returns true if the byte is a speed pot byte (top 2 bits = 10).
    static func isSpeedPotByte(_ byte: UInt8) -> Bool {
        (byte & 0xC0) == 0x80
    }

    /// Decode status flags from a status byte.
    static func decodeStatus(_ byte: UInt8) -> WinKeyerStatus {
        WinKeyerStatus(rawValue: byte & 0x3F)
    }

    /// Decode speed from a speed pot byte (bits 5:0 = speed offset from pot minimum).
    static func decodeSpeedPot(_ byte: UInt8) -> UInt8 {
        byte & 0x3F
    }
}
