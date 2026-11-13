import Foundation
import OSLog

// MARK: - MacroExecutorError

public enum MacroExecutorError: Error, Equatable, Sendable {
    case noRadioConnected
    case protocolMismatch(expected: [RadioCommandProtocol], connected: RadioCommandProtocol)
    case template(MacroTemplateError)
    case catalog(RadioCommandCatalogError)
    case stepFailed(stepIndex: Int, kind: RadioMacroStep.Kind, reason: String)
    case missingCIVAddress
    case cancelled
    case missingRequiredArg(name: String)
    case invalidArgValue(name: String, value: String, expected: String)
    case argOutOfRange(name: String, value: String, min: Int?, max: Int?)
    case sinkRefused(String)
    case assertionFailed(message: String, stepIndex: Int)
    case format(String)
}

// MARK: - MacroExecutorSink

/// Abstraction over the radio surface that a macro dispatches into. The iOS
/// app wires this to `RadioSession`; tests pass a recording mock. Keeping
/// the sink protocol-based lets the executor unit-test cleanly without a
/// live BLE bridge.
public protocol MacroExecutorSink: Sendable {
    /// The protocol of the currently connected radio, or nil if not connected.
    var connectedProtocol: RadioCommandProtocol? { get async }

    /// CI-V slave address of the connected radio. Required to frame `.civ`
    /// vendor commands and raw CI-V bytes.
    var civAddress: UInt8? { get async }

    func setFrequencyHz(_ hz: UInt64) async -> Bool
    func setMode(_ mode: String) async -> Bool
    func setPowerWatts(_ watts: UInt64) async -> Bool
    func setPTT(_ on: Bool) async -> Bool
    func sendCW(_ text: String) async -> Bool
    func sendVendorCommand(commandId: String, args: [String: String]) async -> Bool
    func sendRawBytes(protocolName: String, hexBytes: String) async throws
    func readField(_ field: String) async -> String?
}

/// Default no-op for sinks that don't yet implement field reads. Plan B sinks
/// will override.
public extension MacroExecutorSink {
    func readField(_: String) async -> String? {
        nil
    }

    func sendVendorCommand(commandId _: String, args _: [String: String]) async -> Bool {
        true
    }
}

// MARK: - MacroExecutionReport

public struct MacroExecutionReport: Sendable, Equatable {
    // MARK: Lifecycle

    public init(executedSteps: Int = 0, skippedSteps: Int = 0, elapsed: TimeInterval = 0) {
        self.executedSteps = executedSteps
        self.skippedSteps = skippedSteps
        self.elapsed = elapsed
    }

    // MARK: Public

    public var executedSteps: Int
    public var skippedSteps: Int
    public var elapsed: TimeInterval
}

// MARK: - MacroExecutor

/// Runs a `RadioMacroSpec` against a `MacroExecutorSink`. Stateless across
/// runs — instantiate, call `execute`, discard.
public struct MacroExecutor: Sendable {
    // MARK: Lifecycle

    public init(
        catalog: RadioCommandCatalog = .shared,
        sleep: @escaping @Sendable (UInt32) async -> Void = { ms in
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
        }
    ) {
        self.catalog = catalog
        self.sleep = sleep
    }

    // MARK: Public

    public let catalog: RadioCommandCatalog
    public let sleep: @Sendable (UInt32) async -> Void

    public func execute(
        macro spec: RadioMacroSpec,
        context: MacroContext,
        runtimeArgs: [String: String],
        sink: MacroExecutorSink
    ) async throws -> MacroExecutionReport {
        let start = Date()
        let resolvedArgs = try resolveArgs(spec: spec, callerArgs: runtimeArgs)
        let connected = await sink.connectedProtocol
        try checkProtocol(spec: spec, connected: connected)

        let engine = MacroTemplateEngine(args: spec.args)
        // Namespaced template values: arg.<name> from caller args, ctx.<name>
        // populated incrementally by `readField` and seeded from context.
        var values: [String: String] = [:]
        for (key, value) in resolvedArgs {
            values["arg.\(key)"] = value
        }
        for (token, value) in context.namespacedTokens() {
            values["ctx.\(token)"] = value
        }

        var executed = 0
        do {
            for (index, step) in spec.steps.enumerated() {
                try Task.checkCancellation()
                try await dispatch(
                    step: step,
                    index: index,
                    engine: engine,
                    values: &values,
                    sink: sink
                )
                executed += 1
            }
        } catch {
            // Spec safety: drop PTT on any failure exit.
            _ = await sink.setPTT(false)
            throw error
        }
        // Spec safety: drop PTT on success too. Macros that never raise PTT
        // see a harmless no-op; macros that do raise PTT are guaranteed not
        // to leave the radio keyed if the last step forgot to release.
        _ = await sink.setPTT(false)
        return MacroExecutionReport(
            executedSteps: executed,
            skippedSteps: spec.steps.count - executed,
            elapsed: Date().timeIntervalSince(start)
        )
    }

    // MARK: Private

    private static let log = Logger(subsystem: "app.carrierwave.data", category: "MacroExecutor")

