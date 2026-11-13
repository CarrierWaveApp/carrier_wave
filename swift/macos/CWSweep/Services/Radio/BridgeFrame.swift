import CarrierWaveCore
import Foundation
import SwiftProtobuf

// MARK: - BridgeFrame

/// Protobuf-based framing for the Carrier Wave Bridge Protocol over BLE NUS.
/// Each BLE notification is one serialized `Cwbp_BridgeMessage`.
nonisolated enum BridgeFrame {
    // MARK: - Capability Flags

    struct Capabilities: OptionSet {
        static let usbHost = Capabilities(rawValue: 1 << 0)
        static let autoDetect = Capabilities(rawValue: 1 << 1)
        static let setVerify = Capabilities(rawValue: 1 << 2)
        static let cwKeyer = Capabilities(rawValue: 1 << 3)

        let rawValue: UInt8
    }

    // MARK: - CW Keyer Types

    enum CWAckResult: UInt8 {
        case okay = 0x00
        case queued = 0x01
        case fail = 0x02
        case unsupported = 0x03
        case badSlot = 0x04
        case emptySlot = 0x05
    }

    struct CWProgressFlags: OptionSet {
        static let txActive = CWProgressFlags(rawValue: 1 << 0)
        static let draining = CWProgressFlags(rawValue: 1 << 1)
        static let complete = CWProgressFlags(rawValue: 1 << 2)

        let rawValue: UInt8
    }

    struct CWStatusResponse {
        let wpm: UInt8
        let bufferDepth: UInt8
        let flags: CWProgressFlags
        let slotCount: UInt8
    }

    // MARK: - Set-Verify Types

    enum SetResultCode: UInt8 {
        case okay = 0x00
        case fail = 0x01
        case unsupported = 0x02
    }

    // MARK: - Radio Protocol Types

    enum BridgeRadioProtocolType: UInt8 {
        case kenwood = 0x01
        case civ = 0x02
    }

    // MARK: - Universal Mode Enum

    /// Protocol-independent mode values shared with CW Bridge firmware.
    enum UniversalMode: UInt8 {
        case lsb = 0x01
        case usb = 0x02
        case cw = 0x03
        case fm = 0x04
        case am = 0x05
        case data = 0x06
        case cwR = 0x07

        // MARK: Internal

        static func from(carrierWaveMode: String) -> UniversalMode? {
            switch carrierWaveMode.uppercased() {
            case "LSB": .lsb
            case "USB",
                 "USB-D": .usb
            case "CW": .cw
            case "FM": .fm
            case "AM": .am
            case "DATA",
                 "RTTY",
                 "FT8",
                 "FT4",
                 "JTTY",
                 "PSK": .data
            case "CW-R": .cwR
            default: nil
            }
        }
    }

    // MARK: - Protocol Version

    static let protocolVersion: UInt32 = 2

    // MARK: - Frame Building (protobuf)

    static func buildHandshakeReq() -> Data {
        var msg = Cwbp_BridgeMessage()
        var req = Cwbp_HandshakeReq()
        req.protocolVersion = protocolVersion
        msg.msg = .handshakeReq(req)
        return (try? msg.serializedData()) ?? Data()
    }

    static func buildRequestDetect() -> Data {
        var msg = Cwbp_BridgeMessage()
        msg.msg = .requestDetect(Cwbp_RequestDetect())
        return (try? msg.serializedData()) ?? Data()
    }

    /// Ask the bridge to re-emit its current state (USB connect, detected
    /// radio, jack/battery). Used as a self-heal poll.
    static func buildStatusReq() -> Data {
        var msg = Cwbp_BridgeMessage()
        msg.msg = .statusReq(Cwbp_StatusReq())
        return (try? msg.serializedData()) ?? Data()
    }

    static func buildSetBaud(_ baudRate: UInt32) -> Data {
        var msg = Cwbp_BridgeMessage()
        var baud = Cwbp_SetBaud()
        baud.baudRate = baudRate
        msg.msg = .setBaud(baud)
        return (try? msg.serializedData()) ?? Data()
    }

    static func buildCatData(_ catBytes: Data) -> Data {
        var msg = Cwbp_BridgeMessage()
        var cat = Cwbp_CatData()
        cat.payload = catBytes
        msg.msg = .catData(cat)
        return (try? msg.serializedData()) ?? Data()
    }

    static func buildSetVerify(field: Cwbp_SetVerifyField, value: Data = Data()) -> Data {
        var msg = Cwbp_BridgeMessage()
        var verify = Cwbp_SetVerify()
        verify.field = field
        verify.value = value
        msg.msg = .setVerify(verify)
        return (try? msg.serializedData()) ?? Data()
    }

    // MARK: - CW Frame Builders

    static func buildCWSend(_ text: String) -> Data {
        var msg = Cwbp_BridgeMessage()
        var send = Cwbp_CwSend()
        send.text = text
        msg.msg = .cwSend(send)
        return (try? msg.serializedData()) ?? Data()
    }

    static func buildCWStop() -> Data {
        var msg = Cwbp_BridgeMessage()
        msg.msg = .cwStop(Cwbp_CwStop())
        return (try? msg.serializedData()) ?? Data()
    }

    static func buildCWSpeed(wpm: UInt8) -> Data {
        var msg = Cwbp_BridgeMessage()
        var speed = Cwbp_CwSpeed()
        speed.wpm = UInt32(wpm)
        msg.msg = .cwSpeed(speed)
        return (try? msg.serializedData()) ?? Data()
    }

    static func buildCWSlotPlay(slot: UInt8, context: [String: String] = [:]) -> Data {
        var msg = Cwbp_BridgeMessage()
        var play = Cwbp_CwSlotPlay()
        play.slot = UInt32(slot)
        play.context = context
        msg.msg = .cwSlotPlay(play)
        return (try? msg.serializedData()) ?? Data()
    }

    static func buildCWSlotSet(slot: UInt8, text: String) -> Data {
        var msg = Cwbp_BridgeMessage()
        var slotSet = Cwbp_CwSlotSet()
        slotSet.slot = UInt32(slot)
        slotSet.text = text
        msg.msg = .cwSlotSet(slotSet)
        return (try? msg.serializedData()) ?? Data()
    }

    static func buildCWStatusReq() -> Data {
        var msg = Cwbp_BridgeMessage()
        msg.msg = .cwStatusReq(Cwbp_CwStatusReq())
        return (try? msg.serializedData()) ?? Data()
    }

    // MARK: - Frame Parsing

    static func parse(_ data: Data) -> Cwbp_BridgeMessage? {
        try? Cwbp_BridgeMessage(serializedBytes: data)
    }
}

