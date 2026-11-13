import CarrierWaveCore
import SwiftProtobuf
import UIKit

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
        /// CW Sat Bridge: satellite doppler schedule executor.
        static let satDoppler = Capabilities(rawValue: 1 << 5)

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

    /// Parsed CW status response.
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

    enum RadioProtocolType: UInt8 {
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

        /// Convert from a Carrier Wave mode string (e.g. "CW", "USB").
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
                 "PSK": .data
            case "CW-R": .cwR
            default: nil
            }
        }
    }

    /// Header + metadata for one uploaded pass schedule.
    struct SatScheduleHeader {
        let scheduleID: UInt32
        let satName: String
        let direction: Cwbp_SatLinkDirection
        let totalSteps: UInt32
        let durationMs: UInt64
        let downlinkStartHz: UInt64
        let uplinkStartHz: UInt64
        let downlinkMode: UniversalMode
        let uplinkMode: UniversalMode
        /// CTCSS in tenths of Hz (670 = 67.0 Hz); 0 = none.
        let uplinkToneDHz: UInt32
    }

    // MARK: - Protocol Version

    static let protocolVersion: UInt32 = 2

    // MARK: - Satellite Doppler Frame Builders (CW Sat Bridge)

    /// `seq` value the bridge uses to ack a SatScheduleBegin.
    static let satBeginAckSeq: UInt32 = .max

    // MARK: - Frame Building (protobuf)

    /// Build a HANDSHAKE_REQ message.
    static func buildHandshakeReq() -> Data {
        var msg = Cwbp_BridgeMessage()
        var req = Cwbp_HandshakeReq()
        req.protocolVersion = protocolVersion
        msg.msg = .handshakeReq(req)
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build a REQUEST_DETECT message.
    static func buildRequestDetect() -> Data {
        var msg = Cwbp_BridgeMessage()
        msg.msg = .requestDetect(Cwbp_RequestDetect())
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build a STATUS_REQ message — asks the bridge to re-emit its current
    /// state (USB connect, detected radio, jack status, battery). Used to
    /// recover from missed/raced status pushes.
    static func buildStatusReq() -> Data {
        var msg = Cwbp_BridgeMessage()
        msg.msg = .statusReq(Cwbp_StatusReq())
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build a SET_BAUD message.
    static func buildSetBaud(_ baudRate: UInt32) -> Data {
        var msg = Cwbp_BridgeMessage()
        var baud = Cwbp_SetBaud()
        baud.baudRate = baudRate
        msg.msg = .setBaud(baud)
        return (try? msg.serializedData()) ?? Data()
    }

    /// Wrap raw CAT bytes in a CAT_DATA message.
    static func buildCatData(_ catBytes: Data) -> Data {
        var msg = Cwbp_BridgeMessage()
        var cat = Cwbp_CatData()
        cat.payload = catBytes
        msg.msg = .catData(cat)
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build a SET_VERIFY message with a semantic field and value.
    static func buildSetVerify(field: Cwbp_SetVerifyField, value: Data = Data()) -> Data {
        var msg = Cwbp_BridgeMessage()
        var verify = Cwbp_SetVerify()
        verify.field = field
        verify.value = value
        msg.msg = .setVerify(verify)
        return (try? msg.serializedData()) ?? Data()
    }

    // MARK: - CW Frame Builders

    /// Build a CW_SEND message with the text to transmit.
    static func buildCWSend(_ text: String) -> Data {
        var msg = Cwbp_BridgeMessage()
        var send = Cwbp_CwSend()
        send.text = text
        msg.msg = .cwSend(send)
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build a CW_STOP message to abort transmission.
    static func buildCWStop() -> Data {
        var msg = Cwbp_BridgeMessage()
        msg.msg = .cwStop(Cwbp_CwStop())
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build a CW_SPEED message.
    static func buildCWSpeed(wpm: UInt8) -> Data {
        var msg = Cwbp_BridgeMessage()
        var speed = Cwbp_CwSpeed()
        speed.wpm = UInt32(wpm)
        msg.msg = .cwSpeed(speed)
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build a CW_SLOT_PLAY message with optional template context.
    static func buildCWSlotPlay(slot: UInt8, context: [String: String] = [:]) -> Data {
        var msg = Cwbp_BridgeMessage()
        var play = Cwbp_CwSlotPlay()
        play.slot = UInt32(slot)
        play.context = context
        msg.msg = .cwSlotPlay(play)
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build a CW_SLOT_SET message to store text in a memory slot.
    static func buildCWSlotSet(slot: UInt8, text: String) -> Data {
        var msg = Cwbp_BridgeMessage()
        var slotSet = Cwbp_CwSlotSet()
        slotSet.slot = UInt32(slot)
        slotSet.text = text
        msg.msg = .cwSlotSet(slotSet)
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build a CW_STATUS_REQ message.
    static func buildCWStatusReq() -> Data {
        var msg = Cwbp_BridgeMessage()
        msg.msg = .cwStatusReq(Cwbp_CwStatusReq())
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build a SAT_BEGIN message starting a schedule upload.
    static func buildSatBegin(_ header: SatScheduleHeader) -> Data {
        var msg = Cwbp_BridgeMessage()
        var begin = Cwbp_SatScheduleBegin()
        begin.scheduleID = header.scheduleID
        begin.satName = header.satName
        begin.direction = header.direction
        begin.totalSteps = header.totalSteps
        begin.durationMs = UInt32(clamping: header.durationMs)
        begin.downlinkStartHz = header.downlinkStartHz
        begin.uplinkStartHz = header.uplinkStartHz
        begin.downlinkMode = UInt32(header.downlinkMode.rawValue)
        begin.uplinkMode = UInt32(header.uplinkMode.rawValue)
        begin.uplinkToneDhz = header.uplinkToneDHz
        msg.msg = .satBegin(begin)
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build one SAT_CHUNK of packed steps (stop-and-wait after each).
    static func buildSatChunk(scheduleID: UInt32, seq: UInt32, steps: Data) -> Data {
        var msg = Cwbp_BridgeMessage()
        var chunk = Cwbp_SatScheduleChunk()
        chunk.scheduleID = scheduleID
        chunk.seq = seq
        chunk.steps = steps
        msg.msg = .satChunk(chunk)
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build a SAT_START arming the loaded schedule.
    static func buildSatStart(scheduleID: UInt32, aosInMs: UInt64, elapsedMs: UInt64) -> Data {
        var msg = Cwbp_BridgeMessage()
        var start = Cwbp_SatStart()
        start.scheduleID = scheduleID
        start.aosInMs = aosInMs
        start.elapsedMs = elapsedMs
        msg.msg = .satStart(start)
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build a SAT_ABORT cancelling the armed/running pass.
    static func buildSatAbort() -> Data {
        var msg = Cwbp_BridgeMessage()
        msg.msg = .satAbort(Cwbp_SatAbort())
        return (try? msg.serializedData()) ?? Data()
    }

    /// Build a SAT_SET_VFO — 0 = downlink (VFO A), 1 = uplink (VFO B).
    static func buildSatSetVfo(uplink: Bool) -> Data {
        var msg = Cwbp_BridgeMessage()
        var setVfo = Cwbp_SatSetActiveVfo()
        setVfo.vfo = uplink ? 1 : 0
        msg.msg = .satSetVfo(setVfo)
        return (try? msg.serializedData()) ?? Data()
    }

    // MARK: - Frame Parsing (protobuf)

    /// Parse a BLE notification as a protobuf BridgeMessage.
    /// Returns nil if the data cannot be decoded.
    static func parse(_ data: Data) -> Cwbp_BridgeMessage? {
        try? Cwbp_BridgeMessage(serializedBytes: data)
    }
}

// MARK: - BridgeEvent

/// Events from the CW Bridge, consumed by RadioService.
nonisolated enum BridgeEvent: Equatable {
    /// Handshake completed — bridge is running CWBP.
    case handshakeComplete(fwVersion: String, capabilities: UInt8)

    /// USB-serial device connected on the bridge.
    case usbConnected

    /// USB-serial device disconnected.
    case usbDisconnected

    /// Bridge is probing for radio identity.
    case detecting

    /// Radio detected — includes protocol type and raw ID string.
    case radioDetected(
        protocolType: BridgeFrame.RadioProtocolType,
        baudRate: UInt32,
        rawID: String
    )

    /// Radio detection failed (no response at any baud/protocol).
    case detectionFailed

    /// Bridge is fully operational (USB + radio detected + ready).
    case ready

    /// Error from the bridge.
    case bridgeError(String)

    /// Set-and-verify result from the bridge.
    case setVerifyResult(result: BridgeFrame.SetResultCode)

    /// CW keyer command acknowledged.
    case cwAck(result: BridgeFrame.CWAckResult, bufferDepth: UInt8)

    /// CW keyer buffer progress update.
    case cwProgress(bufferDepth: UInt8, flags: BridgeFrame.CWProgressFlags)

    /// CW speed changed (encoder rotation on the bridge).
    case cwSpeedChanged(wpm: UInt8)

    /// CW keyer status response.
    case cwStatus(
        wpm: UInt8,
        bufferDepth: UInt8,
        flags: BridgeFrame.CWProgressFlags,
        slotCount: UInt8
    )

    /// Sat bridge: ack for a schedule Begin (`seq == BridgeFrame.satBeginAckSeq`)
    /// or a step chunk.
    case satAck(scheduleID: UInt32, seq: UInt32, result: Cwbp_SatAckResult, stepsLoaded: UInt32)

    /// Sat bridge: executor state push.
    case satStatus(SatBridgeStatus)
}

// MARK: - SatBridgeStatus

/// Decoded SatStatus payload — the sat bridge executor's live state.
nonisolated struct SatBridgeStatus: Equatable {
    let state: Cwbp_SatRunState
    let scheduleID: UInt32
    let stepIndex: UInt32
    let downlinkHz: UInt64
    let uplinkHz: UInt64
    /// Negative = ms until AOS (countdown); positive = elapsed into the pass.
    let tMs: Int64
    let detail: String
}

// MARK: - Protobuf → BridgeEvent Conversion

nonisolated extension BridgeFrame {
    /// Convert a decoded protobuf message into a BridgeEvent.
    /// Returns nil for client→bridge messages or unrecognized types.
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

        case let .satAck(ack):
            return satAckEvent(from: ack)

        case let .satStatus(status):
            return satStatusEvent(from: status)

        default:
            return nil
        }
    }

    /// Extract raw CAT payload from a CatData message.
    static func catPayload(from msg: Cwbp_BridgeMessage) -> Data? {
        guard case let .catData(cat) = msg.msg else {
            return nil
        }
        return cat.payload
    }

    // MARK: Private helpers

    private static func satAckEvent(from ack: Cwbp_SatScheduleAck) -> BridgeEvent {
        .satAck(
            scheduleID: ack.scheduleID,
            seq: ack.seq,
            result: ack.result,
            stepsLoaded: ack.stepsLoaded
        )
    }

    private static func satStatusEvent(from status: Cwbp_SatStatus) -> BridgeEvent {
        .satStatus(SatBridgeStatus(
            state: status.state,
            scheduleID: status.scheduleID,
            stepIndex: status.stepIndex,
            downlinkHz: status.downlinkHz,
            uplinkHz: status.uplinkHz,
            tMs: status.tMs,
            detail: status.detail
        ))
    }

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
        let bridgeProto: RadioProtocolType? = switch info.protocol {
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
