import CarrierWaveData
import Foundation
import Testing

struct MacroImportCoordinatorTests {
    // MARK: Internal

    @Test func acceptsCleanMacro() async throws {
        let spec = RadioMacroSpec(
            name: "Clean tune-only",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(changesFrequency: true),
            args: [],
            steps: [.setFrequency(hz: 7_032_000)]
        )
        let data = try encode(RadioMacroDocument(macro: spec))
        let coordinator = MacroImportCoordinator()
        let outcome = await coordinator.evaluate(documentData: data, provenance: .airDrop)
        switch outcome {
        case let .readyToInstall(decoded, provenance, requiresRawBytes):
            #expect(decoded.name == "Clean tune-only")
            #expect(provenance == .airDrop)
            #expect(requiresRawBytes == false)
        case let .rejected(reason):
            Issue.record("Expected readyToInstall, got rejected: \(reason)")
        }
    }

    @Test func rejectsInvalidJSON() async {
        let coordinator = MacroImportCoordinator()
        let outcome = await coordinator.evaluate(
            documentData: Data("not json at all".utf8),
            provenance: .files
        )
        switch outcome {
        case let .rejected(reason):
            #expect(reason.contains("Invalid macro document JSON"))
        case .readyToInstall:
            Issue.record("Expected rejection for non-JSON payload")
        }
    }

    @Test func rejectsUnsupportedFormat() async throws {
        // Hand-craft a document JSON with format=99 — bypasses the
        // RadioMacroDocument(format:macro:) initializer so we test the
        // decode error path directly.
        let json: [String: Any] = [
            "format": 99,
            "macro": [
                "id": UUID().uuidString,
                "name": "Future macro",
                "capabilities": ["transmits": false],
                "args": [],
                "steps": [],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let coordinator = MacroImportCoordinator()
        let outcome = await coordinator.evaluate(documentData: data, provenance: .files)
        switch outcome {
        case let .rejected(reason):
            #expect(reason.contains("newer Carrier Wave"))
            #expect(reason.contains("99"))
        case .readyToInstall:
            Issue.record("Expected rejection for format=99")
        }
    }

    @Test func rejectsCapabilityLying() async throws {
        // Declared capabilities are empty, but steps include PTT-on — the
        // verifier infers transmits=true and the dominance check refuses.
        let spec = RadioMacroSpec(
            name: "Sneaky transmit",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(),
            args: [],
            steps: [.setPTT(on: true)]
        )
        let data = try encode(RadioMacroDocument(macro: spec))
        let coordinator = MacroImportCoordinator()
        let outcome = await coordinator.evaluate(documentData: data, provenance: .other(label: "test"))
        switch outcome {
        case let .rejected(reason):
            #expect(reason.contains("Capability declarations") || reason.lowercased().contains("transmit"))
        case .readyToInstall:
            Issue.record("Expected rejection — capabilities don't dominate inferred")
        }
    }

    @Test func flagsRawBytesAcceptanceRequirement() async throws {
        let spec = RadioMacroSpec(
            name: "Raw passthrough",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(transmits: true, usesRawBytes: true),
            args: [],
            steps: [.rawBytes(protocol: "civ", bytes: "FE FE A4 E0 1A FD")]
        )
        let data = try encode(RadioMacroDocument(macro: spec))
        let coordinator = MacroImportCoordinator()
        let outcome = await coordinator.evaluate(
            documentData: data,
            provenance: .registry(slug: "icom-preamp-on")
        )
        switch outcome {
        case let .readyToInstall(_, provenance, requiresRawBytes):
            #expect(requiresRawBytes == true)
            if case let .registry(slug) = provenance {
                #expect(slug == "icom-preamp-on")
            } else {
                Issue.record("Expected registry provenance, got \(provenance)")
            }
        case let .rejected(reason):
            Issue.record("Expected readyToInstall for known-opcode raw bytes, got rejected: \(reason)")
        }
    }

    // MARK: Private

    private func encode(_ document: RadioMacroDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }
}
