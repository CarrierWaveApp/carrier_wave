import UIKit

// MARK: - BandScopeAnchor

/// The dial-by-declaration anchor (spec §6): set when the user taps Tune
/// or logs a QSO — never by dragging. While fresh it flips Scope's
/// frequency column to signed deltas and draws the YOU line + scrubber
/// caret; trust decays with age and the whole thing auto-clears.
struct BandScopeAnchor: Equatable {
    let frequencyKHz: Double
    let band: String
    let setAt: Date

    /// Trust in [floor, 1]: full for `anchorFullTrustSeconds`, linear
    /// fade to the floor by `anchorFloorSeconds`. Applies to the YOU
    /// line, the caret, AND the delta ink — stale deltas at full ink are
    /// the anchor lying.
    func trust(at now: Date = Date()) -> Double {
        let age = now.timeIntervalSince(setAt)
        let full = BandScopeTunables.anchorFullTrustSeconds
        let floorAt = BandScopeTunables.anchorFloorSeconds
        let floor = BandScopeTunables.anchorTrustFloor
        if age <= full {
            return 1.0
        }
        if age >= floorAt {
            return floor
        }
        let progress = (age - full) / (floorAt - full)
        return 1.0 - progress * (1.0 - floor)
    }

    /// Hard staleness (§6): past this the anchor no longer exists.
    func isExpired(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(setAt) >= BandScopeTunables.anchorAutoClearSeconds
    }
}

// MARK: - AnchorStore

/// Owns the (single, global) anchor. Rendered only in Scope in v1 (§6):
/// Heard is multi-band and cross-band deltas are nonsense.
@MainActor
@Observable
final class AnchorStore {
    private(set) var anchor: BandScopeAnchor?

    /// The anchor if it is still live for the given band; expired or
    /// cross-band anchors read as nil (band change clears, §6).
    func activeAnchor(band: String, now: Date = Date()) -> BandScopeAnchor? {
        guard let anchor, anchor.band == band, !anchor.isExpired(at: now) else {
            return nil
        }
        return anchor
    }

    /// Set/refresh from a Tune tap or a logged QSO.
    func declare(frequencyKHz: Double, band: String, now: Date = Date()) {
        anchor = BandScopeAnchor(frequencyKHz: frequencyKHz, band: band, setAt: now)
    }

    /// The × on the YOU line, or a band change.
    func clear() {
        anchor = nil
    }

    /// Drop an expired anchor so observers stop seeing it (called from
    /// the render timeline; harmless to call often).
    func sweepExpired(now: Date = Date()) {
        if let anchor, anchor.isExpired(at: now) {
            self.anchor = nil
        }
    }
}