    private func checkProtocol(
        spec: RadioMacroSpec,
        connected: RadioCommandProtocol?
    ) throws {
        guard let appliesTo = spec.appliesTo, !appliesTo.isEmpty else {
            return
        }
        guard let connected else {
            throw MacroExecutorError.noRadioConnected
        }
        guard appliesTo.contains(connected) else {
            throw MacroExecutorError.protocolMismatch(expected: appliesTo, connected: connected)
        }
    }

    private func resolveArgs(
        spec: RadioMacroSpec,
        callerArgs: [String: String]
    ) throws -> [String: String] {
        var resolved: [String: String] = [:]
        for arg in spec.args {
            let raw = callerArgs[arg.name] ?? arg.defaultValue
            guard let raw else {
                throw MacroExecutorError.missingRequiredArg(name: arg.name)
            }
            try validate(arg: arg, value: raw)
            resolved[arg.name] = raw
        }
        for (key, value) in callerArgs where resolved[key] == nil {
            resolved[key] = value
        }
        return resolved
    }

    private func validate(arg: RadioMacroArg, value: String) throws {
        switch arg.type {
        case .bool:
            // strict; accept "true"/"false" only
            switch value {
            case "true",
                 "false": break
            default:
                throw MacroExecutorError.invalidArgValue(
                    name: arg.name, value: value, expected: "true/false"
                )
            }
        case .enumeration:
            guard arg.values?.contains(where: { $0.id == value }) ?? false else {
                throw MacroExecutorError.invalidArgValue(
                    name: arg.name, value: value, expected: "enum value"
                )
            }
        case .uint8,
             .uint16,
             .uint32,
             .uint64,
             .freqHz,
             .frequency:
            guard let parsed = UInt64(value) else {
                throw MacroExecutorError.invalidArgValue(
                    name: arg.name, value: value, expected: "unsigned integer"
                )
            }
            if let minimum = arg.min, Int(parsed) < minimum {
                throw MacroExecutorError.argOutOfRange(
                    name: arg.name, value: value, min: minimum, max: arg.max
                )
            }
            if let maximum = arg.max, Int(parsed) > maximum {
                throw MacroExecutorError.argOutOfRange(
                    name: arg.name, value: value, min: arg.min, max: maximum
                )
            }
        case .string:
            break
        }
    }
}

// MARK: - Dispatch

private extension MacroExecutor {
    func dispatch(
        step: RadioMacroStep,
        index: Int,
        engine: MacroTemplateEngine,
        values: inout [String: String],
        sink: MacroExecutorSink
    ) async throws {
        do {
            try await dispatchInner(
                step: step,
                index: index,
                engine: engine,
                values: &values,
                sink: sink
            )
        } catch let error as MacroTemplateError {
            throw MacroExecutorError.template(error)
        } catch let error as RadioCommandCatalogError {
            throw MacroExecutorError.catalog(error)
        } catch let error as MacroFormatError {
            throw MacroExecutorError.format("\(error)")
        } catch let error as MacroExecutorError {
            throw error
        } catch is CancellationError {
            throw MacroExecutorError.cancelled
        } catch {
            throw MacroExecutorError.stepFailed(
                stepIndex: index,
                kind: step.kind,
                reason: error.localizedDescription
            )
        }
    }

    func dispatchInner(
        step: RadioMacroStep,
        index: Int,
        engine: MacroTemplateEngine,
        values: inout [String: String],
        sink: MacroExecutorSink
    ) async throws {
        switch step {
        case let .delay(durationMs):
            await sleep(UInt32(min(durationMs, UInt64(UInt32.max))))
        case let .setFrequency(hz):
            try await ensure(sink.setFrequencyHz(hz), label: "setFrequency")
        case let .setMode(mode):
            try await dispatchSetMode(mode, engine: engine, values: values, sink: sink)
        case let .setPowerWatts(watts):
            try await ensure(sink.setPowerWatts(watts), label: "setPowerWatts")
        case let .setPTT(on):
            try await ensure(sink.setPTT(on), label: "setPTT")
        case let .sendCW(text):
            try await dispatchSendCW(text, engine: engine, values: values, sink: sink)
        case let .vendorCommand(commandId, optionalArgs):
            try await dispatchVendorStep(
                commandId: commandId,
                optionalArgs: optionalArgs,
                engine: engine,
                values: values,
                sink: sink
            )
        case let .rawBytes(protocolName, bytes):
            try await dispatchRaw(protocolName: protocolName, bytes: bytes, sink: sink)
        case let .readField(field, into):
            values["ctx.\(into)"] = await sink.readField(field) ?? ""
        case let .waitUntil(expr, timeoutMs):
            try await runWaitUntil(
                expr: expr,
                timeoutMs: timeoutMs,
                index: index,
                engine: engine,
                values: values
            )
        case let .assert(expr, message):
            try await dispatchAssert(expr: expr, message: message, index: index, engine: engine, values: values)
        }
    }

    func ensure(_ ok: Bool, label: String) async throws {
        if !ok {
            throw MacroExecutorError.sinkRefused(label)
        }
    }

