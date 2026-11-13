import CarrierWaveData
import Foundation
import Testing

// MARK: - StubEnv

private struct StubEnv: MacroSafetyEnvironment {
    let connectedProtocol: RadioCommandProtocol?
    let sessionAllowsTx: Bool
    let globalInhibitTx: Bool
    let deviceRegion: String
}

// MARK: - Helpers

private func usEnv(
    connected: RadioCommandProtocol? = .civ,
    sessionAllowsTx: Bool = true,
    globalInhibitTx: Bool = false
) -> StubEnv {
    StubEnv(
        connectedProtocol: connected,
        sessionAllowsTx: sessionAllowsTx,
        globalInhibitTx: globalInhibitTx,
        deviceRegion: "US"
    )
}

// MARK: - MacroSafetyGateTests

struct MacroSafetyGateTests {
    @Test func cleanMacroAllowed() async {
        // 40m at 7.032 MHz, US, civ, declared capabilities consistent with steps.
        let spec = RadioMacroSpec(
            name: "tune 40m",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(
                transmits: false,
                changesFrequency: true
            ),
            steps: [.setFrequency(hz: 7_032_000)]
        )
        let decision = await MacroSafetyGate.evaluate(
            spec: spec,
            resolvedArgs: [:],
            environment: usEnv()
        )
        #expect(decision.outcome == .allow)
        #expect(decision.postSubstitutionFreqIssues.isEmpty)
    }

    @Test func protocolMismatchRequiresConfirmation() async {
        let spec = RadioMacroSpec(
            name: "civ only",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(changesFrequency: true),
            steps: [.setFrequency(hz: 7_032_000)]
        )
        let decision = await MacroSafetyGate.evaluate(
            spec: spec,
            resolvedArgs: [:],
            environment: usEnv(connected: .kenwood)
        )
        guard case let .allowWithConfirmation(reason) = decision.outcome else {
            Issue.record("Expected confirmation, got \(decision.outcome)")
            return
        }
        #expect(reason.contains("civ"))
        #expect(reason.contains("kenwood"))
    }

    @Test func capabilityLyingRefuses() async {
        // Declares transmits=false but steps include setPTT(on: true).
        let spec = RadioMacroSpec(
            name: "lie",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(transmits: false),
            steps: [.setPTT(on: true)]
        )
        let decision = await MacroSafetyGate.evaluate(
            spec: spec,
            resolvedArgs: [:],
            environment: usEnv()
        )
        guard case let .refuse(reason) = decision.outcome else {
            Issue.record("Expected refusal, got \(decision.outcome)")
            return
        }
        #expect(reason.contains("transmits"))
    }

    @Test func freqOutsideUSBandRefuses() async {
        // 152 MHz is outside every US amateur band.
        let spec = RadioMacroSpec(
            name: "qrg arg",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(changesFrequency: true),
            args: [
                RadioMacroArg(
                    name: "qrg",
                    type: .frequency,
                    min: 0,
                    max: 1_000_000_000
                ),
            ],
            steps: [.setFrequency(hz: 0)]
        )
        let decision = await MacroSafetyGate.evaluate(
            spec: spec,
            resolvedArgs: ["arg.qrg": "152000000"],
            environment: usEnv()
        )
        guard case let .refuse(reason) = decision.outcome else {
            Issue.record("Expected refusal, got \(decision.outcome)")
            return
        }
        #expect(reason.contains("US"))
        #expect(reason.contains("152000000"))
    }

    @Test func txInhibitRefuses() async {
        let spec = RadioMacroSpec(
            name: "ptt",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(transmits: true),
            steps: [.setPTT(on: true)]
        )
        let decision = await MacroSafetyGate.evaluate(
            spec: spec,
            resolvedArgs: [:],
            environment: usEnv(globalInhibitTx: true)
        )
        guard case let .refuse(reason) = decision.outcome else {
            Issue.record("Expected refusal, got \(decision.outcome)")
            return
        }
        #expect(reason.contains("Inhibit Transmit"))
    }

    @Test func txArmRequestsConfirmation() async {
        let spec = RadioMacroSpec(
            name: "ptt",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(transmits: true),
            steps: [.setPTT(on: true)]
        )
        let decision = await MacroSafetyGate.evaluate(
            spec: spec,
            resolvedArgs: [:],
            environment: usEnv(sessionAllowsTx: false)
        )
        guard case let .allowWithConfirmation(reason) = decision.outcome else {
            Issue.record("Expected confirmation, got \(decision.outcome)")
            return
        }
        #expect(reason.contains("PTT"))
    }

    @Test func multipleFreqIssuesEnumerated() async {
        let spec = RadioMacroSpec(
            name: "two freqs",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(changesFrequency: true),
            args: [
                RadioMacroArg(
                    name: "primary",
                    type: .frequency,
                    min: 0,
                    max: 1_000_000_000
                ),
                RadioMacroArg(
                    name: "secondary",
                    type: .frequency,
                    min: 0,
                    max: 1_000_000_000
                ),
            ],
            steps: [.setFrequency(hz: 0)]
        )
        let decision = await MacroSafetyGate.evaluate(
            spec: spec,
            resolvedArgs: [
                "arg.primary": "152000000",
                "arg.secondary": "200000000",
            ],
            environment: usEnv()
        )
        guard case let .refuse(reason) = decision.outcome else {
            Issue.record("Expected refusal, got \(decision.outcome)")
            return
        }
        #expect(reason.contains("primary"))
        #expect(reason.contains("secondary"))
        #expect(decision.postSubstitutionFreqIssues.count == 2)
    }

    @Test func disconnectedProtocolSkipsProtocolMismatch() async {
        let spec = RadioMacroSpec(
            name: "civ only",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(changesFrequency: true),
            steps: [.setFrequency(hz: 7_032_000)]
        )
        let decision = await MacroSafetyGate.evaluate(
            spec: spec,
            resolvedArgs: [:],
            environment: usEnv(connected: nil)
        )
        #expect(decision.outcome == .allow)
    }

    @Test func postSubstitutionFreqIssuesArrayPopulated() async {
        let spec = RadioMacroSpec(
            name: "qrg arg",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(changesFrequency: true),
            args: [
                RadioMacroArg(
                    name: "qrg",
                    type: .freqHz,
                    min: 0,
                    max: 1_000_000_000
                ),
            ],
            steps: [.setFrequency(hz: 0)]
        )
        let decision = await MacroSafetyGate.evaluate(
            spec: spec,
            resolvedArgs: ["arg.qrg": "152000000"],
            environment: usEnv()
        )
        #expect(decision.postSubstitutionFreqIssues.count == 1)
        #expect(decision.postSubstitutionFreqIssues.first?.contains("qrg") == true)
        #expect(decision.postSubstitutionFreqIssues.first?.contains("152000000") == true)
    }
}
