import Foundation

/// Where tuning to a spot actually lands. Sweep's "Tune & Log" used to look
/// like a silent no-op whenever no radio was connected; resolving the
/// destination up front lets the UI say what will happen and lets the radio
/// command log record what did happen (CAR-121).
enum SpotTuneDestination: Equatable {
    /// A CAT-connected radio on the target slot is retuned.
    case radio(name: String?)
    /// No radio, but the external SDR waterfall is enabled: it recentres and
    /// the log entry is prefilled.
    case sdrWaterfall
    /// Nothing is connected: the tune only sets the log entry frequency/mode.
    case logEntryOnly

    // MARK: Internal

    /// Explanatory footer for the spot context menu. `nil` when a radio is
    /// connected: tuning does the obvious thing and needs no caveat.
    var contextMenuFootnote: String? {
        switch self {
        case .radio:
            nil
        case .sdrWaterfall:
            "No radio connected — Tune moves the SDR waterfall and log entry"
        case .logEntryOnly:
            "No radio connected — Tune only sets the log entry frequency"
        }
    }

    /// Pure resolution from the current radio/SDR state.
    static func resolve(
        isRadioConnected: Bool,
        radioName: String?,
        sdrWaterfallEnabled: Bool
    ) -> SpotTuneDestination {
        if isRadioConnected {
            return .radio(name: radioName)
        }
        if sdrWaterfallEnabled {
            return .sdrWaterfall
        }
        return .logEntryOnly
    }

    /// Status line for the radio command log after a spot tune that had no
    /// radio to talk to. `nil` for `.radio` (the CAT traffic is logged anyway).
    func noRadioStatusLine(frequencyMHz: Double, mode: String) -> String? {
        let freq = String(format: "%.3f MHz", frequencyMHz)
        let target = mode.isEmpty ? freq : "\(freq) \(mode)"
        switch self {
        case .radio:
            return nil
        case .sdrWaterfall:
            return "No radio connected — set \(target) for the SDR waterfall and log entry"
        case .logEntryOnly:
            return "No radio connected — set \(target) for the log entry"
        }
    }
}
