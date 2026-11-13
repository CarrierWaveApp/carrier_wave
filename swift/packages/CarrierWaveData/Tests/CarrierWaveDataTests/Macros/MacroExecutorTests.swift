import CarrierWaveData
@preconcurrency import Foundation
import Testing

// MARK: - RecordingSink

private actor RecordingSink: MacroExecutorSink {
    // MARK: Lifecycle

    init(passThroughVendor: Bool = false) {
        self.passThroughVendor = passThroughVendor
    }

    // MARK: Internal

    enum Event: Equatable {
        case setFrequencyHz(UInt64)
        case setMode(String)
        case setPowerWatts(UInt64)
        case setPTT(Bool)
        case sendCW(String)
        case sendVendorCommand(String, [String: String])
        case sendRawBytes(String, String)
    }

    var events: [Event] = []
    /// When true, vendor commands fall through to the catalog path so we can
    /// observe the framed raw-bytes output.
    var passThroughVendor: Bool

    var connectedProtocol: RadioCommandProtocol? {
        .civ
    }

    var civAddress: UInt8? {
        0xA4
    } // IC-7300

    func setFrequencyHz(_ hz: UInt64) async -> Bool {
        events.append(.setFrequencyHz(hz))
        return true
    }

    func setMode(_ mode: String) async -> Bool {
        events.append(.setMode(mode))
        return true
    }

    func setPowerWatts(_ watts: UInt64) async -> Bool {
        events.append(.setPowerWatts(watts))
        return true
    }

    func setPTT(_ on: Bool) async -> Bool {
        events.append(.setPTT(on))
        return true
    }

    func sendCW(_ text: String) async -> Bool {
        events.append(.sendCW(text))
        return true
    }

    func sendVendorCommand(commandId: String, args: [String: String]) async -> Bool {
        if passThroughVendor {
            return false
        }
        events.append(.sendVendorCommand(commandId, args))
        return true
    }

    func sendRawBytes(protocolName: String, hexBytes: String) async throws {
        events.append(.sendRawBytes(protocolName, hexBytes))
    }

    func readField(_: String) async -> String? {
        nil
    }
}

// MARK: - KenwoodSink

private actor KenwoodSink: MacroExecutorSink {
    var lastBytes: String?

    var connectedProtocol: RadioCommandProtocol? {
        .kenwood
    }

    var civAddress: UInt8? {
        nil
    }

    func setFrequencyHz(_: UInt64) async -> Bool {
        true
    }

    func setMode(_: String) async -> Bool {
        true
    }

    func setPowerWatts(_: UInt64) async -> Bool {
        true
    }

    func setPTT(_: Bool) async -> Bool {
        true
    }

    func sendCW(_: String) async -> Bool {
        true
    }

    func sendVendorCommand(commandId _: String, args _: [String: String]) async -> Bool {
        // Fall through to catalog → raw bytes path so the test can inspect
        // the framed Kenwood ASCII command.
        false
    }

    func sendRawBytes(protocolName _: String, hexBytes: String) async throws {
        lastBytes = hexBytes
    }

    func readField(_: String) async -> String? {
        nil
    }
}

// MARK: - MacroExecutorTests

struct MacroExecutorTests {
    // MARK: Internal

