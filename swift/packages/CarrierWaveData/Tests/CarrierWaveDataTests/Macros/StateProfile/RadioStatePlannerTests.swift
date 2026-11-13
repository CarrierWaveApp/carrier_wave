import CarrierWaveData
@preconcurrency import Foundation
import Testing

// MARK: - MockKX2

/// In-memory stand-in for an Elecraft KX2 over Kenwood ASCII CAT. Holds a
/// register per command prefix; `query` echoes `PREFIX + payload + ";"`,
/// `send` overwrites the register from a SET command. Lets the planner's
/// read/diff/apply/verify loop run with no BLE bridge.
private actor MockKX2: RadioStateTransport {
    // MARK: Lifecycle

    init(initial: [String: String]) {
        registers = initial
    }

    // MARK: Internal

    func query(_ command: String) async throws -> String {
        let prefix = Self.prefix(of: command)
        let payload = registers[prefix] ?? ""
        return "\(prefix)\(payload);"
    }

    func send(_ command: String) async throws {
        let prefix = Self.prefix(of: command)
        var body = command
        if body.hasSuffix(";") {
            body.removeLast()
        }
        registers[prefix] = String(body.dropFirst(prefix.count))
    }

    func payload(for prefix: String) -> String? {
        registers[prefix]
    }

    // MARK: Private

    private var registers: [String: String]

    private static func prefix(of command: String) -> String {
        String(command.prefix(while: { $0.isLetter }))
    }
}

// MARK: - RadioStatePlannerTests

struct RadioStatePlannerTests {
    // MARK: Internal

    @Test("refresh parses Elecraft ASCII into canonical values")
    func refreshParses() async throws {
        let radio = MockKX2(initial: ["FA": "00014074000", "MD": "2", "PC": "005"])
        let current = try await planner.refresh(keys: ["vfoA", "mode", "power"], gateway: gateway(radio))
        #expect(current["vfoA"] == "14074000")
        #expect(current["mode"] == "USB")
        #expect(current["power"] == "5")
    }

    @Test("refresh skips write-only fields")
    func refreshSkipsUnreadable() async throws {
        let radio = MockKX2(initial: ["RG": "200"])
        let current = try await planner.refresh(keys: ["rfGain"], gateway: gateway(radio))
        #expect(current.isEmpty)
    }

    @Test("plan reports only drifted readable settings")
    func planDiffs() async throws {
        // Radio sits on 20 m USB 5 W; profile wants 40 m CW 5 W.
        let radio = MockKX2(initial: ["FA": "00014074000", "MD": "2", "PC": "005"])
        let profile = RadioStateProfile(
            name: "40m CW",
            desired: ["vfoA": "7030000", "mode": "CW", "power": "5"]
        )
        let plan = try await planner.plan(profile: profile, gateway: gateway(radio))
        #expect(plan.drift.count == 2)
        #expect(plan.isConverged == false)
        #expect(plan.actions.contains(.noChange(key: "power", value: "5")))
        #expect(plan.actions.contains(.update(key: "vfoA", from: "14074000", to: "7030000")))
        #expect(plan.actions.contains(.update(key: "mode", from: "USB", to: "CW")))
    }

    @Test("compile emits one step per change, none for converged settings")
    func compileDiffOnly() async throws {
        let radio = MockKX2(initial: ["FA": "00014074000", "MD": "2", "PC": "005"])
        let profile = RadioStateProfile(
            name: "40m CW",
            desired: ["vfoA": "7030000", "mode": "CW", "power": "5"]
        )
        let plan = try await planner.plan(profile: profile, gateway: gateway(radio))
        let spec = try planner.compile(plan, name: profile.name)
        #expect(spec.steps.count == 2)
        #expect(spec.steps.contains(.rawBytes(protocol: "kenwood", bytes: "FA00007030000;")))
        #expect(spec.steps.contains(.rawBytes(protocol: "kenwood", bytes: "MD3;")))
        #expect(spec.appliesTo == [.kenwood])
    }

    @Test("apply then verify converges")
    func applyConverges() async throws {
        let radio = MockKX2(initial: ["FA": "00014074000", "MD": "2", "PC": "005"])
        let profile = RadioStateProfile(
            name: "40m CW",
            desired: ["vfoA": "7030000", "mode": "CW", "power": "10"]
        )
        let plan = try await planner.plan(profile: profile, gateway: gateway(radio))
        let failed = try await planner.apply(plan, gateway: gateway(radio))
        #expect(failed.isEmpty)
        let after = try await planner.verify(profile: profile, gateway: gateway(radio))
        #expect(after.isConverged)
        #expect(after.drift.isEmpty)
        #expect(await radio.payload(for: "FA") == "00007030000")
        #expect(await radio.payload(for: "MD") == "3")
        #expect(await radio.payload(for: "PC") == "010")
    }

    @Test("write-only setting is applied blindly and flagged unverifiable")
    func blindApplyPath() async throws {
        let radio = MockKX2(initial: ["FA": "00014074000"])
        let profile = RadioStateProfile(name: "rfgain", desired: ["rfGain": "200"])
        let plan = try await planner.plan(profile: profile, gateway: gateway(radio))
        #expect(plan.unverifiable == ["rfGain"])
        #expect(plan.isConverged) // no readable drift
        let failed = try await planner.apply(plan, gateway: gateway(radio))
        #expect(failed.isEmpty)
        // The SET still went out to the radio...
        #expect(await radio.payload(for: "RG") == "200")
        // ...but a re-plan can never confirm it, so it stays a blindApply.
        let after = try await planner.verify(profile: profile, gateway: gateway(radio))
        #expect(after.unverifiable == ["rfGain"])
    }

    @Test("unparseable read reports update from unknown")
    func unparseableReadIsUpdate() async throws {
        // Radio returns an empty FA payload — readable, but nothing to parse.
        let radio = MockKX2(initial: [:])
        let profile = RadioStateProfile(name: "freq", desired: ["vfoA": "7030000"])
        let plan = try await planner.plan(profile: profile, gateway: gateway(radio))
        #expect(plan.actions == [.update(key: "vfoA", from: nil, to: "7030000")])
    }

    @Test("unknown profile key throws")
    func unknownKeyThrows() async throws {
        let radio = MockKX2(initial: [:])
        let profile = RadioStateProfile(name: "bogus", desired: ["nope": "1"])
        await #expect(throws: RadioStatePlanError.self) {
            try await planner.plan(profile: profile, gateway: gateway(radio))
        }
    }

    // MARK: Private

    private let planner = RadioStatePlanner(fields: RadioStateField.kx2Spike)

    private func gateway(_ transport: RadioStateTransport) -> CatalogStateGateway {
        CatalogStateGateway(transport: transport, fields: RadioStateField.kx2Spike)
    }
}
