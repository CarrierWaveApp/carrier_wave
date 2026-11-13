import CarrierWaveData
import Foundation

// MARK: - MacRadioSessionMacroSinkError

enum MacRadioSessionMacroSinkError: Error {
    case notConnected
    case invalidHex
}

// MARK: - MacRadioSessionMacroSink

/// Bridges `MacroExecutorSink` to CW Sweep's live `RadioManager` and the
/// active `RadioSession` for the currently focused slot. Plan C's macOS
/// editor will instantiate one per macro execution.
///
/// Implemented as an `actor` (not `@MainActor`) so the executor can call
/// into it from any context. All reads of the `@MainActor`-isolated
/// `RadioManager` are explicitly hopped via `await MainActor.run { ... }`.
actor MacRadioSessionMacroSink: MacroExecutorSink {
    // MARK: Lifecycle

    /// Initialize bound to a `RadioManager`. The caller (typically
    /// `@MainActor`) supplies the instance — defaults to
    /// `SharedEnvironment.shared.radioManager` via the `.live()` factory.
    init(radioManager: RadioManager) {
        self.radioManager = radioManager
    }

    // MARK: Internal

    var connectedProtocol: RadioCommandProtocol? {
        get async {
            await MainActor.run {
                guard radioManager.isConnected else {
                    return nil
                }
                guard let slot = activeSlot(),
                      let state = radioManager.slotStates[slot]
                else {
                    return nil
                }
                return Self.toRadioCommandProtocol(state.profile.protocolType)
            }
        }
    }

    var civAddress: UInt8? {
        get async {
            await MainActor.run {
                guard let slot = activeSlot(),
                      let state = radioManager.slotStates[slot]
                else {
                    return nil
                }
                let pType = state.profile.protocolType
                guard pType == .civ || pType == .icomWiFi else {
                    return nil
                }
                return state.profile.civAddress
            }
        }
    }

    /// Convenience factory for the production path: binds to
    /// `SharedEnvironment.shared.radioManager` from a `@MainActor` context.
    /// Plan C call sites (editor / runner UI) are already on the main actor.
    @MainActor
    static func live() -> MacRadioSessionMacroSink {
        MacRadioSessionMacroSink(radioManager: SharedEnvironment.shared.radioManager)
    }

    func setFrequencyHz(_ hertz: UInt64) async -> Bool {
        let mhz = Double(hertz) / 1_000_000
        guard let session = await activeSession() else {
            await logFailure("setFrequency \(hertz) Hz: no session")
            return false
        }
        return await session.tuneToFrequency(mhz)
    }

    func setMode(_ mode: String) async -> Bool {
        guard let session = await activeSession() else {
            await logFailure("setMode \(mode): no session")
            return false
        }
        let universal = await MainActor.run {
            BridgeFrame.UniversalMode.from(carrierWaveMode: mode)?.rawValue
        }
        return await session.setMode(mode, universalModeRawValue: universal)
    }

    func setPowerWatts(_ watts: UInt64) async -> Bool {
        guard let session = await activeSession() else {
            await logFailure("setPower \(watts)W: no session")
            return false
        }
        let clamped = UInt8(min(watts, UInt64(UInt8.max)))
        return await session.setPowerLevel(clamped)
    }

    func setPTT(_ on: Bool) async -> Bool {
        guard let session = await activeSession() else {
            await logFailure("setPTT \(on): no session")
            return false
        }
        return await session.setPTT(on)
    }

    func sendCW(_ text: String) async -> Bool {
        guard let session = await activeSession() else {
            await logFailure("sendCW \(text.prefix(20)): no session")
            return false
        }
        return await session.sendCW(text)
    }

    func sendRawBytes(protocolName _: String, hexBytes: String) async throws {
        guard let session = await activeSession() else {
            await logFailure("sendRawBytes \(hexBytes.prefix(40)): no session")
            throw MacRadioSessionMacroSinkError.notConnected
        }
        guard let data = Self.decodeHex(hexBytes) else {
            await logFailure("sendRawBytes: invalid hex \(hexBytes.prefix(40))")
            throw MacRadioSessionMacroSinkError.invalidHex
        }
        try await session.sendRaw(data)
    }

    /// Read a live field from the focused slot. Phase 1 exposes `vfoA` (in
    /// Hz, as a decimal string) and `mode`. Other fields are not yet
    /// surfaced by `RadioManager` and return nil — future work.
    func readField(_ field: String) async -> String? {
        await MainActor.run {
            switch field {
            case "vfoA":
                let mhz = radioManager.frequency
                guard mhz > 0 else {
                    return nil
                }
                return String(format: "%.0f", mhz * 1_000_000)
            case "mode":
                let mode = radioManager.mode
                return mode.isEmpty ? nil : mode
            default:
                // swr / power / etc. not yet exposed by RadioManager.
                return nil
            }
        }
    }

    // MARK: Private

    private let radioManager: RadioManager

    /// Decode a hex-byte string (with optional whitespace and `0x` prefixes)
    /// into raw bytes. Mirrors `MacroHex.parse` in the CarrierWaveData package
    /// (internal to that module and so cannot be imported here). Returns nil
    /// on malformed input — caller throws `.invalidHex`.
    private static func decodeHex(_ text: String) -> Data? {
        let cleaned = text
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard cleaned.count.isMultiple(of: 2) else {
            return nil
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index ..< next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private static func toRadioCommandProtocol(
        _ ptype: RadioProtocolType
    ) -> RadioCommandProtocol? {
        switch ptype {
        case .civ,
             .icomWiFi: .civ
        case .kenwood,
             .elecraft: .kenwood
        case .yaesu,
             .scuLan10: .yaesu
        case .flex: .flex
        case .cwBridge: nil
        }
    }

    /// Resolve the live session for the currently active radio. Returns nil
    /// if no slot is bound or the session has been torn down.
    private func activeSession() async -> RadioSession? {
        await MainActor.run {
            guard let id = radioManager.activeRadioId else {
                return nil
            }
            return radioManager.sessions[id]
        }
    }

    /// Find the slot whose UUID matches `activeRadioId`, falling back to
    /// `focusedSlot`. Main-actor isolated since it reads `radioManager`.
    @MainActor
    private func activeSlot() -> RadioSlot? {
        guard let id = radioManager.activeRadioId else {
            return nil
        }
        return radioManager.slots.first(where: { $1 == id })?.key
            ?? radioManager.focusedSlot
    }

    private func logFailure(_ message: String) async {
        await MainActor.run {
            radioManager.appendConnectionLog("MacroSink: \(message)")
        }
    }
}
