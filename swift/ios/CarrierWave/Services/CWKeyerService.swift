import UIKit

// MARK: - CWSlot

/// A single CW memory keyer slot (1–8).
struct CWSlot: Identifiable {
    let id: Int
    var label: String
    var text: String

    /// True when the slot has no message text.
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Display label: explicit label, or first word of template with `{}` stripped, or "Slot N".
    var displayLabel: String {
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        if !trimmedLabel.isEmpty {
            return trimmedLabel
        }

        let firstWord = text
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .first ?? ""

        let stripped = firstWord
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")

        if !stripped.isEmpty {
            return stripped
        }
        return "Slot \(id)"
    }
}

// MARK: - CWKeyerContext

/// Parameter bundle for building a macro substitution context.
struct CWKeyerContext {
    var callsign: String
    var myCall: String
    var myName: String
    var serial: Int
    var rstSent: String
    var name: String
    var exchange: String
}

// MARK: - CWKeyerService

/// Manages CW memory keyer slot storage and template expansion.
@MainActor
@Observable
final class CWKeyerService {
    // MARK: Lifecycle

    init() {
        slots = Self.loadSlots()
        wpm = UserDefaults.standard.integer(forKey: Keys.wpm)
        if wpm == 0 {
            wpm = defaultWPM
        }
    }

    // MARK: Internal

    static let maxSlots = 8
    static let maxSlotLength = 120

    /// All macro variables available in slot templates.
    static let macroVariables: [(macro: String, description: String)] = [
        (macro: "{MYCALL}", description: "Your callsign"),
        (macro: "{MYNAME}", description: "Your name"),
        (macro: "{CALL}", description: "Contact callsign"),
        (macro: "{NR}", description: "Serial number"),
        (macro: "{RST}", description: "RST sent"),
        (macro: "{NAME}", description: "Contact name"),
        (macro: "{EXCH}", description: "Exchange"),
    ]

    /// Prosign macros available in slot templates.
    static let macroProsigns: [String] = ["{BT}", "{AR}", "{SK}", "{KN}", "{AS}"]

    var slots: [CWSlot]

    var wpm: Int {
        didSet {
            let clamped = wpm.clamped(to: wpmRange)
            if clamped != wpm {
                wpm = clamped
            }
            UserDefaults.standard.set(wpm, forKey: Keys.wpm)
        }
    }

    /// Non-empty slots only, for display in keyer button strips.
    var programmedSlots: [CWSlot] {
        slots.filter { !$0.isEmpty }
    }

    /// Returns the slot with the given id (1-8).
    func slot(for id: Int) -> CWSlot? {
        slots.first { $0.id == id }
    }

    /// Persists updated label and text for the given slot id.
    func updateSlot(id: Int, label: String, text: String) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else {
            return
        }
        slots[index].label = String(label.prefix(8))
        slots[index].text = String(text.prefix(Self.maxSlotLength))
        let defaults = UserDefaults.standard
        defaults.set(label, forKey: Keys.slotLabel(id))
        defaults.set(slots[index].text, forKey: Keys.slotText(id))
    }

    /// Returns the first slot id with no text, or nil if all slots are filled.
    func nextEmptySlotID() -> Int? {
        slots.first { $0.isEmpty }?.id
    }

    /// Expands macros with sample values for preview display.
    /// Empty `myCall`/`myName` fall back to placeholders so the preview is
    /// never literal `{MYCALL}` / `{MYNAME}` even before the user has set
    /// up their profile.
    func expandForPreview(
        _ template: String,
        myCall: String = "",
        myName: String = "",
        exchange: String = ""
    ) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{MYCALL}", with: myCall.isEmpty ? "W6JY" : myCall)
        result = result.replacingOccurrences(of: "{MYNAME}", with: myName.isEmpty ? "JAY" : myName)
        result = result.replacingOccurrences(of: "{CALL}", with: "W1AW")
        result = result.replacingOccurrences(of: "{NR}", with: "001")
        result = result.replacingOccurrences(of: "{RST}", with: "599")
        result = result.replacingOccurrences(of: "{NAME}", with: "HIRAM")
        result = result.replacingOccurrences(of: "{EXCH}", with: exchange.isEmpty ? "5NN" : exchange)
        return result
    }

    /// Builds a macro substitution context for CW_SLOT_PLAY bridge commands.
    func buildContext(from params: CWKeyerContext) -> [String: String] {
        [
            "CALL": params.callsign,
            "MYCALL": params.myCall,
            "MYNAME": params.myName,
            "NR": String(format: "%03d", params.serial),
            "RST": params.rstSent.isEmpty ? "599" : params.rstSent,
            "NAME": params.name,
            "EXCH": params.exchange,
        ]
    }

    // MARK: Private

    private enum Keys {
        static let wpm = "cwKeyer.wpm"

        static func slotLabel(_ id: Int) -> String {
            "cwKeyer.slot.\(id).label"
        }

        static func slotText(_ id: Int) -> String {
            "cwKeyer.slot.\(id).text"
        }
    }

    private let defaultWPM = 20
    private let wpmRange = 5 ... 60

    private static func loadSlots() -> [CWSlot] {
        let defaults = UserDefaults.standard
        return (1 ... maxSlots).map { id in
            CWSlot(
                id: id,
                label: defaults.string(forKey: Keys.slotLabel(id)) ?? "",
                text: defaults.string(forKey: Keys.slotText(id)) ?? ""
            )
        }
    }
}

// MARK: - Comparable + clamped

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
