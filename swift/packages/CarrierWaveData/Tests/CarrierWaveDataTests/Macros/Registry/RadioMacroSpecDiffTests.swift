import CarrierWaveData
import Foundation
import Testing

struct RadioMacroSpecDiffTests {
    // MARK: Internal

    @Test func returnsEmptyArrayWhenSpecsMatch() {
        let spec = makeSpec()
        #expect(RadioMacroSpecDiff.diff(local: spec, remote: spec).isEmpty)
    }

    @Test func surfacesNameChange() {
        let local = makeSpec(name: "Old")
        let remote = makeSpec(name: "New")
        let changes = RadioMacroSpecDiff.diff(local: local, remote: remote)
        #expect(changes.contains { $0.field == "Name" && $0.before == "Old" && $0.after == "New" })
    }

    @Test func capabilityFlagsExpandToPerFlagRows() {
        let local = makeSpec(transmits: false)
        let remote = makeSpec(transmits: true)
        let changes = RadioMacroSpecDiff.diff(local: local, remote: remote)
        let transmitChange = try? #require(changes.first(where: { $0.field == "Capability: Transmits" }))
        #expect(transmitChange?.before == "No")
        #expect(transmitChange?.after == "Yes")
    }

    @Test func detectsAddedStep() {
        let local = makeSpec(steps: [.setFrequency(hz: 7_032_000)])
        let remote = makeSpec(steps: [
            .setFrequency(hz: 7_032_000),
            .delay(durationMs: 250),
        ])
        let changes = RadioMacroSpecDiff.diff(local: local, remote: remote)
        let added = try? #require(changes.first(where: { $0.field == "Step 2 (added)" }))
        #expect(added?.before == nil)
        #expect(added?.after?.contains("Wait") == true)
    }

    @Test func detectsRemovedStep() {
        let local = makeSpec(steps: [
            .setFrequency(hz: 7_032_000),
            .delay(durationMs: 250),
        ])
        let remote = makeSpec(steps: [.setFrequency(hz: 7_032_000)])
        let changes = RadioMacroSpecDiff.diff(local: local, remote: remote)
        let removed = try? #require(changes.first(where: { $0.field == "Step 2 (removed)" }))
        #expect(removed?.before?.contains("Wait") == true)
        #expect(removed?.after == nil)
    }

    @Test func detectsChangedStep() {
        let local = makeSpec(steps: [.setFrequency(hz: 7_032_000)])
        let remote = makeSpec(steps: [.setFrequency(hz: 7_035_000)])
        let changes = RadioMacroSpecDiff.diff(local: local, remote: remote)
        let step = try? #require(changes.first(where: { $0.field == "Step 1" }))
        #expect(step?.before?.contains("7.032000") == true)
        #expect(step?.after?.contains("7.035000") == true)
    }

    // MARK: Private

    // MARK: Helpers

    private func makeSpec(
        name: String = "Tune",
        transmits: Bool = false,
        steps: [RadioMacroStep] = []
    ) -> RadioMacroSpec {
        RadioMacroSpec(
            name: name,
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(transmits: transmits),
            args: [],
            steps: steps
        )
    }
}
