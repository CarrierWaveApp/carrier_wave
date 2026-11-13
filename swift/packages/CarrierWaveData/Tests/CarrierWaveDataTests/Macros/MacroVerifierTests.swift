import CarrierWaveData
import Foundation
import Testing

struct MacroVerifierTests {
    @Test func declaredNonTransmitWithPTTStepFails() {
        let spec = RadioMacroSpec(
            name: "lie",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(transmits: false),
            steps: [.setPTT(on: true)]
        )
        let issues = MacroVerifier.verify(spec)
        #expect(issues.contains {
            $0.severity == .error && $0.message.contains("transmits")
        })
    }

    @Test func frequencyArgWithoutBoundsFails() {
        let spec = RadioMacroSpec(
            name: "open freq",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(changesFrequency: true),
            args: [
                RadioMacroArg(name: "freq", type: .frequency),
            ],
            steps: [.setFrequency(hz: 7_032_000)]
        )
        let issues = MacroVerifier.verify(spec)
        #expect(issues.contains {
            $0.severity == .error && $0.message.contains("min/max")
        })
    }

    @Test func nonAsciiInSendCWIsError() {
        let spec = RadioMacroSpec(
            name: "dash",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(transmits: true),
            steps: [.sendCW(text: "CQ — DE W6JY")]
        )
        let issues = MacroVerifier.verify(spec)
        #expect(issues.contains {
            $0.severity == .error && $0.message.contains("ASCII")
        })
    }

    @Test func delayOver30sIsError() {
        let spec = RadioMacroSpec(
            name: "long",
            appliesTo: [.civ],
            steps: [.delay(durationMs: 60_000)]
        )
        let issues = MacroVerifier.verify(spec)
        #expect(issues.contains {
            $0.severity == .error && $0.message.contains("30000")
        })
    }

    @Test func rawBytesCivPttOnFloorsTransmits() {
        let spec = RadioMacroSpec(
            name: "lying",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(transmits: false, usesRawBytes: true),
            steps: [.rawBytes(protocol: "civ", bytes: "FE FE 94 E0 1C 00 01 FD")]
        )
        let issues = MacroVerifier.verify(spec)
        #expect(issues.contains {
            $0.severity == .error && $0.message.contains("transmits")
        })
    }

    @Test func rawBytesUnknownPayloadFloorsTransmits() {
        let spec = RadioMacroSpec(
            name: "unknown",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(transmits: false, usesRawBytes: true),
            steps: [.rawBytes(protocol: "civ", bytes: "FE FE 94 E0 AA BB CC FD")]
        )
        let issues = MacroVerifier.verify(spec)
        #expect(issues.contains {
            $0.severity == .error && $0.message.contains("transmits")
        })
    }

    @Test func cleanMacroProducesNoIssues() {
        let spec = RadioMacroSpec(
            name: "ok",
            appliesTo: [.civ],
            capabilities: RadioMacroCapabilities(
                transmits: true,
                changesFrequency: true,
                changesMode: true
            ),
            args: [
                RadioMacroArg(
                    name: "qrg",
                    type: .frequency,
                    min: 7_000_000,
                    max: 7_300_000,
                    defaultValue: "7032000"
                ),
            ],
            steps: [
                .setMode(mode: "CW"),
                .setFrequency(hz: 7_032_000),
                .setPTT(on: true),
                .sendCW(text: "CQ DE W6JY"),
            ]
        )
        let issues = MacroVerifier.verify(spec)
        #expect(issues.isEmpty)
    }

    // MARK: - Shared fixture corpus

    /// Runs the JSON-driven verifier corpus that both Swift (now) and Rust
    /// (Plan D) consume. Keeping the contract in JSON ensures the two
    /// verifier implementations stay in lockstep — a Rust regression that
    /// passes goldens but diverges from Swift will fail this test once the
    /// Rust side starts loading the same file.
    @Test func runsSharedFixture() throws {
        guard let url = Bundle.module.url(
            forResource: "macro-verifier-cases",
            withExtension: "json"
        ) else {
            Issue.record("fixture not found in test bundle")
            return
        }
        let data = try Data(contentsOf: url)

        struct Fixture: Decodable {
            let cases: [Case]
        }
        struct Case: Decodable {
            let name: String
            let spec: RadioMacroSpec
            let expect: Expect
        }
        struct Expect: Decodable {
            let issues: [ExpectIssue]
        }
        struct ExpectIssue: Decodable {
            let severity: String
            let messageContains: String
        }

        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        for testCase in fixture.cases {
            let actual = MacroVerifier.verify(testCase.spec)
            if testCase.expect.issues.isEmpty {
                #expect(
                    !actual.contains(where: { $0.severity == .error }),
                    "case \(testCase.name): expected no errors, got \(actual)"
                )
            } else {
                for expected in testCase.expect.issues {
                    let matched = actual.contains { issue in
                        String(describing: issue.severity) == expected.severity
                            && issue.message.contains(expected.messageContains)
                    }
                    #expect(
                        matched,
                        "case \(testCase.name): expected issue \(expected), got \(actual)"
                    )
                }
            }
        }
    }
}
