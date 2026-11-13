import CarrierWaveData
import UIKit

// MARK: - RadioSessionMacroSinkError

enum RadioSessionMacroSinkError: Error {
    case notConnected
    case invalidHex
}

// MARK: - RadioSessionMacroSink

/// Bridges `MacroExecutorSink` to the iOS app's live `RadioService` + its
/// underlying `RadioSession` actor. Plan C will instantiate one per macro
/// execution and hand it to `MacroExecutor.execute(...)` so a user-authored
/// macro can drive the connected radio.
///
/// Implemented as an `actor` (not `@MainActor`) so the executor can call
/// into it from any context. All reads of the `@MainActor`-isolated
/// `RadioService` are explicitly hopped via `await MainActor.run { ... }`.
actor RadioSessionMacroSink: MacroExecutorSink {
    // MARK: Lifecycle

    /// Initialize bound to a `RadioService`. The caller (typically
    /// `@MainActor`) supplies the instance — defaults to `.shared` via the
    /// `.live()` factory below.
    init(radioService: RadioService) {
        self.radioService = radioService
    }

    // MARK: Internal

    var connectedProtocol: RadioCommandProtocol? {
        get async {
            await MainActor.run {
                guard radioService.isConnected else {
                    return nil
                }
                switch radioService.rigProtocol {
                case .civ: return RadioCommandProtocol.civ
                case .kenwood: return RadioCommandProtocol.kenwood
                }
            }
        }
    }

    var civAddress: UInt8? {
        get async {
            await MainActor.run {
                radioService.rigProtocol == .civ ? radioService.configuredRigAddress : nil
            }
        }
    }

    /// Convenience factory for the production path: binds to
    /// `RadioService.shared` from a `@MainActor` context. Plan C call sites
    /// (editor / runner UI) are already on the main actor.
    @MainActor
    static func live() -> RadioSessionMacroSink {
        RadioSessionMacroSink(radioService: .shared)
    }

    func setFrequencyHz(_ hertz: UInt64) async -> Bool {
        let mhz = Double(hertz) / 1_000_000
        guard let session = await session() else {
            await logFailure("setFrequency \(hertz) Hz: no session")
            return false
        }
        return await session.tuneToFrequency(mhz)
    }

    func setMode(_ mode: String) async -> Bool {
        guard let session = await session() else {
            await logFailure("setMode \(mode): no session")
            return false
        }
        let universal = await MainActor.run {
            BridgeFrame.UniversalMode.from(carrierWaveMode: mode)?.rawValue
        }
        return await session.setMode(mode, universalModeRawValue: universal)
    }

    func setPowerWatts(_ watts: UInt64) async -> Bool {
        guard let session = await session() else {
            await logFailure("setPower \(watts)W: no session")
            return false
        }
        let clamped = UInt8(min(watts, UInt64(UInt8.max)))
        return await session.setPowerLevel(clamped)
    }

    func setPTT(_ on: Bool) async -> Bool {
        guard let session = await session() else {
            await logFailure("setPTT \(on): no session")
            return false
        }
        return await session.setPTT(on)
    }

    func sendCW(_ text: String) async -> Bool {
        guard let session = await session() else {
            await logFailure("sendCW \(text.prefix(20)): no session")
            return false
        }
        return await session.sendCW(text)
    }

    func sendRawBytes(protocolName _: String, hexBytes: String) async throws {
        guard let session = await session() else {
            await logFailure("sendRawBytes \(hexBytes.prefix(40)): no session")
            throw RadioSessionMacroSinkError.notConnected
        }
        guard let data = Self.decodeHex(hexBytes) else {
            await logFailure("sendRawBytes: invalid hex \(hexBytes.prefix(40))")
            throw RadioSessionMacroSinkError.invalidHex
        }
        try await session.sendRaw(data)
    }

    /// Read a live field from the radio. Phase 1 exposes `vfoA` (in Hz, as a
    /// decimal string) and `mode`. Other fields (e.g. `swr`) are not yet
    /// surfaced by `RadioService` and return nil — future work.
    func readField(_ field: String) async -> String? {
        await MainActor.run {
            switch field {
            case "vfoA":
                radioService.radioFrequencyMHz.map {
                    String(format: "%.0f", $0 * 1_000_000)
                }
            case "mode":
                radioService.radioMode
            default:
                // swr / power / etc. not yet exposed by RadioService.
                nil
            }
        }
    }

    // MARK: Private

    private let radioService: RadioService

    /// Decode a hex-byte string (with optional whitespace and `0x` prefixes)
    /// into raw bytes. Mirrors `MacroHex.parse` in the CarrierWaveData package
    /// (which is internal to that module and so cannot be imported here).
    /// Returns nil on malformed input — caller throws `.invalidHex`.
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

    private func session() async -> RadioSession? {
        await MainActor.run { radioService.session }
    }

    private func logFailure(_ message: String) async {
        await MainActor.run {
            radioService.addLog(.error, "MacroSink: \(message)")
        }
    }
}