    @Test func dispatchesTypedStepsInOrder() async throws {
        let sink = RecordingSink()
        let spec = RadioMacroSpec(
            name: "test",
            steps: [
                .setMode(mode: "CW"),
                .setFrequency(hz: 7_032_000),
                .setPowerWatts(watts: 5),
                .setPTT(on: true),
                .delay(durationMs: 10),
            ]
        )
        let executor = MacroExecutor(catalog: loadedCatalog(), sleep: { _ in })
        _ = try await executor.execute(
            macro: spec,
            context: .preview,
            runtimeArgs: [:],
            sink: sink
        )
        let events = await sink.events
        #expect(events == [
            .setMode("CW"),
            .setFrequencyHz(7_032_000),
            .setPowerWatts(5),
            .setPTT(true),
            .setPTT(false),
        ])
    }

    @Test func releasesPTTOnSuccessEvenWithoutTransmitStep() async throws {
        let sink = RecordingSink()
        let spec = RadioMacroSpec(
            name: "no-tx",
            steps: [
                .setFrequency(hz: 7_032_000),
            ]
        )
        let executor = MacroExecutor(catalog: loadedCatalog(), sleep: { _ in })
        _ = try await executor.execute(
            macro: spec,
            context: .preview,
            runtimeArgs: [:],
            sink: sink
        )
        let events = await sink.events
        #expect(events == [.setFrequencyHz(7_032_000), .setPTT(false)])
    }

    @Test func resolvesArgPlaceholderInString() async throws {
        let sink = RecordingSink()
        let spec = RadioMacroSpec(
            name: "test",
            args: [
                RadioMacroArg(name: "mycall", type: .string, defaultValue: "W6JY"),
            ],
            steps: [
                .sendCW(text: "CQ {arg.mycall} K"),
            ]
        )
        let executor = MacroExecutor(catalog: loadedCatalog(), sleep: { _ in })
        _ = try await executor.execute(
            macro: spec,
            context: .preview,
            runtimeArgs: [:],
            sink: sink
        )
        let events = await sink.events
        #expect(events == [.sendCW("CQ W6JY K"), .setPTT(false)])
    }

    @Test func resolvesCtxPlaceholderInString() async throws {
        let sink = RecordingSink()
        let spec = RadioMacroSpec(
            name: "test",
            steps: [
                .sendCW(text: "DE {ctx.myCall} K"),
            ]
        )
        let executor = MacroExecutor(catalog: loadedCatalog(), sleep: { _ in })
        _ = try await executor.execute(
            macro: spec,
            context: .preview,
            runtimeArgs: [:],
            sink: sink
        )
        let events = await sink.events
        #expect(events == [.sendCW("DE W6JY K"), .setPTT(false)])
    }

    @Test func vendorCommandDeliveredToSink() async throws {
        let sink = RecordingSink(passThroughVendor: false)
        let spec = RadioMacroSpec(
            name: "test",
            appliesTo: [.civ],
            steps: [
                .vendorCommand(commandId: "civ.preamp", args: ["level": "one"]),
            ]
        )
        let executor = MacroExecutor(catalog: loadedCatalog(), sleep: { _ in })
        _ = try await executor.execute(
            macro: spec,
            context: .preview,
            runtimeArgs: [:],
            sink: sink
        )
        let events = await sink.events
        #expect(events == [.sendVendorCommand("civ.preamp", ["level": "one"]), .setPTT(false)])
    }

    @Test func vendorFallthroughFramesCIVCommand() async throws {
        let sink = RecordingSink(passThroughVendor: true)
        let spec = RadioMacroSpec(
            name: "test",
            appliesTo: [.civ],
            steps: [
                .vendorCommand(commandId: "civ.preamp", args: ["level": "one"]),
            ]
        )
        let executor = MacroExecutor(catalog: loadedCatalog(), sleep: { _ in })
        _ = try await executor.execute(
            macro: spec,
            context: .preview,
            runtimeArgs: [:],
            sink: sink
        )
        let events = await sink.events
        // FE FE A4 E0 16 02 01 FD
        #expect(events == [.sendRawBytes("civ", "FE FE A4 E0 16 02 01 FD"), .setPTT(false)])
    }

    @Test func protocolMismatchAborts() async {
        let sink = KenwoodSink()
        let spec = RadioMacroSpec(
            name: "test",
            appliesTo: [.civ],
            steps: [
                .vendorCommand(commandId: "civ.preamp", args: ["level": "one"]),
            ]
        )
        let executor = MacroExecutor(catalog: loadedCatalog(), sleep: { _ in })
        await #expect(throws: MacroExecutorError.self) {
            _ = try await executor.execute(
                macro: spec,
                context: .preview,
                runtimeArgs: [:],
                sink: sink
            )
        }
    }

    @Test func missingRequiredArgThrows() async {
        let sink = RecordingSink()
        let spec = RadioMacroSpec(
            name: "test",
            args: [
                RadioMacroArg(name: "mycall", type: .string),
            ],
            steps: [
                .sendCW(text: "CQ {arg.mycall} K"),
            ]
        )
        let executor = MacroExecutor(catalog: loadedCatalog(), sleep: { _ in })
        await #expect(throws: MacroExecutorError.self) {
            _ = try await executor.execute(
                macro: spec,
                context: .preview,
                runtimeArgs: [:],
                sink: sink
            )
        }
    }

    @Test func argRangeValidated() async {
        let sink = RecordingSink()
        let spec = RadioMacroSpec(
            name: "test",
            args: [
                RadioMacroArg(name: "pwr", type: .uint8, min: 1, max: 100, defaultValue: "200"),
            ],
            steps: [
                .setPowerWatts(watts: 5),
            ]
        )
        let executor = MacroExecutor(catalog: loadedCatalog(), sleep: { _ in })
        await #expect(throws: MacroExecutorError.self) {
            _ = try await executor.execute(
                macro: spec,
                context: .preview,
                runtimeArgs: [:],
                sink: sink
            )
        }
    }

    @Test func assertFailureRaisesError() async {
        let sink = RecordingSink()
        let spec = RadioMacroSpec(
            name: "test",
            args: [
                RadioMacroArg(name: "ready", type: .bool, defaultValue: "false"),
            ],
            steps: [
                .assert(expr: "{arg.ready}", message: "must be ready"),
            ]
        )
        let executor = MacroExecutor(catalog: loadedCatalog(), sleep: { _ in })
        await #expect(throws: MacroExecutorError.self) {
            _ = try await executor.execute(
                macro: spec,
                context: .preview,
                runtimeArgs: [:],
                sink: sink
            )
        }
    }

    // MARK: Private

    private func loadedCatalog() -> RadioCommandCatalog {
        let catalog = RadioCommandCatalog()
        catalog.loadBundled()
        return catalog
    }
}
