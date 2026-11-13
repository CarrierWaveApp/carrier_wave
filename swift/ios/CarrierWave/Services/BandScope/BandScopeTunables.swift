import UIKit

// MARK: - BandScopeTunables

/// Every tunable constant from the Band Scope spec (§18) in one place —
/// nothing below may be hardcoded at a call site. Anchor-decay values are
/// placeholders to be recalibrated from logbook inter-QSO gaps.
enum BandScopeTunables {
    // MARK: - Scope (frequency lens)

    /// Chained pileup-cluster width (§10).
    static let clusterWidthKHz = 0.45

    /// Minimum clear-spectrum gap that earns a tappable QSY divider (§4).
    static let gapAffordanceKHz = 0.8

    /// Hard cap on gap-divider row height (§4).
    static let gapRowMaxHeight: CGFloat = 44

    /// Freshness fade: full ink up to this age … (§7). 5 min keeps calls
    /// bright through a typical activation/spot refresh cycle.
    static let fadeFullSeconds: TimeInterval = 300
    /// … linear to the floor by this age.
    static let fadeFloorSeconds: TimeInterval = 1_800
    /// Opacity floor — never dimmer than this from age alone.
    static let fadeFloorOpacity = 0.5

    /// Rows within this distance of the anchor render bold (§6).
    static let nearAnchorBoldKHz = 1.0

    /// Sticky frequency-header interval (§5); per-band later if needed.
    static let headerIntervalKHz = 5.0

    /// Dim opacity for WPM-ceiling rows in Heard and filtered scrubber
    /// ticks. (Scope hard-hides filtered spots as of 2026-07-04; the
    /// scrubber keeps dimmed ticks as the honest occupancy picture.)
    static let filteredDimOpacity = 0.35

    /// Scrubber viewport sync debounce (§3).
    static let scrubberSyncDebounce: TimeInterval = 0.1

    /// Scope row height (§8).
    static let rowHeight: CGFloat = 46

    // MARK: - Anchor trust decay (§6 — placeholders, all tunable)

    /// Anchor renders at full opacity for this long …
    static let anchorFullTrustSeconds: TimeInterval = 120
    /// … then fades linearly, reaching the floor here.
    static let anchorFloorSeconds: TimeInterval = 480
    /// Trust floor for YOU line, caret, and delta ink.
    static let anchorTrustFloor = 0.3
    /// Hard staleness: auto-clear and revert to absolute frequencies.
    static let anchorAutoClearSeconds: TimeInterval = 900

    // MARK: - Heard (recency lens)

    /// "Just now" bucket upper bound (§13).
    static let bucketJustNowSeconds: TimeInterval = 120
    /// "Last 15 min" bucket upper bound.
    static let bucketRecentSeconds: TimeInterval = 900
}
