// Macro Engine
//
// Enhanced macro system for CW Sweep with per-mode macro sets,
// ESM (Enter Sends Message) sequencing, and rich variable expansion.
// Supports F1-F12 messages for CW, SSB, and digital modes.

import Foundation

// MARK: - OperatingMode

/// Operating mode for macro set selection.
enum OperatingMode: String, CaseIterable, Codable {
    case cw = "CW"
    case ssb = "SSB"
    case digital = "DIGI"

    // MARK: Internal

    var label: String {
        rawValue
    }

    /// Derive from ADIF mode string.
    static func from(mode: String) -> OperatingMode {
        let upper = mode.uppercased()
        switch upper {
        case "CW":
            return .cw
        case "SSB",
             "LSB",
             "USB",
             "FM",
             "AM":
            return .ssb
        default:
            return .digital
        }
    }
}

// MARK: - MacroContext

/// Full context for macro variable expansion.
struct MacroContext {
    var myCall: String = ""
    var hisCall: String = ""
    var serial: Int = 1
    var exchange: String = ""
    var frequency: Double = 0
    var name: String = ""
    var parkRef: String = ""
    var gridSquare: String = ""
    var rstSent: String = "599"
    var power: String = ""
    var operatingMode: OperatingMode = .cw
}

// MARK: - ESMState

/// Enter Sends Message state machine.
/// Determines which macro to send based on QSO progress.
enum ESMState: String {
    /// No QSO in progress — send CQ (F1)
    case idle
    /// Callsign entered, no exchange received — send exchange (F2)
    case callEntered
    /// Exchange received — send TU/confirm (F3)
    case exchangeReceived
    /// QSO complete — send 73 and log (F7)
    case confirmed

    // MARK: Internal

    /// The F-key slot ESM should send in this state.
    var macroSlot: Int {
        switch self {
        case .idle: 1 // CQ
        case .callEntered: 2 // Exchange
        case .exchangeReceived: 3 // TU
        case .confirmed: 7 // 73
        }
    }
}

// MARK: - MacroSet

/// A named collection of F1-F12 macros for a specific mode.
struct MacroSet: Codable, Identifiable {
    let name: String
    let mode: OperatingMode
    var messages: [Int: String]

    var id: String {
        "\(mode.rawValue)-\(name)"
    }

    /// Get message for a slot, falling back to empty.
    func message(for slot: Int) -> String {
        messages[slot] ?? ""
    }
}

// MARK: - MacroEngine

/// Manages per-mode F1-F12 macro sets with variable expansion and ESM.
actor MacroEngine {
    // MARK: Lifecycle

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([MacroSet].self, from: data)
        {
            for macroSet in decoded {
                macroSets[macroSet.mode] = macroSet
            }
        }
    }

    // MARK: Internal

    /// Get the active macro set for a mode.
    func activeSet(for mode: OperatingMode) -> MacroSet {
        macroSets[mode] ?? Self.defaultSet(for: mode)
    }

    /// Get expanded message for a slot in the given mode.
    func expandedMessage(
        slot: Int, mode: OperatingMode, context: MacroContext
    ) -> String {
        let text = activeSet(for: mode).message(for: slot)
        return expandVariables(text, context: context)
    }

    /// ESM: get the appropriate macro for the current state.
    func esmMessage(
        state: ESMState, mode: OperatingMode, context: MacroContext
    ) -> String {
        expandedMessage(
            slot: state.macroSlot, mode: mode, context: context
        )
    }

    /// Update a single message slot.
    func setMessage(
        slot: Int, text: String, mode: OperatingMode
    ) {
        let current = macroSets[mode] ?? Self.defaultSet(for: mode)
        var messages = current.messages
        messages[slot] = text
        macroSets[mode] = MacroSet(
            name: current.name, mode: mode, messages: messages
        )
        saveSets()
    }

    /// Reset a mode's macros to defaults.
    func resetToDefaults(mode: OperatingMode) {
        macroSets[mode] = Self.defaultSet(for: mode)
        saveSets()
    }

    // MARK: - Variable Expansion

    /// Expand all {VARIABLE} placeholders in a macro string.
    func expandVariables(
        _ text: String, context: MacroContext
    ) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: "{MYCALL}", with: context.myCall
        )
        result = result.replacingOccurrences(
            of: "{HISCALL}", with: context.hisCall
        )
        result = result.replacingOccurrences(
            of: "{CALL}", with: context.hisCall
        )
        result = result.replacingOccurrences(
            of: "{NR}", with: String(format: "%03d", context.serial)
        )
        result = result.replacingOccurrences(
            of: "{SERIAL}", with: String(format: "%03d", context.serial)
        )
        result = result.replacingOccurrences(
            of: "{EXCH}", with: context.exchange
        )
        result = result.replacingOccurrences(
            of: "{FREQ}",
            with: String(format: "%.1f", context.frequency)
        )
        result = result.replacingOccurrences(
            of: "{NAME}", with: context.name
        )
        result = result.replacingOccurrences(
            of: "{PARK}", with: context.parkRef
        )
        result = result.replacingOccurrences(
            of: "{GRID}", with: context.gridSquare
        )
        result = result.replacingOccurrences(
            of: "{RST}", with: context.rstSent
        )
        result = result.replacingOccurrences(
            of: "{PWR}", with: context.power
        )
        return result
    }

    // MARK: Private

    private static let storageKey = "macroEngine.sets"

    private static let cwDefaults = MacroSet(
        name: "Default CW", mode: .cw,
        messages: [
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
    )

    private static let ssbDefaults = MacroSet(
        name: "Default SSB", mode: .ssb,
        messages: [
            1: "CQ CQ CQ this is {MYCALL}",
            2: "{HISCALL} you are {RST} {EXCH}",
            3: "Thank you, {MYCALL}",
            4: "{HISCALL} say again?",
            5: "Your number again?",
            6: "QSO before",
            7: "73",
            8: "CQ contest {MYCALL}",
        ]
    )

    private static let digitalDefaults = MacroSet(
        name: "Default Digital", mode: .digital,
        messages: [
            1: "CQ CQ DE {MYCALL} {MYCALL} K",
            2: "{HISCALL} {RST} {EXCH}",
            3: "TU 73",
            4: "AGN?",
        ]
    )

    private var macroSets: [OperatingMode: MacroSet] = [:]

    // MARK: - Defaults

    private static func defaultSet(
        for mode: OperatingMode
    ) -> MacroSet {
        switch mode {
        case .cw:
            cwDefaults
        case .ssb:
            ssbDefaults
        case .digital:
            digitalDefaults
        }
    }

    // MARK: - Persistence

    private func loadAllSets() {
        guard let data = UserDefaults.standard.data(
            forKey: Self.storageKey
        ),
            let decoded = try? JSONDecoder().decode(
                [MacroSet].self, from: data
            )
        else {
            return
        }
        for macroSet in decoded {
            macroSets[macroSet.mode] = macroSet
        }
    }

    private func saveSets() {
        let allSets = Array(macroSets.values)
        if let data = try? JSONEncoder().encode(allSets) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
