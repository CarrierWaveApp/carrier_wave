import CarrierWaveData
import Foundation
import Testing

struct MacroSpecHashTests {
    @Test func sameStepsHashEqual_ignoringMetadata() {
        let aaa = RadioMacroSpec(
            id: UUID(),
            name: "Alpha",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(transmits: true),
            args: [],
            steps: [.setPTT(on: true)]
        )
        let bbb = RadioMacroSpec(
            id: UUID(),
            name: "Bravo",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(transmits: true),
            args: [],
            steps: [.setPTT(on: true)]
        )
        #expect(MacroSpecHash.canonical(aaa) == MacroSpecHash.canonical(bbb))
        #expect(!MacroSpecHash.canonical(aaa).isEmpty)
    }

    @Test func differentStepsHashDiffer() {
        let aaa = RadioMacroSpec(
            id: UUID(),
            name: "Same name",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(transmits: true),
            args: [],
            steps: [.setPTT(on: true)]
        )
        let bbb = RadioMacroSpec(
            id: UUID(),
            name: "Same name",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(transmits: true),
            args: [],
            steps: [.setPTT(on: false)]
        )
        #expect(MacroSpecHash.canonical(aaa) != MacroSpecHash.canonical(bbb))
    }

    @Test func hashIsHex64Chars() throws {
        let spec = RadioMacroSpec(
            id: UUID(),
            name: "Hex test",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(),
            args: [],
            steps: [.setPTT(on: true)]
        )
        let digest = MacroSpecHash.canonical(spec)
        #expect(digest.count == 64)
        #expect(try digest.allSatisfy(\.isHexDigit))
    }
}
