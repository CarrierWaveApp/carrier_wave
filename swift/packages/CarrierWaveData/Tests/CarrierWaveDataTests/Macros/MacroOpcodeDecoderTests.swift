import CarrierWaveData
import Foundation
import Testing

@Suite("RadioMacroOpcodeTable")
struct MacroOpcodeDecoderTests {
    @Test func civPttOnIsTransmit() {
        let table = RadioMacroOpcodeTable.load(for: "civ")
        let caps = table.capabilities(forBytesHex: "FE FE 94 E0 1C 00 01 FD")
        #expect(caps.transmits)
    }

    @Test func civPttOffNotTransmit() {
        let table = RadioMacroOpcodeTable.load(for: "civ")
        let caps = table.capabilities(forBytesHex: "FE FE 94 E0 1C 00 00 FD")
        #expect(!caps.transmits)
    }

    @Test func civSetFrequencyMatches() {
        let table = RadioMacroOpcodeTable.load(for: "civ")
        let caps = table.capabilities(forBytesHex: "FE FE 94 E0 05 00 32 70 14 FD")
        #expect(caps.changesFrequency)
    }

    @Test func unknownPayloadFlagsAsUnrecognized() {
        let table = RadioMacroOpcodeTable.load(for: "civ")
        let bytes = "FE FE 94 E0 AA BB CC FD"
        #expect(!table.allRecognized(forBytesHex: bytes))
    }

    @Test func kenwoodTxIsTransmit() {
        let table = RadioMacroOpcodeTable.load(for: "kenwood")
        let caps = table.capabilities(forBytesHex: "54 58 3B")
        #expect(caps.transmits)
    }

    @Test func malformedHexReturnsEmpty() {
        let table = RadioMacroOpcodeTable.load(for: "civ")
        let caps = table.capabilities(forBytesHex: "ZZ ZZ")
        #expect(!caps.transmits && !caps.changesFrequency)
    }
}
