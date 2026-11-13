import CarrierWaveData
import Foundation

// MARK: - RadioProfileRunner

/// Runs a declarative `RadioStateProfile` against CW Sweep's active radio:
/// refresh → plan → apply → verify, logging each phase to the connection
/// log. This is the entry point for "radio-as-code" from Sweep — call
/// `run(profile:on:)` from a command, menu, or button.
///
/// Reuses the shared `RadioSessionStateGateway`, so reads come from the live
/// `RadioState` the session already polls and writes go through the session.
@MainActor
enum RadioProfileRunner {
    struct Outcome {
        /// The pre-apply diff.
        let plan: RadioStatePlan
        /// Keys the radio refused or couldn't set over its current link.
        let failedKeys: [String]
        /// The post-apply re-plan.
        let verified: RadioStatePlan

        var converged: Bool {
            verified.isConverged && failedKeys.isEmpty
        }
    }

    @discardableResult
    static func run(
        profile: RadioStateProfile,
        on radioManager: RadioManager,
        fields: [RadioStateField] = RadioStateField.kx2Spike
    ) async -> Outcome? {
        guard let id = radioManager.activeRadioId, let session = radioManager.sessions[id] else {
            radioManager.appendConnectionLog("RadioProfile '\(profile.name)': no radio connected")
            return nil
        }

        let gateway = RadioSessionStateGateway(control: session, fields: fields)
        let planner = RadioStatePlanner(fields: fields)

        do {
            let plan = try await planner.plan(profile: profile, gateway: gateway)
            radioManager.appendConnectionLog(
                "RadioProfile '\(profile.name)': \(plan.changes.count) change(s), \(plan.drift.count) drift"
            )
            let failed = try await planner.apply(plan, gateway: gateway)
            if !failed.isEmpty {
                radioManager.appendConnectionLog(
                    "RadioProfile '\(profile.name)': could not set \(failed.joined(separator: ", "))"
                )
            }
            let verified = try await planner.verify(profile: profile, gateway: gateway)
            let outcome = Outcome(plan: plan, failedKeys: failed, verified: verified)
            radioManager.appendConnectionLog(
                "RadioProfile '\(profile.name)': \(outcome.converged ? "converged" : "not converged")"
            )
            return outcome
        } catch {
            radioManager.appendConnectionLog("RadioProfile '\(profile.name)' error: \(error)")
            return nil
        }
    }
}

// MARK: - RadioProfileReadbackRunner

/// Codec-over-serial harness: taps the live `RadioSession`'s frame stream and
/// runs each `RadioStateField.parse(response:)` against the bytes the radio
/// actually sends back. Validates the read half of `RadioStateCodec` end-to-end
/// on hardware, complementing the gateway-over-session path used by
/// `RadioProfileRunner` (which only reads already-decoded state).
@MainActor
enum RadioProfileReadbackRunner {
    // MARK: Internal

    struct Outcome {
        let decoded: [String: String]
        let unmatched: [String]
    }

    @discardableResult
    static func run(
        on radioManager: RadioManager,
        fields: [RadioStateField] = RadioStateField.kx2Spike,
        timeout: Duration = .seconds(2)
    ) async -> Outcome? {
        guard let id = radioManager.activeRadioId, let session = radioManager.sessions[id] else {
            radioManager.appendConnectionLog("RadioProfile readback: no radio connected")
            return nil
        }

        let readable = fields.filter(\.readable)
        radioManager.appendConnectionLog(
            "RadioProfile readback: observing \(readable.count) field(s) for \(timeout)"
        )

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        await session.setCodecTap { frame in continuation.yield(frame) }

        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            continuation.finish()
        }

        var decoded: [String: String] = [:]
        for await frame in stream {
            guard let response = String(data: frame, encoding: .ascii) else {
                continue
            }
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            for field in readable where decoded[field.key] == nil {
                if let value = field.codec.decode(strippedPayload(trimmed, prefix: field.prefix) ?? "") {
                    decoded[field.key] = value
                    radioManager.appendConnectionLog(
                        "RadioField '\(field.key)' (\(field.label)): \(trimmed) -> \(value)"
                    )
                }
            }
            if decoded.count == readable.count {
                continuation.finish()
                break
            }
        }

        timeoutTask.cancel()
        await session.setCodecTap(nil)

        let unmatched = readable.map(\.key).filter { decoded[$0] == nil }
        if !unmatched.isEmpty {
            radioManager.appendConnectionLog(
                "RadioProfile readback: no response for \(unmatched.joined(separator: ", "))"
            )
        }
        radioManager.appendConnectionLog(
            "RadioProfile readback: \(decoded.count)/\(readable.count) decoded"
        )
        return Outcome(decoded: decoded, unmatched: unmatched)
    }

    // MARK: Private

    /// Strip the `<prefix>...;` envelope so the payload can go straight through
    /// the field's codec — mirrors `RadioStateField.parse(response:)`, but using
    /// the codec directly proves the harness exercises the read-half primitive
    /// rather than the convenience wrapper.
    private static func strippedPayload(_ response: String, prefix: String) -> String? {
        guard response.hasPrefix(prefix), response.hasSuffix(";") else {
            return nil
        }
        return String(response.dropFirst(prefix.count).dropLast())
    }
}

// MARK: - OperateIntentRunner

/// Dynamic-macro flow for `"operate ft8"` / `"operate cw"` / `"operate ssb"`.
/// Resolves a `RadioIntent` against the connected radio's live state, runs
/// the planner to compute a diff, compiles the result (plus the intent's
/// vendor-command sequence) into a fresh `RadioMacroSpec`, and opens the
/// existing `MacroRunWindowController` with both the spec and the
/// pre-computed plan so the run sheet can show the diff before Run.
///
/// The compiled spec is disposable — generated per invocation, not
/// persisted. See memory `dynamic-radio-macros` for the rationale.
@MainActor
enum OperateIntentRunner {
    // MARK: Internal