// MARK: - BridgeEvent

/// Events from the CW Bridge consumed by the RadioManager.
nonisolated enum BridgeEvent: Equatable {
    case handshakeComplete(fwVersion: String, capabilities: UInt8)
    case usbConnected
    case usbDisconnected
    case detecting
    case radioDetected(
        protocolType: BridgeFrame.BridgeRadioProtocolType,
        baudRate: UInt32,
        rawID: String
    )
    case detectionFailed
    case ready
    case bridgeError(String)
    case setVerifyResult(result: BridgeFrame.SetResultCode)
    case cwAck(result: BridgeFrame.CWAckResult, bufferDepth: UInt8)
    case cwProgress(bufferDepth: UInt8, flags: BridgeFrame.CWProgressFlags)
    case cwSpeedChanged(wpm: UInt8)
    case cwStatus(
        wpm: UInt8,
        bufferDepth: UInt8,
        flags: BridgeFrame.CWProgressFlags,
        slotCount: UInt8
    )
}

// MARK: - Protobuf → BridgeEvent Conversion

nonisolated extension BridgeFrame {
    static func event(from msg: Cwbp_BridgeMessage) -> BridgeEvent? {
        guard let variant = msg.msg else {
            return nil
        }

        switch variant {
        case let .handshakeRsp(rsp):
            return .handshakeComplete(
                fwVersion: rsp.firmwareVersion,
                capabilities: UInt8(rsp.capabilities & 0xFF)
            )

        case let .status(status):
            return statusEvent(from: status)

        case let .radioInfo(info):
            return radioInfoEvent(from: info)

        case let .setResult(result):
            guard let code = SetResultCode(rawValue: UInt8(result.result.rawValue)) else {
                return nil
            }
            return .setVerifyResult(result: code)

        case let .cwAck(ack):
            guard let result = CWAckResult(rawValue: UInt8(ack.result.rawValue)) else {
                return nil
            }
            return .cwAck(result: result, bufferDepth: UInt8(ack.bufDepth & 0xFF))

        case let .cwProgress(progress):
            let flags = CWProgressFlags(rawValue: UInt8(progress.flags & 0xFF))
            return .cwProgress(bufferDepth: UInt8(progress.bufDepth & 0xFF), flags: flags)

        case let .cwSpeed(speed):
            return .cwSpeedChanged(wpm: UInt8(speed.wpm & 0xFF))

        case let .cwStatusRsp(rsp):
            return .cwStatus(
                wpm: UInt8(rsp.wpm & 0xFF),
                bufferDepth: UInt8(rsp.bufDepth & 0xFF),
                flags: CWProgressFlags(rawValue: UInt8(rsp.flags & 0xFF)),
                slotCount: UInt8(rsp.slotCount & 0xFF)
            )

        default:
            return nil
        }
    }

    static func catPayload(from msg: Cwbp_BridgeMessage) -> Data? {
        guard case let .catData(cat) = msg.msg else {
            return nil
        }
        return cat.payload
    }

    // MARK: Private helpers

    private static func statusEvent(from status: Cwbp_Status) -> BridgeEvent? {
        switch status.code {
        case .statusUsbConnected: return .usbConnected
        case .statusUsbDisconnected: return .usbDisconnected
        case .statusDetecting: return .detecting
        case .statusDetectionFailed: return .detectionFailed
        case .statusReady: return .ready
        case .statusError:
            let detail = status.detail.isEmpty ? "Unknown error" : status.detail
            return .bridgeError(detail)
        default: return nil
        }
    }

    private static func radioInfoEvent(from info: Cwbp_RadioInfo) -> BridgeEvent? {
        let bridgeProto: BridgeRadioProtocolType? = switch info.protocol {
        case .protoKenwood: .kenwood
        case .protoCiv: .civ
        default: nil
        }
        guard let bridgeProto else {
            return nil
        }
        return .radioDetected(
            protocolType: bridgeProto,
            baudRate: info.baudRate,
            rawID: info.idString
        )
    }
}
