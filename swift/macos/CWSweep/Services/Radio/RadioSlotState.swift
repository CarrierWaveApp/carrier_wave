import Foundation

// MARK: - RadioConnectError

/// Errors thrown by `RadioManager.connect(...)` when the caller's intent
/// would conflict with an existing slot binding.
enum RadioConnectError: LocalizedError {
    case slotOccupied(RadioSlot)
    case duplicatePort(path: String, slot: RadioSlot)
    case noFreeSlot

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .slotOccupied(slot):
            "\(slot.label) is already connected. Disconnect it first."
        case let .duplicatePort(path, slot):
            "Port \(path) is already in use by \(slot.label)."
        case .noFreeSlot:
            "No free radio slot. Disconnect a radio before adding another."
        }
    }
}

// MARK: - ContestSlotRole

/// SO2R role hint for a slot. Surfaced in the Contester layout; not yet
/// consumed by the scoring engine.
enum ContestSlotRole: String, CaseIterable, Codable, Identifiable {
    case none
    case run
    case mult

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .none: "—"
        case .run: "Run"
        case .mult: "Mult"
        }
    }
}

// MARK: - RadioSlot

/// User-visible identity for a connected radio. Sessions come and go; a slot
/// is the stable label the operator (and persistence) refers to.
enum RadioSlot: String, CaseIterable, Codable, Identifiable, Hashable {
    case a
    case b

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        "Radio \(rawValue.uppercased())"
    }

    var shortLabel: String {
        rawValue.uppercased()
    }

    /// Stable ordering used for picking the next available slot.
    var ordinal: Int {
        switch self {
        case .a: 0
        case .b: 1
        }
    }
}

// MARK: - RadioSlotState

/// Per-slot, per-session state. Owned by `RadioManager.slotStates`.
///
/// Holds everything that used to live as singular state on `RadioManager`
/// (frequency, mode, XIT/RIT, transmit, connection metadata). The manager's
/// legacy fields continue to mirror the focused slot for backward compat with
/// the ~50 existing read sites; new UI should consume `RadioSlotState`
/// directly.
@MainActor
@Observable
final class RadioSlotState: Identifiable {
    // MARK: Lifecycle

    init(
        slot: RadioSlot,
        sessionId: UUID,
        profile: RadioProfile
    ) {
        self.slot = slot
        self.sessionId = sessionId
        self.profile = profile
    }

    // MARK: Internal

    let slot: RadioSlot
    let sessionId: UUID

    var profile: RadioProfile

    /// Display path: serial port path for USB, host:port for network, BLE name
    /// for CW Bridge. Mirrors what `RadioManager.connectedPortPath` used to
    /// hold.
    var connectedPortPath: String?

    /// Resolved radio name (typically `profile.name`).
    var connectedRadioName: String?

    /// Currently tuned frequency in MHz.
    var frequency: Double = 0

    /// Currently selected mode string (CW, USB, etc.).
    var mode: String = ""

    /// Scope span in kHz from Yaesu SS05 response (0 = unknown / not Yaesu).
    var scopeSpanKHz: Double = 0

    /// Whether XIT is enabled on the radio.
    var xitEnabled: Bool = false

    /// Whether RIT is enabled on the radio.
    var ritEnabled: Bool = false

    /// Current RIT/XIT offset in Hz.
    var ritXitOffset: Int = 0

    /// Whether the radio is transmitting.
    var isTransmitting: Bool = false

    /// Contester role tag for this slot. Annotation only at this stage —
    /// not consumed by the contest scoring engine yet. Persisted via
    /// `RadioManager+Persistence`'s `contestRole(for:)` accessor so it
    /// survives across sessions.
    var contestRole: ContestSlotRole = .none

    /// CW Bridge state for this slot, if the slot's session is bridged.
    /// Nil for direct USB/TCP/IP radios. Populated alongside the legacy
    /// `activeBridge*` and `bridge*` properties on `RadioManager`; readers
    /// that want to be multi-bridge-ready should consume this directly.
    var bridge: BridgeSlotState?

    /// Most recent error surface for this slot (e.g. transport failure).
    var lastError: String?
}

// MARK: - BridgeSlotState

/// Per-slot state for a CW Bridge BLE session. Mirrors the legacy
/// `bridge*` properties on `RadioManager` so multi-bridge installs can
/// route reads through the slot rather than a single global. The active
/// `BridgeProtocol` and `BLERadioTransport` references live here too —
/// `RadioManager` continues to expose the focused-slot ones via shims.
@MainActor
@Observable
final class BridgeSlotState {
    // MARK: Lifecycle

    init(bridge: BridgeProtocol, transport: BLERadioTransport, sessionId: UUID) {
        self.bridge = bridge
        self.transport = transport
        self.sessionId = sessionId
    }

    // MARK: Internal

    let sessionId: UUID

    /// Active CWBP framing actor for this slot.
    var bridge: BridgeProtocol

    /// Underlying BLE transport for this slot.
    var transport: BLERadioTransport

    /// Firmware version reported by the bridge (nil until handshake).
    var firmwareVersion: String?

    /// Bridge capability flag bitmask (see BridgeFrame.Capabilities).
    var capabilities: UInt8 = 0

    /// Whether the bridge's USB port has a downstream radio attached.
    var usbConnected: Bool = false

    /// Detected radio name from the bridge (e.g. "Elecraft K3/KX").
    var detectedRadio: String?

    /// Whether the bridge is currently probing for a radio.
    var detecting: Bool = false

    /// Whether the CWBP handshake has completed.
    var isFramed: Bool = false

    /// Whether the bridge advertises CW keyer capability.
    var hasCWKeyer: Bool = false

    /// CW state echoed from firmware.
    var cwSendingSlot: Int?
    var cwSpeed: UInt8 = 25
    var cwFlags: BridgeFrame.CWProgressFlags = []
    var cwBufferDepth: UInt8 = 0

    /// Running task monitoring bridge events for this slot.
    var eventTask: Task<Void, Never>?

    /// Running task monitoring BLE connection state for this slot.
    var stateTask: Task<Void, Never>?
}