    @discardableResult
    static func run(
        intent: RadioIntent,
        on radioManager: RadioManager,
        fields: [RadioStateField] = RadioStateField.kx2Canonical
    ) async -> Bool {
        guard let prep = await prepare(intent: intent, on: radioManager) else {
            return false
        }
        let menuRows = await snapshotMenuRows(
            desired: prep.opProfile.menuItems,
            session: prep.session,
            radioManager: radioManager,
            intentName: intent.displayName
        )
        return await planAndPresent(
            intent: intent,
            prep: prep,
            menuRows: menuRows,
            fields: fields,
            radioManager: radioManager
        )
    }

    // MARK: Private

    /// Active session + slot context for an intent run. Nil result already
    /// logged to the connection log.
    private struct Prep {
        let session: RadioSession
        let protocolKind: RadioCommandProtocol
        let opProfile: OperatingProfile
    }

    private static func prepare(
        intent: RadioIntent,
        on radioManager: RadioManager
    ) async -> Prep? {
        guard let id = radioManager.activeRadioId, let session = radioManager.sessions[id] else {
            radioManager.appendConnectionLog("Intent '\(intent.displayName)': no radio connected")
            return nil
        }
        guard let slotState = radioManager.slotStates[radioManager.focusedSlot] else {
            radioManager.appendConnectionLog("Intent '\(intent.displayName)': no active slot")
            return nil
        }
        let protocolKind = commandProtocol(for: slotState.profile.protocolType)
        let liveState = await session.liveState()
        let context = RadioIntentContext(
            currentFrequencyHz: liveState.frequency > 0
                ? UInt64((liveState.frequency * 1_000_000).rounded())
                : nil,
            currentMode: liveState.mode.isEmpty ? nil : liveState.mode,
            protocolKind: protocolKind
        )
        guard let opProfile = intent.operatingProfile(context: context) else {
            radioManager.appendConnectionLog(
                "Intent '\(intent.displayName)': no template for \(protocolKind.rawValue) radios yet"
            )
            return nil
        }
        return Prep(session: session, protocolKind: protocolKind, opProfile: opProfile)
    }

    private static func planAndPresent(
        intent: RadioIntent,
        prep: Prep,
        menuRows: [MenuPlanRow],
        fields: [RadioStateField],
        radioManager: RadioManager
    ) async -> Bool {
        let resolution = prep.opProfile.resolution(name: intent.displayName)
        let gateway = RadioSessionStateGateway(control: prep.session, fields: fields)
        let planner = RadioStatePlanner(fields: fields)
        do {
            let plan = try await planner.plan(profile: resolution.profile, gateway: gateway)
            let spec = try planner.compile(
                plan,
                vendorSteps: resolution.vendorSteps,
                name: intent.displayName,
                icon: intent.icon,
                appliesTo: [prep.protocolKind]
            )
            let menuDiff = menuRows.filter { !$0.converged }.count
            radioManager.appendConnectionLog(
                "Intent '\(intent.displayName)': "
                    + "\(plan.changes.count) change(s), "
                    + "\(menuDiff) menu diff, "
                    + "\(resolution.vendorSteps.count) vendor step(s)"
            )
            MacroRunWindowController.present(spec: spec, plan: plan, menuPlanRows: menuRows)
            return true
        } catch {
            radioManager.appendConnectionLog("Intent '\(intent.displayName)' planning error: \(error)")
            return false
        }
    }

    /// Snapshot current values for every menu item the intent declares, then
    /// build the `MenuPlanRow` list the sheet renders. Labels come from the
    /// canonical KX2 menu catalog; an item the intent declares but the
    /// catalog doesn't recognize falls back to "menu <n>".
    private static func snapshotMenuRows(
        desired: [MenuItem],
        session: RadioSession,
        radioManager: RadioManager,
        intentName: String
    ) async -> [MenuPlanRow] {
        guard !desired.isEmpty else {
            return []
        }
        let catalogByItem = Dictionary(
            uniqueKeysWithValues: RadioMenuField.kx2Canonical.map { ($0.item, $0) }
        )
        let readFields = desired.compactMap { catalogByItem[$0.item] }
        radioManager.appendConnectionLog(
            "Intent '\(intentName)': reading \(readFields.count) menu(s)…"
        )
        let snapshot = await MenuReader.snapshot(items: readFields, session: session)
        return desired.map { item in
            MenuPlanRow(
                item: item.item,
                label: catalogByItem[item.item]?.label ?? "menu \(item.item)",
                current: snapshot[item.item],
                desired: item.value
            )
        }
    }

    /// Collapse Sweep's transport-level `RadioProtocolType` into the
    /// macro-layer `RadioCommandProtocol`. Elecraft and Kenwood share the
    /// Kenwood ASCII catalog; SCU-LAN10 wraps a Yaesu CAT path; CW Bridge
    /// is assumed to front a Kenwood/Elecraft for the KX2-first intents
    /// shipped here.
    private static func commandProtocol(for protocolType: RadioProtocolType) -> RadioCommandProtocol {
        switch protocolType {
        case .civ,
             .icomWiFi:
            .civ
        case .kenwood,
             .elecraft,
             .cwBridge:
            .kenwood
        case .yaesu,
             .scuLan10:
            .yaesu
        case .flex:
            .flex
        }
    }
}
