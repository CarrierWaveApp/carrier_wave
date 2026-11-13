import CarrierWaveData
@preconcurrency import Foundation
import Testing

// MARK: - FakeRadioControl

/// Deterministic stand-in for the slice of `RadioSession` the gateway uses.
/// Holds a settable `RadioState` and records writes, so reads-from-state and
/// write-through can be asserted without driving a live poll/receive loop.
private actor FakeRadioControl: RadioControlSurface {
    // MARK: Internal

    private(set) var tuned: [Double] = []
    private(set) var modes: [String] = []
    private(set) var raw: [String] = []

    func liveState() async -> RadioSession.RadioState {
        state
    }

    func tuneToFrequency(_ freqMHz: Double) async -> Bool {
        tuned.append(freqMHz)
        state.frequency = freqMHz
        return true
    }

    func setMode(_ mode: String, universalModeRawValue _: UInt8?) async -> Bool {
        modes.append(mode)
        state.mode = mode
        return true
    }

    func sendRaw(_ data: Data) async throws {
        raw.append(String(bytes: data, encoding: .utf8) ?? "")
    }

    func seed(frequencyMHz: Double, mode: String, power: UInt8) {
        state.frequency = frequencyMHz
        state.mode = mode
        state.powerLevel = power
    }

    // MARK: Private

    private var state = RadioSession.RadioState()
}

// MARK: - RadioSessionStateGatewayTests

struct RadioSessionStateGatewayTests {
    @Test("reads canonical values from live RadioState")
    func readsLiveState() async throws {
        let control = FakeRadioControl()
        await control.seed(frequencyMHz: 14.074, mode: "usb", power: 5)
        let gateway = RadioSessionStateGateway(control: control)
        #expect(try await gateway.currentValue(forKey: "vfoA") == "14074000")
        #expect(try await gateway.currentValue(forKey: "mode") == "USB")
        #expect(try await gateway.currentValue(forKey: "power") == "5")
    }

    @Test("unset state reads back as nil")
    func unsetStateIsNil() async throws {
        let gateway = RadioSessionStateGateway(control: FakeRadioControl())
        #expect(try await gateway.currentValue(forKey: "vfoA") == nil)
        #expect(try await gateway.currentValue(forKey: "power") == nil)
    }

    @Test("frequency and mode write through typed setters, not raw")
    func typedWrites() async throws {
        let control = FakeRadioControl()
        let gateway = RadioSessionStateGateway(control: control)
        #expect(try await gateway.apply(key: "vfoA", value: "7030000"))
        #expect(try await gateway.apply(key: "mode", value: "CW"))
        // Round-trip through the canonical string to avoid float equality.
        #expect(try await gateway.currentValue(forKey: "vfoA") == "7030000")
        #expect(await control.modes == ["CW"])
        #expect(await control.raw.isEmpty)
    }

    @Test("power falls back to raw ASCII via the field codec")
    func powerWritesRaw() async throws {
        let control = FakeRadioControl()
        let gateway = RadioSessionStateGateway(control: control)
        #expect(try await gateway.apply(key: "power", value: "10"))
        #expect(await control.raw == ["PC010;"])
    }

    @Test("full plan/apply/verify loop converges against a live-style gateway")
    func loopConverges() async throws {
        let control = FakeRadioControl()
        await control.seed(frequencyMHz: 14.074, mode: "USB", power: 5)
        let gateway = RadioSessionStateGateway(control: control)
        let planner = RadioStatePlanner(fields: RadioStateField.kx2Spike)
        let profile = RadioStateProfile(
            name: "40m CW",
            desired: ["vfoA": "7030000", "mode": "CW"]
        )
        let plan = try await planner.plan(profile: profile, gateway: gateway)
        #expect(plan.drift.count == 2)
        let failed = try await planner.apply(plan, gateway: gateway)
        #expect(failed.isEmpty)
        let after = try await planner.verify(profile: profile, gateway: gateway)
        #expect(after.isConverged)
    }
}
