import CarrierWaveData
import Foundation
import SwiftData
import Testing

@MainActor
struct RadioMacroJournalTests {
    // MARK: - Helpers

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(CarrierWaveSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func sampleSpec(id: UUID = UUID()) -> RadioMacroSpec {
        RadioMacroSpec(
            id: id,
            name: "QRP CW POTA",
            icon: "tree.fill",
            description: "QRP CW POTA setup",
            tags: ["pota", "cw"],
            appliesTo: [.civ],
            author: "W6JY",
            capabilities: RadioMacroCapabilities(
                transmits: true,
                changesFrequency: true,
                changesMode: true,
                changesPower: true
            ),
            args: [],
            steps: [
                .setMode(mode: "CW"),
                .setFrequency(hz: 7_032_000),
                .setPowerWatts(watts: 5),
            ]
        )
    }

    // MARK: - Tests

    @Test func journalOperationCodableRoundTrip() throws {
        let id = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let spec = Self.sampleSpec(id: id)
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let fields = RadioMacroFields(
            id: id,
            spec: spec,
            tombstoned: false,
            tombstoneReason: nil,
            modifiedAt: modifiedAt,
            sortOrder: 7
        )
        let op = JournalOperation.upsertRadioMacro(fields)

        #expect(op.entityType == .radioMacro)
        #expect(op.entityId == id)
        #expect(op.entityModifiedAt == modifiedAt)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(op)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(JournalOperation.self, from: data)

        #expect(decoded.entityType == .radioMacro)
        #expect(decoded.entityId == id)
        guard case let .upsertRadioMacro(decodedFields) = decoded else {
            Issue.record("Expected .upsertRadioMacro case after decoding")
            return
        }
        #expect(decodedFields.id == id)
        #expect(decodedFields.spec.name == "QRP CW POTA")
        #expect(decodedFields.spec.steps.count == 3)
        #expect(decodedFields.sortOrder == 7)
        #expect(decodedFields.tombstoned == false)
        #expect(decodedFields.modifiedAt == modifiedAt)
    }

    @Test func radioMacroFromSpecRoundTrip() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let id = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let spec = Self.sampleSpec(id: id)
        let macro = RadioMacro.from(spec: spec, sortOrder: 3)
        context.insert(macro)
        try context.save()

        #expect(macro.id == id)
        #expect(macro.name == "QRP CW POTA")
        #expect(macro.steps.count == 3)
        #expect(macro.sortOrder == 3)
        #expect(macro.cloudDirtyFlag == false)

        // Fetch back and confirm persisted shape survives the round-trip.
        let macroID = id
        var desc = FetchDescriptor<RadioMacro>(
            predicate: #Predicate { $0.id == macroID }
        )
        desc.fetchLimit = 1
        let fetched = try #require(try context.fetch(desc).first)
        #expect(fetched.name == "QRP CW POTA")
        #expect(fetched.steps.count == 3)
        #expect(fetched.appliesTo == [.civ])

        // Round-trip through toSpec() — the same call extractRadioMacroFields uses.
        let recoveredSpec = fetched.toSpec()
        #expect(recoveredSpec.name == spec.name)
        #expect(recoveredSpec.steps.count == spec.steps.count)
        #expect(recoveredSpec.appliesTo == spec.appliesTo)
        #expect(recoveredSpec.capabilities.transmits == true)
    }

    @Test func radioMacroFieldsEncodeIncludesNestedSpec() throws {
        let id = UUID()
        let spec = Self.sampleSpec(id: id)
        let fields = RadioMacroFields(
            id: id,
            spec: spec,
            tombstoned: true,
            tombstoneReason: "retracted",
            modifiedAt: Date(timeIntervalSince1970: 1_700_001_000),
            sortOrder: 0
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(fields)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(RadioMacroFields.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.tombstoned == true)
        #expect(decoded.tombstoneReason == "retracted")
        #expect(decoded.spec.steps.count == 3)
    }
}
