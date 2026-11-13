import Foundation

//
// Field → Sweep CW keying frames. Field cannot share Sweep's BLE bond with
// the CW Bridge dongle (BLE NUS is single-central), so all keying flows over
// the existing TCP RemoteOp link. Sweep applies each command against
// `RadioManager.activeBridge` and re-broadcasts the bridge's keyer state on
// the `cw.keyer` topic so Field's HUD can mirror WPM, buffer depth, and slot
// playback.

// MARK: - SendCWCommand

/// Field → Sweep. Send a literal CW string through the bridge keyer.
public struct SendCWCommand: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(requestID: UUID = UUID(), text: String, radioID: String? = nil) {
        self.requestID = requestID
        self.text = text
        self.radioID = radioID
    }

    // MARK: Public

    public let requestID: UUID
    public let text: String
    public let radioID: String?
}

// MARK: - StopCWCommand

/// Field → Sweep. Stop any active CW transmission immediately.
public struct StopCWCommand: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(requestID: UUID = UUID(), radioID: String? = nil) {
        self.requestID = requestID
        self.radioID = radioID
    }

    // MARK: Public

    public let requestID: UUID
    public let radioID: String?
}

// MARK: - SetCWSpeedCommand

/// Field → Sweep. Set the bridge keyer speed in WPM. Sweep clamps to 5...60.
public struct SetCWSpeedCommand: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(requestID: UUID = UUID(), wpm: UInt8, radioID: String? = nil) {
        self.requestID = requestID
        self.wpm = wpm
        self.radioID = radioID
    }

    // MARK: Public

    public let requestID: UUID
    public let wpm: UInt8
    public let radioID: String?
}

// MARK: - PlayCWSlotCommand

/// Field → Sweep. Play a stored CW memory slot (1...8) with optional template
/// substitution context (e.g. `["call": "K1JT"]`).
public struct PlayCWSlotCommand: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        requestID: UUID = UUID(),
        slot: UInt8,
        context: [String: String] = [:],
        radioID: String? = nil
    ) {
        self.requestID = requestID
        self.slot = slot
        self.context = context
        self.radioID = radioID
    }

    // MARK: Public

    public let requestID: UUID
    public let slot: UInt8
    public let context: [String: String]
    public let radioID: String?
}

// MARK: - SetCWSlotCommand

/// Field → Sweep. Program a CW memory slot on Sweep. Sweep persists the new
/// text in its keyer store and (when a bridge is connected) also pushes the
/// expanded text into the bridge's slot memory so subsequent `playCWSlot`
/// frames key the right message.
public struct SetCWSlotCommand: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        requestID: UUID = UUID(),
        slot: UInt8,
        label: String,
        text: String,
        radioID: String? = nil
    ) {
        self.requestID = requestID
        self.slot = slot
        self.label = label
        self.text = text
        self.radioID = radioID
    }

    // MARK: Public

    public let requestID: UUID
    public let slot: UInt8
    public let label: String
    public let text: String
    public let radioID: String?
}

// MARK: - RemoteCWSlot

/// Wire-format CW memory slot entry. `id` is 1...8 (the bridge's memory
/// count). `text` may include macro tokens like `{CALL}` / `{MYCALL}` /
/// `{NR}` / `{RST}` — Sweep expands them at play time using context the
/// client supplies in `PlayCWSlotCommand`.
public struct RemoteCWSlot: Codable, Sendable, Equatable, Identifiable {
    // MARK: Lifecycle

    public init(id: UInt8, label: String, text: String) {
        self.id = id
        self.label = label
        self.text = text
    }

    // MARK: Public

    public let id: UInt8
    public let label: String
    public let text: String

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - CWSlotsEvent

/// Sweep → Field. Snapshot of every CW memory slot Sweep currently knows
/// about (includes empty slots so the editor UI can offer them as targets).
/// Emitted on the `cw.slots` topic right after subscribe and after every
/// `commandSetCWSlot`.
public struct CWSlotsEvent: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(slots: [RemoteCWSlot]) {
        self.slots = slots
    }

