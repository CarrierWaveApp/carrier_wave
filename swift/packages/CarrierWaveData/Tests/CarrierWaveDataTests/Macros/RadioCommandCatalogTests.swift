import CarrierWaveData
import Foundation
import Testing

struct RadioCommandCatalogTests {
    // MARK: Internal

    @Test func loadsBundledCommands() {
        let catalog = loadedCatalog()
        #expect(catalog.command(id: "civ.preamp") != nil)
        #expect(catalog.command(id: "civ.attenuator") != nil)
        #expect(catalog.command(id: "kw.menu") != nil)
    }

    @Test func encodesPreampOnPayload() throws {
        let catalog = loadedCatalog()
        let spec = try #require(catalog.command(id: "civ.preamp"))
        let payload = try spec.encodePayload(args: ["level": "one"], context: .preview)
        #expect(Array(payload) == [0x16, 0x02, 0x01])
    }

    @Test func encodesAttenuatorEnumWithDefault() throws {
        let catalog = loadedCatalog()
        let spec = try #require(catalog.command(id: "civ.attenuator"))
        // No args -> default "off" -> 0x00
        let payload = try spec.encodePayload(args: [:], context: .preview)
        #expect(Array(payload) == [0x11, 0x00])
    }

    @Test func encodesBooleanAsHex2() throws {
        let catalog = loadedCatalog()
        let spec = try #require(catalog.command(id: "civ.noiseBlanker"))
        let payloadOn = try spec.encodePayload(args: ["enabled": "true"], context: .preview)
        let payloadOff = try spec.encodePayload(args: ["enabled": "false"], context: .preview)
        #expect(Array(payloadOn) == [0x16, 0x22, 0x01])
        #expect(Array(payloadOff) == [0x16, 0x22, 0x00])
    }

    @Test func encodesMemoryChannelAsBCD() throws {
        let catalog = loadedCatalog()
        let spec = try #require(catalog.command(id: "civ.selectMemory"))
        // bcd2 = 2 bytes = 4 digits, LSB-first. "12" → "0012" → bytes ["00","12"] reversed
        // ⇒ "12 00".
        let payload = try spec.encodePayload(args: ["channel": "12"], context: .preview)
        #expect(Array(payload) == [0x08, 0x12, 0x00])
    }

    @Test func encodesContextValueInTemplate() throws {
        // Use {FREQ_KHZ}-style context tokens inside an arg to a vendor command.
        let catalog = loadedCatalog()
        let spec = try #require(catalog.command(id: "civ.selectMemory"))
        let context = MacroContext(currentFreqHz: 7_032_000)
        // Channel "{FREQ_KHZ}"... 7032 wouldn't fit (max 99). Use a bound check.
        #expect(throws: RadioCommandCatalogError.self) {
            _ = try spec.encodePayload(args: ["channel": "{FREQ_KHZ}"], context: context)
        }
    }

    @Test func unknownEnumValueThrows() throws {
        let catalog = loadedCatalog()
        let spec = try #require(catalog.command(id: "civ.preamp"))
        #expect(throws: RadioCommandCatalogError.self) {
            _ = try spec.encodePayload(args: ["level": "three"], context: .preview)
        }
    }

    @Test func kenwoodMenuEncodesAsASCII() throws {
        let catalog = loadedCatalog()
        let spec = try #require(catalog.command(id: "kw.menu"))
        let payload = try spec.encodePayload(
            args: ["item": "066", "value": "1"], context: .preview
        )
        let text = String(data: payload, encoding: .ascii)
        #expect(text == "EX0660001")
    }

    // MARK: Private

    private func loadedCatalog() -> RadioCommandCatalog {
        let catalog = RadioCommandCatalog()
        catalog.loadBundled()
        return catalog
    }
}
