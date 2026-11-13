import Foundation

// MARK: - CWKeyerPreset

//
// Mode-specific bundle of CW keyer slot text. Tapping a preset in
// `RemoteSweepCWPane` writes every entry to Sweep via repeated
// `cwSetSlot` calls; macros (e.g. `{MYCALL}`, `{HISSTATE}`) stay in
// the slot text and Sweep expands them at play time from its live
// Quick Entry box. Adding a new preset is a one-liner in `builtin`.

struct CWKeyerPreset: Identifiable, Hashable {
    struct SlotEntry: Hashable {
        let id: UInt8
        let label: String
        let text: String
    }

    let id: String
    let name: String
    let slots: [SlotEntry]
}

extension CWKeyerPreset {
    /// Built-in presets shown in the keyer pane's "PRESETS" menu.
    static let builtin: [CWKeyerPreset] = [
        CWKeyerPreset(
            id: "pota",
            name: "POTA",
            slots: [
                SlotEntry(id: 1, label: "CQ", text: "CQ CQ POTA DE {MYCALL} K"),
                SlotEntry(id: 2, label: "BK", text: "BK RR TU {HISSTATE} ES 73 EE"),
            ]
        ),
    ]
}
