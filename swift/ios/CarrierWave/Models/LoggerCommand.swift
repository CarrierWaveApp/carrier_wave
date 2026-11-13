import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - LoggerCommand

/// Commands that can be entered in the logger input field
enum LoggerCommand: Equatable {
    /// Change frequency (e.g., "14.060" or "FREQ 14.060")
    case frequency(Double)

    /// Change mode (e.g., "MODE CW")
    case mode(String)

    /// Self-spot to POTA with optional comment and optional repeat interval in minutes
    case spot(comment: String?, repeatMinutes: Int? = nil)

    /// Stop the repeating spot timer
    case spotStop

    /// Show RBN spots panel for a callsign (nil = user's callsign)
    case rbn(callsign: String?)

    /// Show activator spots panel (POTA + SOTA)
    case hunt

    /// Log a one-off QSO at a different frequency/mode without changing the session
    /// (e.g., "HUNT W6JY 14067 CW"). Carries the full QuickEntryResult so all
    /// metadata (RST, park, grid, state, notes, time) flows through.
    case huntLog(QuickEntryResult)

    /// Show P2P (park-to-park) opportunities panel
    case p2p

    /// Show S2S (summit-to-summit) opportunities panel — current SOTA
    /// spots that could yield an S2S contact for an active SOTA session.
    case s2s

    /// Show solar conditions panel
    case solar

    /// Show weather panel
    case weather

    /// Show session map
    case map

    /// Show hidden QSOs
    case hidden

    /// Show help
    case help

    /// Add a note to the session log
    case note(text: String)

    /// Open radio manual in CW Field Guide
    case manual

    /// Show WebSDR recording panel
    case websdr

    /// Show band picker with recommended frequencies
    case band

    /// Change radio/rig
    case rig

    /// Open outing checklists in CW Field Guide
    case checklist

    /// Show BLE radio control panel
    case radio

    /// Replay last N seconds of SDR audio
    case replay

    /// Change the station callsign for this session
    case myCall(String)

    /// Set several session fields at once from a callsign-less line
    /// (e.g., "14.046 CW CN87"). Applies to future QSOs, not a single log.
    case sessionMetadata(SessionMetadataEntry)

    // MARK: Internal

    /// Help text listing all available commands
    static var helpText: String {
        """
        Available Commands:

        FREQ <freq>     - Set frequency
                          e.g., 14.060, 14060 kHz, 14.060 MHz
        BAND            - Pick band with recommended frequencies
        MODE <mode>     - Set mode (CW, SSB, FT8, etc.)
                          or type mode directly: CW, SSB, FT8
        RIG             - Change equipment (radio, antenna, key)
        SPOT [comment]  - Self-spot to POTA
                          e.g., SPOT QRT, SPOT QSY
        SPOT [comment] REPEAT <min>
                        - Spot and repeat every <min> minutes
                          e.g., SPOT QRQ REPEAT 5
        SPOT STOP       - Stop repeating spot timer
        QRT             - Self-spot QRT to POTA
        RBN [callsign]  - Show RBN/POTA spots
                          e.g., RBN W1AW (or just RBN for your spots)
        HUNT            - Show activator spots (POTA + SOTA)
                          (or POTA, SPOTS)
        HUNT <call> [freq] [mode]
                        - Log a one-off QSO without changing
                          the session. Pass freq, mode, or both;
                          missing fields fall back to the session,
                          e.g., HUNT W6JY 14067 CW or HUNT N9HO 14060
        P2P             - Find park-to-park opportunities
                          (POTA activations only)
        S2S             - Find summit-to-summit opportunities
                          (SOTA activations only)
        SOLAR           - Show solar conditions
        WEATHER         - Show weather (or WX)
        MAP             - Show session QSO map
        HIDDEN          - Show deleted QSOs (or DELETED)
        NOTE <text>     - Add a note to the session log
        MANUAL          - Open radio manual (or MAN)
        CHECKLIST       - Open outing checklists (or CL)
        WEBSDR          - Record from a nearby WebSDR
                          (or SDR, REC, RECORD, SWL)
        RADIO           - Show BLE radio control panel
                          (or CAT, RIG-BLE)
        MYCALL <call>    - Set your station callsign
                          e.g., MYCALL W5ABC
        REPLAY          - Replay last 15s of SDR audio
                          (or AGN, HUH)
        HELP            - Show this help (or ?)

        Type a frequency directly: 14.060, 14060, 14060kHz
        Combine session fields in one line: 14.046 CW CN87
        (sets frequency, mode, and your grid for future QSOs)
        """
    }

