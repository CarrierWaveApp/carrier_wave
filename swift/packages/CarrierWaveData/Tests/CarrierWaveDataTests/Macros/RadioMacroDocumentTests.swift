import CarrierWaveData
import Foundation
import Testing

struct RadioMacroDocumentTests {
    @Test func roundTripsViaJSON() throws {
        let spec = try RadioMacroSpec(
            id: #require(UUID(uuidString: "9F2C7B40-1E5C-4D12-BB6E-7C0F08E1A3F4")),
            name: "Start POTA — 40m CW",
            icon: "tree.fill",
            description: "Configure rig for QRP CW POTA on 40m.",
            tags: ["pota", "cw", "40m"],
            appliesTo: [.civ],
            author: "W6JY",
            capabilities: RadioMacroCapabilities(
                transmits: true,
                changesFrequency: true,
                changesMode: true,
                changesPower: true
            ),
            args: [
                RadioMacroArg(
                    name: "qrg_hz",
                    label: "Frequency (Hz)",
                    type: .frequency,
                    min: 7_000_000,
                    max: 7_300_000,
                    defaultValue: "7032000"
                ),
                RadioMacroArg(
                    name: "power_w",
                    label: "Power (W)",
                    type: .uint8,
                    min: 1, max: 100,
                    defaultValue: "5"
                ),
            ],
            steps: [
                .setMode(mode: "CW"),
                .setFrequency(hz: 7_032_000),
                .setPowerWatts(watts: 5),
                .vendorCommand(commandId: "civ.preamp", args: ["level": "one"]),
                .delay(durationMs: 250),
                .sendCW(text: "CQ POTA DE {arg.mycall} K"),
            ]
        )
        let original = RadioMacroDocument(macro: spec)
        let data = try original.encode(pretty: false)
        let decoded = try RadioMacroDocument.decode(from: data)
        #expect(decoded.format == RadioMacroDocument.currentFormat)
        #expect(decoded.macro == spec)
    }

    @Test func stepCodableShapeMatchesAuthoredJSON() throws {
        let jsonText = """
        {
          "kind": "vendorCommand",
          "commandId": "civ.preamp",
          "args": { "level": "one" }
        }
        """
        let step = try JSONDecoder().decode(RadioMacroStep.self, from: Data(jsonText.utf8))
        guard case let .vendorCommand(commandId, args) = step else {
            Issue.record("Decoded wrong case: \(step)")
            return
        }
        #expect(commandId == "civ.preamp")
        #expect(args == ["level": "one"])
    }

    @Test func setFrequencyCodableShape() throws {
        let jsonText = """
        { "kind": "setFrequency", "hz": 7032000 }
        """
        let step = try JSONDecoder().decode(RadioMacroStep.self, from: Data(jsonText.utf8))
        guard case let .setFrequency(hz) = step else {
            Issue.record("Decoded wrong case: \(step)")
            return
        }
        #expect(hz == 7_032_000)
    }

    @Test func v1DocumentIsRejected() {
        let v1 = """
        { "format": 1, "macro": { "id": "9F2C7B40-1E5C-4D12-BB6E-7C0F08E1A3F4", "name": "old" } }
        """
        #expect(throws: RadioMacroDocumentError.self) {
            _ = try RadioMacroDocument.decode(from: Data(v1.utf8))
        }
    }
}
