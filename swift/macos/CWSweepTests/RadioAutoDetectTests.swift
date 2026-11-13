import Foundation
import Testing
@testable import CWSweep

// MARK: - Cable hint tests

@Test func cableHintsHasFTDI() {
    let ftdi = RadioAutoDetect.cableHints.first { $0.vendorId == 0x0403 && $0.productId == 0x6015 }
    #expect(ftdi != nil)
    #expect(ftdi?.bauds.first == 38_400)
}

@Test func cableHintsHasCP2102() {
    let cp = RadioAutoDetect.cableHints.first { $0.vendorId == 0x10C4 && $0.productId == 0xEA60 }
    #expect(cp != nil)
    #expect(cp?.bauds.contains(19_200) == true)
}

@Test func candidateBaudsFallsBackToDefault() {
    let bauds = RadioAutoDetect.candidateBauds(vendorId: 0xDEAD, productId: 0xBEEF)
    #expect(bauds == RadioAutoDetect.defaultBauds)
}

@Test func candidateBaudsUsesHintWhenMatched() {
    let bauds = RadioAutoDetect.candidateBauds(vendorId: 0x1A86, productId: 0x7523)
    #expect(bauds.first == 9_600)
}

@Test func candidateBaudsFallsBackWhenNilIdentifiers() {
    let bauds = RadioAutoDetect.candidateBauds(vendorId: nil, productId: nil)
    #expect(bauds == RadioAutoDetect.defaultBauds)
}

// MARK: - Kenwood ID parsing

@Test func parseKenwoodIDExtractsThreeDigitID() {
    let buffer = Data("ID020;".utf8)
    #expect(RadioAutoDetect.parseKenwoodID(buffer) == "ID020")
}

@Test func parseKenwoodIDExtractsYaesuFourDigitID() {
    let buffer = Data("ID0650;".utf8)
    #expect(RadioAutoDetect.parseKenwoodID(buffer) == "ID0650")
}

@Test func parseKenwoodIDIgnoresOwnEcho() {
    // The probe sends "ID;"; the response begins with the echo.
    let buffer = Data("ID;ID017;".utf8)
    #expect(RadioAutoDetect.parseKenwoodID(buffer) == "ID017")
}

@Test func parseKenwoodIDReturnsNilOnGarbage() {
    let buffer = Data("garbage".utf8)
    #expect(RadioAutoDetect.parseKenwoodID(buffer) == nil)
}

@Test func parseKenwoodIDRejectsNonDigitPayload() {
    let buffer = Data("IDxx;".utf8)
    #expect(RadioAutoDetect.parseKenwoodID(buffer) == nil)
}

// MARK: - Yaesu vs Kenwood

@Test func isYaesuIDDifferentiatesByLength() {
    #expect(RadioAutoDetect.isYaesuID("ID0650") == true)
    #expect(RadioAutoDetect.isYaesuID("ID020") == false)
    #expect(RadioAutoDetect.isYaesuID("ID017") == false)
    #expect(RadioAutoDetect.isYaesuID("XX1234") == false)
}

// MARK: - CI-V parsing

@Test func parseCIVResponseExtractsRadioAddress() {
    // Skip our own echo (FE FE 00 E0 ... FD), then a real reply addressed to E0 from A4.
    let echo: [UInt8] = [0xFE, 0xFE, 0x00, 0xE0, 0x19, 0x00, 0xFD]
    let reply: [UInt8] = [0xFE, 0xFE, 0xE0, 0xA4, 0x19, 0x00, 0x00, 0x70, 0x30, 0x00, 0xFD]
    let data = Data(echo + reply)
    #expect(RadioAutoDetect.parseCIVResponse(data) == 0xA4)
}

@Test func parseCIVResponseSkipsEchoOnly() {
    let echo: [UInt8] = [0xFE, 0xFE, 0x00, 0xE0, 0x19, 0x00, 0xFD]
    #expect(RadioAutoDetect.parseCIVResponse(Data(echo)) == nil)
}

@Test func parseCIVResponseReturnsNilOnEmpty() {
    #expect(RadioAutoDetect.parseCIVResponse(Data()) == nil)
}

@Test func parseCIVResponseRequiresFDTerminator() {
    // FE FE preamble, addressed to us, but missing FD terminator.
    let truncated: [UInt8] = [0xFE, 0xFE, 0xE0, 0x94, 0x19, 0x00, 0x01, 0x02]
    #expect(RadioAutoDetect.parseCIVResponse(Data(truncated)) == nil)
}

// MARK: - Name lookup

@Test func kenwoodIDNameRecognisesKnownIDs() {
    #expect(RadioAutoDetect.kenwoodIDName("ID017") == "Elecraft K3/KX")
    #expect(RadioAutoDetect.kenwoodIDName("ID0650") == "Yaesu FT-891")
    #expect(RadioAutoDetect.kenwoodIDName("ID999") == nil)
}

@Test func civAddressNameRecognisesIcom() {
    #expect(RadioAutoDetect.civAddressName(0xA4) == "Icom IC-7300")
    #expect(RadioAutoDetect.civAddressName(0x94) == "Icom IC-705")
    #expect(RadioAutoDetect.civAddressName(0x12) == nil)
}

// MARK: - Result → RadioProfile

@Test func detectResultMapsToProfile() {
    let result = RadioAutoDetect.Result(
        protocolType: .civ,
        baudRate: 19_200,
        civAddress: 0xA4,
        rawID: "A4",
        radioName: "Icom IC-7300"
    )
    let profile = result.toProfile(portPath: "/dev/cu.usbserial-1234")
    #expect(profile.protocolType == .civ)
    #expect(profile.baudRate == 19_200)
    #expect(profile.civAddress == 0xA4)
    #expect(profile.serialPortPath == "/dev/cu.usbserial-1234")
    #expect(profile.dtrSignal == true)
    #expect(profile.rtsSignal == true)
}

@Test func detectResultElecraftDoesNotAssertControlLines() {
    // Elecraft K3 enters TEST mode if DTR/RTS are asserted at open.
    let result = RadioAutoDetect.Result(
        protocolType: .elecraft, baudRate: 38_400, civAddress: nil,
        rawID: "ID017", radioName: "Elecraft K3/KX"
    )
    let profile = result.toProfile(portPath: "/dev/cu.test")
    #expect(profile.dtrSignal == false)
    #expect(profile.rtsSignal == false)
}
