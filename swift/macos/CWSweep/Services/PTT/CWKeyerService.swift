import Foundation

// MARK: - KeyerContext

/// Context for macro expansion in CW messages.
struct KeyerContext {
    var myCall: String
    var hisCall: String
    var serial: Int
    var exchange: String
    var frequency: Double
}

// MARK: - SlotSnapshotEntry

/// Plain value type returned by `CWKeyerService.slotSnapshot()` for callers
/// that need to walk every memory slot (e.g. the Remote protocol layer
/// publishing a `cw.slots` event). Avoids large_tuple lint warnings.
struct SlotSnapshotEntry {
    let id: Int
    let label: String
    let text: String
}

// MARK: - CWKeyerService

/// Manages F1-F12 CW memory messages with macro expansion.
actor CWKeyerService {
    // MARK: Lifecycle

    init() {
        let defaults = UserDefaults.standard
        for slot in 1 ... 12 {
            if let text = defaults.string(forKey: "cwKeyer.message.\(slot)") {
                messages[slot] = text
            }
            if let label = defaults.string(forKey: "cwKeyer.label.\(slot)") {
                labels[slot] = label
            }
        }
    }

    // MARK: Internal

    /// Get message text for a slot (1-12)
    func message(for slot: Int) -> String {
        messages[slot] ?? Self.defaults[slot] ?? ""
    }

    /// Set message text for a slot
    func setMessage(slot: Int, text: String) {
        messages[slot] = text
        saveMessages()
    }

    /// Optional human-readable label for a slot (separate from the message
    /// text). Persisted alongside the message and surfaced over the Remote
    /// protocol so iOS can show short button captions (e.g. "73", "TU").
    func label(for slot: Int) -> String {
        labels[slot] ?? ""
    }

    /// Set the slot's display label.
    func setLabel(slot: Int, label: String) {
        labels[slot] = label
        UserDefaults.standard.set(label, forKey: "cwKeyer.label.\(slot)")
    }

    /// Snapshot of every slot in the bridge's addressable range (1...8) for
    /// remote mirroring. Always returns 8 entries — empty slots have empty
    /// `text` so the editor UI on Field can pick them as targets.
    func slotSnapshot() -> [SlotSnapshotEntry] {
        (1 ... 8).map { id in
            SlotSnapshotEntry(id: id, label: label(for: id), text: message(for: id))
        }
    }

    /// Expand macros in a message with the given context
    func expandMacros(_ text: String, context: KeyerContext) -> String {
        var result = text
        result = result.replacingOccurrences(of: "{MYCALL}", with: context.myCall)
        result = result.replacingOccurrences(of: "{HISCALL}", with: context.hisCall)
        result = result.replacingOccurrences(of: "{NR}", with: String(format: "%03d", context.serial))
        result = result.replacingOccurrences(of: "{EXCH}", with: context.exchange)
        result = result.replacingOccurrences(of: "{FREQ}", with: String(format: "%.1f", context.frequency))
        return result
    }

    /// Build the expanded message for a slot with context
    func expandedMessage(slot: Int, context: KeyerContext) -> String {
        let text = message(for: slot)
        return expandMacros(text, context: context)
    }

    // MARK: Private

    /// Default messages for common contest operations
    private static let defaults: [Int: String] = [
        1: "CQ CQ CQ DE {MYCALL} {MYCALL} K",
        2: "{HISCALL} 5NN {EXCH}",
        3: "TU {MYCALL}",
        4: "{HISCALL} AGN?",
        5: "NR?",
        6: "QSO B4",
        7: "73",
        8: "CQ TEST {MYCALL}",
        9: "{HISCALL} {HISCALL}",
        10: "R R",
        11: "?",
        12: "QRL?",
    ]

    /// Stored messages for F1-F12
    private var messages: [Int: String] = [:]
    /// Optional per-slot button labels (used by the Remote tab on Field).
    private var labels: [Int: String] = [:]

    // MARK: - Persistence

    private func loadMessages() {
        let defaults = UserDefaults.standard
        for slot in 1 ... 12 {
            if let text = defaults.string(forKey: "cwKeyer.message.\(slot)") {
                messages[slot] = text
            }
        }
    }

    private func saveMessages() {
        let defaults = UserDefaults.standard
        for (slot, text) in messages {
            defaults.set(text, forKey: "cwKeyer.message.\(slot)")
        }
    }
}
