import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - SessionStartSheet BKG lock

/// A BKG log is CW on 2 m. The Rust assembler enforces that when the session
/// starts; this keeps the wizard showing what will actually be started, so the
/// operator never sees 20 m SSB next to a selected BKG chip.
extension SessionStartSheet {
    var isBKGSelected: Bool {
        selectedPrograms.contains(BKGLog.programSlug)
    }

    /// While BKG is selected, hold the mode at CW and the frequency inside
    /// 2 m. A frequency already in the band is left alone. A partly typed
    /// value is left alone too, so the field stays editable; Rust snaps
    /// whatever is still out of band at Start.
    func applyBKGLock() {
        guard isBKGSelected else {
            return
        }
        let rules = bkgRules()
        if selectedMode != rules.mode {
            selectedMode = rules.mode
        }
        let inBand = parsedFrequency.map { $0 >= rules.bandLowMhz && $0 <= rules.bandHighMhz } ?? false
        // "14" or "144." while typing is not a frequency to correct yet.
        let isTyping = frequency.count < 5 && !frequency.isEmpty
        if !inBand, !isTyping {
            frequency = String(format: "%.3f", rules.defaultFrequencyMhz)
            frequencyOverridden = true
        }
    }
}
