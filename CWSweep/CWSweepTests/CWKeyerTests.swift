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
