import CarrierWaveData
import Foundation
import Testing
@testable import CWSweep

// MARK: - CW Keyer Tests

@Test func keyerMacroExpansionMyCall() async {
    let keyer = CWKeyerService()
    let context = KeyerContext(
        myCall: "W6JSV",
        hisCall: "K3LR",
        serial: 42,
        exchange: "5 CA",
        frequency: 14.030
    )
    let expanded = await keyer.expandMacros("CQ DE {MYCALL} K", context: context)
    #expect(expanded == "CQ DE W6JSV K")
}

@Test func keyerMacroExpansionHisCall() async {
    let keyer = CWKeyerService()
    let context = KeyerContext(
        myCall: "W6JSV",
        hisCall: "K3LR",
        serial: 1,
        exchange: "",
        frequency: 14.030
    )
    let expanded = await keyer.expandMacros("{HISCALL} 5NN TU", context: context)
    #expect(expanded == "K3LR 5NN TU")
}

@Test func keyerMacroExpansionSerial() async {
    let keyer = CWKeyerService()
    let context = KeyerContext(
        myCall: "W6JSV",
        hisCall: "K3LR",
        serial: 42,
        exchange: "",
        frequency: 14.030
    )
    let expanded = await keyer.expandMacros("NR {NR}", context: context)
    #expect(expanded == "NR 042")
}

@Test func keyerMacroExpansionExchange() async {
    let keyer = CWKeyerService()
    let context = KeyerContext(
        myCall: "W6JSV",
        hisCall: "K3LR",
        serial: 1,
        exchange: "5 CA",
        frequency: 14.030
    )
    let expanded = await keyer.expandMacros("5NN {EXCH}", context: context)
    #expect(expanded == "5NN 5 CA")
}

@Test func keyerMacroExpansionFrequency() async {
    let keyer = CWKeyerService()
    let context = KeyerContext(
        myCall: "W6JSV",
        hisCall: "",
        serial: 1,
        exchange: "",
        frequency: 14.030
    )
    let expanded = await keyer.expandMacros("QSY {FREQ}", context: context)
    #expect(expanded == "QSY 14.0")
}

@Test func keyerDefaultMessages() async {
    let keyer = CWKeyerService()
    let msg = await keyer.message(for: 1)
    // Default F1 is CQ message
    #expect(msg.contains("{MYCALL}"))
}

@Test func keyerSetAndGetMessage() async {
    let keyer = CWKeyerService()
    await keyer.setMessage(slot: 12, text: "TEST MESSAGE")
    let msg = await keyer.message(for: 12)
    #expect(msg == "TEST MESSAGE")
}

// MARK: - Protocol Handler CW Encoding Tests

@Test func civEncodeSendCW() {
    let handler = CIVProtocolHandler(civAddress: 0x94)
    let data = handler.encodeSendCW("CQ")
    #expect(data != nil)
    if let data {
        let bytes = [UInt8](data)
        #expect(bytes.first == 0xFE) // CI-V preamble
        #expect(bytes.last == 0xFD) // CI-V terminator
        // Command 0x17 should be in there
        #expect(bytes.contains(0x17))
    }
}

@Test func kenwoodEncodeSendCW() {
    let handler = KenwoodProtocolHandler()
    let data = handler.encodeSendCW("TEST")
    #expect(data != nil)
    if let data, let str = String(data: data, encoding: .ascii) {
        #expect(str == "KY TEST;")
    }
}

@Test func elecraftEncodeSendCW() {
    let handler = ElecraftProtocolHandler()
    let data = handler.encodeSendCW("CQ")
    #expect(data != nil)
    if let data, let str = String(data: data, encoding: .ascii) {
        #expect(str == "KY CQ;")
    }
}

// MARK: - WinKeyer Handshake Validation

@Test func winKeyerHostOpenAcceptsWK3FirmwareByte() {
    #expect(WinKeyerProtocolEncoder.firmwareVersion(fromHostOpenReply: Data([31])) == 31)
}

@Test func winKeyerHostOpenAcceptsFirmwareFollowedByStatus() {
    #expect(WinKeyerProtocolEncoder.firmwareVersion(fromHostOpenReply: Data([23, 0xC0])) == 23)
}

@Test func winKeyerHostOpenRejectsEcho() {
    // A plain USB-serial chip that copies back what it receives
    let echo = WinKeyerProtocolEncoder.encodeHostOpen()
    #expect(WinKeyerProtocolEncoder.firmwareVersion(fromHostOpenReply: echo) == nil)
}

@Test func winKeyerHostOpenRejectsEmptyReply() {
    #expect(WinKeyerProtocolEncoder.firmwareVersion(fromHostOpenReply: Data()) == nil)
}

@Test func winKeyerHostOpenRejectsImplausibleByte() {
    #expect(WinKeyerProtocolEncoder.firmwareVersion(fromHostOpenReply: Data([0xC0])) == nil)
    #expect(WinKeyerProtocolEncoder.firmwareVersion(fromHostOpenReply: Data([0x02])) == nil)
}

@Test func winKeyerEchoErrorNamesThePort() {
    let error = WinKeyerSessionError.notAWinKeyer(
        portPath: "/dev/cu.usbserial-1",
        reply: WinKeyerProtocolEncoder.encodeHostOpen()
    )
    #expect(error.errorDescription?.contains("echoed") == true)
}

@Test func winKeyerSetWK3ModeIsAdmin20NotFirmwareUpdate() {
    // WK3 Datasheet v1.2: admin 16 (0x10) is Firmware Update; 20 (0x14) is Set WK3 Mode
    #expect(WinKeyerProtocolEncoder.encodeSetWK3Mode() == Data([0x00, 0x14]))
}