    func dispatchSetMode(
        _ mode: String,
        engine: MacroTemplateEngine,
        values: [String: String],
        sink: MacroExecutorSink
    ) async throws {
        let resolved = try engine.resolve(mode, values: values).uppercased()
        try await ensure(sink.setMode(resolved), label: "setMode")
    }

    func dispatchSendCW(
        _ text: String,
        engine: MacroTemplateEngine,
        values: [String: String],
        sink: MacroExecutorSink
    ) async throws {
        let resolved = try engine.resolve(text, values: values)
        _ = try MacroFormat.applyASCII(resolved)
        try await ensure(sink.sendCW(resolved), label: "sendCW")
    }

    func dispatchVendorStep(
        commandId: String,
        optionalArgs: [String: String]?,
        engine: MacroTemplateEngine,
        values: [String: String],
        sink: MacroExecutorSink
    ) async throws {
        let resolvedCommandId = try engine.resolve(commandId, values: values)
        var resolvedArgs: [String: String] = [:]
        for (key, raw) in optionalArgs ?? [:] {
            resolvedArgs[key] = try engine.resolve(raw, values: values)
        }
        try await dispatchVendor(commandId: resolvedCommandId, args: resolvedArgs, sink: sink)
    }

    func dispatchAssert(
        expr: String,
        message: String,
        index: Int,
        engine: MacroTemplateEngine,
        values: [String: String]
    ) async throws {
        let truthy = try engine.resolveBool(expr, values: values)
        if !truthy {
            throw MacroExecutorError.assertionFailed(message: message, stepIndex: index)
        }
    }

    func runWaitUntil(
        expr: String,
        timeoutMs: UInt64,
        index: Int,
        engine: MacroTemplateEngine,
        values: [String: String]
    ) async throws {
        let pollNs: UInt64 = 250_000_000
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMs) / 1_000.0)
        while Date() < deadline {
            let truthy = try engine.resolveBool(expr, values: values)
            if truthy {
                return
            }
            try? await Task.sleep(nanoseconds: pollNs)
        }
        // Final check before reporting timeout, so a flap right at the deadline still passes.
        let truthy = try engine.resolveBool(expr, values: values)
        if truthy {
            return
        }
        throw MacroExecutorError.stepFailed(
            stepIndex: index,
            kind: .waitUntil,
            reason: "waitUntil timed out after \(timeoutMs) ms"
        )
    }

    func dispatchVendor(
        commandId: String,
        args: [String: String],
        sink: MacroExecutorSink
    ) async throws {
        // First, give the sink a chance to handle vendor command natively
        // (Plan B may wire RadioSession into this).
        if await !(sink.sendVendorCommand(commandId: commandId, args: args)) {
            // Fall back to catalog-based encoding + raw bytes path.
            guard let spec = catalog.command(id: commandId) else {
                throw RadioCommandCatalogError.missingCommand(id: commandId)
            }
            let payload = try spec.encodePayload(args: args, context: .preview)
            let framed = try await frame(payload: payload, rigProtocol: spec.rigProtocol, sink: sink)
            try await sink.sendRawBytes(
                protocolName: spec.rigProtocol.rawValue,
                hexBytes: hexString(framed)
            )
        }
    }

    func dispatchRaw(
        protocolName: String,
        bytes: String,
        sink: MacroExecutorSink
    ) async throws {
        // bytes is a hex string; pass through with framing applied if the
        // protocol is one of the known framed ones.
        guard let rigProtocol = RadioCommandProtocol(rawValue: protocolName) else {
            try await sink.sendRawBytes(protocolName: protocolName, hexBytes: bytes)
            return
        }
        let payload: Data = switch rigProtocol {
        case .civ,
             .flex:
            try MacroHex.parse(bytes)
        case .kenwood,
             .yaesu:
            Data(bytes.utf8)
        }
        let framed = try await frame(payload: payload, rigProtocol: rigProtocol, sink: sink)
        try await sink.sendRawBytes(protocolName: protocolName, hexBytes: hexString(framed))
    }

    func frame(
        payload: Data,
        rigProtocol: RadioCommandProtocol,
        sink: MacroExecutorSink
    ) async throws -> Data {
        switch rigProtocol {
        case .civ:
            guard let address = await sink.civAddress else {
                throw MacroExecutorError.missingCIVAddress
            }
            var bytes: [UInt8] = [0xFE, 0xFE, address, 0xE0]
            bytes.append(contentsOf: payload)
            bytes.append(0xFD)
            return Data(bytes)
        case .kenwood,
             .yaesu:
            // Both Kenwood and modern Yaesu CAT use ASCII commands
            // terminated by a single ';'. Vintage Yaesu (binary) is not
            // supported by this path — use raw bytes for those.
            if let last = payload.last, last == UInt8(ascii: ";") {
                return payload
            }
            var bytes = Array(payload)
            bytes.append(UInt8(ascii: ";"))
            return Data(bytes)
        case .flex:
            return payload
        }
    }

    func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