    /// Description of the command for display
    var description: String {
        switch self {
        case let .frequency(freq):
            "Set frequency to \(FrequencyFormatter.formatWithUnit(freq))"
        case let .mode(mode):
            "Set mode to \(mode)"
        case let .spot(comment, repeatMinutes):
            if let repeatMinutes {
                if let comment, !comment.isEmpty {
                    "Self-spot to POTA: \"\(comment)\" every \(repeatMinutes)m"
                } else {
                    "Self-spot to POTA every \(repeatMinutes)m"
                }
            } else if let comment, !comment.isEmpty {
                "Self-spot to POTA: \"\(comment)\""
            } else {
                "Self-spot to POTA"
            }
        case .spotStop:
            "Stop repeating spot timer"
        case let .rbn(callsign):
            if let callsign {
                "Show spots for \(callsign)"
            } else {
                "Show your spots"
            }
        case .hunt:
            "Show activator spots"
        case let .huntLog(result):
            huntLogDescription(result)
        case .p2p:
            "Find P2P opportunities"
        case .s2s:
            "Find S2S opportunities"
        case .solar:
            "Show solar conditions"
        case .weather:
            "Show weather"
        case .map:
            "Show session map"
        case .hidden:
            "Show deleted QSOs"
        case .help:
            "Show available commands"
        case let .note(text):
            "Add note: \"\(text)\""
        case .manual:
            "Open radio manual"
        case .checklist:
            "Open outing checklists"
        case .websdr:
            "Record from WebSDR"
        case .band:
            "Pick band with recommended frequencies"
        case .rig:
            "Change equipment"
        case .radio:
            "Show radio control panel"
        case .replay:
            "Replay last SDR audio"
        case let .myCall(call):
            "Set station callsign to \(call)"
        case let .sessionMetadata(entry):
            sessionMetadataDescription(entry)
        }
    }

    /// Icon for the command
    var icon: String {
        switch self {
        case .frequency:
            "antenna.radiowaves.left.and.right"
        case .mode:
            "waveform"
        case .spot,
             .spotStop:
            "mappin.and.ellipse"
        case .rbn:
            "dot.radiowaves.up.forward"
        case .hunt:
            "binoculars"
        case .huntLog:
            "binoculars.fill"
        case .p2p:
            "arrow.left.arrow.right"
        case .s2s:
            "mountain.2"
        case .solar:
            "sun.max"
        case .weather:
            "cloud.sun"
        case .map:
            "map"
        case .hidden:
            "eye.slash"
        case .help:
            "questionmark.circle"
        case .note:
            "note.text"
        case .manual:
            "book.closed"
        case .checklist:
            "checklist"
        case .websdr:
            "radio"
        case .band:
            "list.bullet.rectangle.portrait"
        case .rig:
            "radio"
        case .radio:
            "antenna.radiowaves.left.and.right"
        case .replay:
            "backward.fill"
        case .myCall:
            "person.text.rectangle"
        case .sessionMetadata:
            "slider.horizontal.3"
        }
    }

    // MARK: Private

    /// Description for a session-metadata update — must make it obvious the
    /// change applies to QSOs logged from now on, and which tokens are ignored.
    private func sessionMetadataDescription(_ entry: SessionMetadataEntry) -> String {
        var parts: [String] = []
        if let freq = entry.frequency {
            let band = entry.band.map { " (\($0))" } ?? ""
            parts.append("\(FrequencyFormatter.formatWithUnit(freq))\(band)")
        }
        if let mode = entry.mode {
            parts.append(mode)
        }
        if let grid = entry.grid {
            parts.append("grid \(grid)")
        }
        var text = "Set session for future QSOs: \(parts.joined(separator: " · "))"
        if !entry.unsupported.isEmpty {
            text += " — can't set: \(entry.unsupported.joined(separator: ", "))"
        }
        return text
    }

    /// Description for a HUNT one-off log
    private func huntLogDescription(_ result: QuickEntryResult) -> String {
        var parts = ["Log \(result.callsign)"]
        if let freq = result.frequency {
            parts.append("at \(FrequencyFormatter.formatWithUnit(freq))")
        }
        if let mode = result.mode {
            parts.append(mode)
        }
        return parts.joined(separator: " ")
    }
}