    // MARK: Public

    public let slots: [RemoteCWSlot]
}

// MARK: - RemoteCWMacros

/// Shared macro vocabulary used by Sweep's keyer expansion and by Field's
/// "what does this slot need?" UI gating. Token names are uppercase and
/// match what `RemoteOpService.handlePlayCWSlot` expects in
/// `PlayCWSlotCommand.context`.
public enum RemoteCWMacros {
    /// Every macro token Sweep knows how to expand. Tokens not in this set
    /// pass through verbatim (so a literal `{FOO}` in a slot stays `{FOO}`).
    public static let known: Set<String> = [
        "MYCALL",
        "MYNAME",
        "CALL",
        "HISCALL",
        "NAME",
        "RST",
        "NR",
        "SERIAL",
        "EXCH",
        "FREQ",
        "HISSTATE",
    ]

    /// Returns the set of known macros referenced by a slot text, uppercased.
    /// Unknown `{FOO}` braces are ignored.
    public static func requiredMacros(in text: String) -> Set<String> {
        var result: Set<String> = []
        var index = text.startIndex
        while index < text.endIndex {
            guard let openIdx = text[index...].firstIndex(of: "{") else {
                break
            }
            let afterOpen = text.index(after: openIdx)
            guard afterOpen < text.endIndex,
                  let closeIdx = text[afterOpen...].firstIndex(of: "}")
            else {
                break
            }
            let token = String(text[afterOpen ..< closeIdx]).uppercased()
            if known.contains(token) {
                result.insert(token)
            }
            index = text.index(after: closeIdx)
        }
        return result
    }

    /// Expands every known macro in `text` against `context`. Unknown macros
    /// pass through unchanged. Missing or empty values become empty strings —
    /// callers that care about emptiness should call `missingMacros(in:context:)`
    /// first and reject before transmission.
    public static func expand(_ text: String, context: [String: String]) -> String {
        var result = text
        for token in known {
            let value = context[token] ?? ""
            result = result.replacingOccurrences(of: "{\(token)}", with: value)
        }
        return result
    }

    /// Returns the macro names that `text` requires but `context` doesn't
    /// satisfy (missing key or whitespace-only value). Sorted for stable
    /// error messages.
    public static func missingMacros(in text: String, context: [String: String]) -> [String] {
        let required = requiredMacros(in: text)
        var missing: [String] = []
        for token in required {
            let value = context[token] ?? ""
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append(token)
            }
        }
        return missing.sorted()
    }
}

// MARK: - CWStatusEvent

/// Sweep → Field. Mirror of the bridge keyer's runtime state. Emitted on the
/// `cw.keyer` topic whenever the bridge raises `cwStatus`, `cwAck`, or
/// `cwProgress`, and immediately after a client subscribes.
public struct CWStatusEvent: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        radioID: String,
        keyerAvailable: Bool,
        wpm: UInt8?,
        bufferDepth: UInt8,
        sendingSlot: UInt8?,
        isSending: Bool,
        timestamp: Date
    ) {
        self.radioID = radioID
        self.keyerAvailable = keyerAvailable
        self.wpm = wpm
        self.bufferDepth = bufferDepth
        self.sendingSlot = sendingSlot
        self.isSending = isSending
        self.timestamp = timestamp
    }

    // MARK: Public

    public let radioID: String
    /// True iff the bridge is connected and advertises CW keyer capability.
    public let keyerAvailable: Bool
    /// Last-known speed in WPM. nil until the first cwStatus arrives.
    public let wpm: UInt8?
    /// Pending bytes in the bridge's CW buffer.
    public let bufferDepth: UInt8
    /// 1...8 if a memory slot is currently playing, nil otherwise.
    public let sendingSlot: UInt8?
    /// True iff the bridge is actively keying (slot or freeform text).
    public let isSending: Bool
    public let timestamp: Date
}
