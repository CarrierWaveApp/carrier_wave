import Foundation

// MARK: - RadioControlSurface

/// The slice of a live radio session the state gateway drives. `RadioSession`
/// conforms directly; tests use a fake.
///
/// Reads come from the session's already-parsed `RadioState` — the poll loop
/// keeps it fresh via the protocol handler's decode path. So the "read-back"
/// the command catalog lacks already exists here for the fields the handler
/// decodes (frequency, mode, power); no new request/response plumbing.
public protocol RadioControlSurface: Sendable {
    func liveState() async -> RadioSession.RadioState
    func tuneToFrequency(_ freqMHz: Double) async -> Bool
    func setMode(_ mode: String, universalModeRawValue: UInt8?) async -> Bool
    func sendRaw(_ data: Data) async throws
}

// MARK: - RadioSession + RadioControlSurface

extension RadioSession: RadioControlSurface {
    public func liveState() async -> RadioState {
        state
    }
}

// MARK: - RadioSessionStateGateway

/// `RadioStateGateway` over a live `RadioSession`. Reads canonical values
/// from the session's polled `RadioState`; writes via the session's typed
/// setters where one exists (frequency, mode — cross-protocol through the
/// protocol handler), falling back to raw ASCII (Kenwood/Elecraft) for
/// settings with no typed setter (power, vendor menu items).
///
/// Shared by iOS and CW Sweep since `RadioSession` lives in this package.
/// Scoped to fields the session can read today; settings the protocol
/// handler doesn't decode read back as nil and so re-apply every run.
public actor RadioSessionStateGateway: RadioStateGateway {
    // MARK: Lifecycle

    public init(control: RadioControlSurface, fields: [RadioStateField] = RadioStateField.kx2Spike) {
        self.control = control
        fieldsByKey = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0) })
    }

    // MARK: Public

    public func currentValue(forKey key: String) async -> String? {
        let state = await control.liveState()
        switch key {
        case "vfoA":
            guard state.frequency > 0 else {
                return nil
            }
            return String(UInt64((state.frequency * 1_000_000).rounded()))
        case "mode":
            return state.mode.isEmpty ? nil : state.mode.uppercased()
        case "power":
            return state.powerLevel > 0 ? String(state.powerLevel) : nil
        default:
            return nil
        }
    }

    public func apply(key: String, value: String) async -> Bool {
        switch key {
        case "vfoA":
            guard let hertz = UInt64(value) else {
                return false
            }
            return await control.tuneToFrequency(Double(hertz) / 1_000_000)
        case "mode":
            return await control.setMode(value, universalModeRawValue: nil)
        default:
            return await applyRaw(key: key, value: value)
        }
    }

    // MARK: Private

    private let control: RadioControlSurface
    private let fieldsByKey: [String: RadioStateField]

    /// Encode via the field codec and send as raw ASCII. Covers power and
    /// vendor settings that have no typed setter on `RadioSession`. Returns
    /// false if the field is unknown, unencodable, or the send fails.
    private func applyRaw(key: String, value: String) async -> Bool {
        guard let field = fieldsByKey[key], let command = field.setCommand(for: value) else {
            return false
        }
        do {
            try await control.sendRaw(Data(command.utf8))
            return true
        } catch {
            return false
        }
    }
}
