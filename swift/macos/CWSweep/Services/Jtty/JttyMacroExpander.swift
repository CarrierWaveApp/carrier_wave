import Foundation

// MARK: - JttyMacroContext

/// Values substituted into the F1–F8 templates.
struct JttyMacroContext: Equatable, Sendable {
    var myCall = ""
    var hisCall = ""
    /// Next-in-line station for `%Q` (TU NOW …).
    var queuedCall = ""
    var serial = 1
    /// Free-form exchange for the Field Day / RTTY Roundup profiles
    /// (`1D EMA`, `MA`). Ignored for the serial profile.
    var exchange = ""
    var grid = ""
    var profile: JttyExchangeProfile = .serial
}

// MARK: - JttyMacroExpander

/// WSJT-X's JTTY function-key macros: `%M` my call, `%H` his call, `%Q` the
/// queued call, `%E` the profile exchange (`599 nnn` for serials), `%N` the
/// bare serial, `%G` my grid. The eight defaults are WSJT-X's own, so the
/// messages pack into the compact native frames the sidecar recognises.
enum JttyMacroExpander {
    static let slotCount = 8

    /// WSJT-X 3.2 shipped defaults (lib/jtty/jtty_design.md).
    static let defaultTemplates: [String] = [
        "CQ %M CQ",
        "%H %E",
        "%H TU CQ %M CQ",
        "%M",
        "%H",
        "TU NOW %Q %E",
        "%H AGN?",
        "%E",
    ]

    /// Short labels for the F-key bar.
    static let slotLabels: [String] = ["CQ", "Exch", "TU CQ", "My call", "His call", "TU now", "AGN?", "Exch only"]

    static func expand(_ template: String, context: JttyMacroContext) -> String {
        // A `TU NOW %Q` message hands the *next* serial to the queued station
        // (WSJT-X's example: serial 107 to W9XYZ, then "TU NOW W7UVW 599 108").
        let serial = template.contains("%Q") ? context.serial + 1 : context.serial
        var result = template
        result = result.replacingOccurrences(of: "%M", with: context.myCall.uppercased())
        result = result.replacingOccurrences(of: "%H", with: context.hisCall.uppercased())
        result = result.replacingOccurrences(of: "%Q", with: context.queuedCall.uppercased())
        result = result.replacingOccurrences(of: "%E", with: exchangeText(context: context, serial: serial))
        result = result.replacingOccurrences(of: "%N", with: serialText(serial))
        result = result.replacingOccurrences(of: "%G", with: String(context.grid.uppercased().prefix(4)))
        return normalize(result)
    }

    /// The full exchange for `%E` under the active profile.
    static func exchangeText(context: JttyMacroContext, serial: Int? = nil) -> String {
        let serial = serial ?? context.serial
        let custom = context.exchange.trimmingCharacters(in: .whitespaces).uppercased()
        switch context.profile {
        case .serial:
            return "599 \(serialText(serial))"
        case .fieldDay:
            return custom
        case .rttyRoundup:
            return custom.isEmpty ? "599 \(serialText(serial))" : "599 \(custom)"
        }
    }

    /// Serials render with at least three digits, as WSJT-X does.
    static func serialText(_ serial: Int) -> String {
        String(format: "%03d", max(0, serial))
    }

    /// Upper-case and collapse whitespace; the helper does the rest of the
    /// source normalisation (unsupported characters become `#`).
    static func normalize(_ text: String) -> String {
        text.uppercased()
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .joined(separator: " ")
    }

    /// Whether the template still needs a value the operator has not filled in.
    static func missingFields(_ template: String, context: JttyMacroContext) -> [String] {
        var missing: [String] = []
        if template.contains("%M"), context.myCall.isEmpty {
            missing.append("my callsign")
        }
        if template.contains("%H"), context.hisCall.isEmpty {
            missing.append("his callsign")
        }
        if template.contains("%Q"), context.queuedCall.isEmpty {
            missing.append("queued callsign")
        }
        if template.contains("%E"), context.profile != .serial, context.exchange.isEmpty {
            missing.append("exchange")
        }
        return missing
    }
}
