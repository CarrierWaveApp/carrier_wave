import CarrierWaveCore
import SwiftUI

// MARK: - LoggerView S2S (Summit-to-Summit) Enrichment

extension LoggerView {
    /// Refresh the shared SOTA spots cache for S2S enrichment.
    /// Cache-side throttle handles network rate-limiting — see
    /// `SOTASpotsCache.refreshIfStale` (30 s freshness window).
    func refreshSOTASpots() async {
        guard sessionManager?.hasActiveSession == true else {
            return
        }
        await SOTASpotsCache.shared.refreshIfStale()
        await MainActor.run {
            cachedSOTASpots = SOTASpotsCache.shared.spotsSync()
        }
    }

    /// Look up the most recent SOTA spot for a callsign (case- and
    /// portable-suffix-insensitive). Returns nil if no current spot matches.
    /// Reads from the shared cache so consumers stay consistent with the
    /// HUNT panel.
    func sotaSpotForCallsign(_ callsign: String) -> SOTASpot? {
        let normalized = SOTASpot.normalizeCallsign(callsign)
        guard !normalized.isEmpty else {
            return nil
        }
        let pool = cachedSOTASpots.isEmpty
            ? SOTASpotsCache.shared.spotsSync()
            : cachedSOTASpots
        return pool.first {
            SOTASpot.normalizeCallsign($0.activatorCallsign) == normalized
        }
    }

    /// Cross-reference callsign against active SOTA spots and auto-fill the
    /// `theirSummit` field with the activator's current summit reference.
    ///
    /// - If the new callsign matches a current SOTA spot: write its summit
    ///   into `theirSummit` and record it in `autoFilledSummit` so we know
    ///   we own that value.
    /// - If it does NOT match and `theirSummit` still equals the previous
    ///   auto-fill: clear it. This is the fix for "callsigns not on a
    ///   mountain are erroneously getting a previous activator's summit"
    ///   — the field used to be sticky.
    /// - A hand-typed value (where `theirSummit != autoFilledSummit`) is
    ///   never touched.
    /// - If the shared cache is cold, kicks off a refresh and re-runs
    ///   the same logic once it lands, guarded against stale callsign edits.
    func updateSOTASpotMatches(for callsign: String) {
        applyS2SMatch(for: callsign, fromCache: cachedSOTASpots)

        // If we matched, we're done. Otherwise, if the cache is empty,
        // try a refresh and re-apply once it lands.
        if sotaSpotForCallsign(callsign) != nil {
            return
        }
        let typed = callsign
        Task {
            await SOTASpotsCache.shared.refreshIfStale()
            let spots = SOTASpotsCache.shared.spotsSync()
            await MainActor.run {
                cachedSOTASpots = spots
                guard callsignInput.uppercased().hasPrefix(typed.uppercased()) ||
                    typed.uppercased().hasPrefix(callsignInput.uppercased())
                else {
                    return
                }
                applyS2SMatch(for: typed, fromCache: spots)
            }
        }
    }

    /// Resolve a single callsign-vs-spots match decision. Splits the
    /// fill / clear / preserve cases out so the cache-cold retry can reuse
    /// it without duplicating the precedence rules.
    private func applyS2SMatch(for callsign: String, fromCache spots: [SOTASpot]) {
        let normalized = SOTASpot.normalizeCallsign(callsign)
        let match = spots.first {
            SOTASpot.normalizeCallsign($0.activatorCallsign) == normalized
        }

        if let match {
            // Auto-fill if empty, or refresh an existing auto-fill so a
            // re-spotted activator's updated summit ref wins.
            if theirSummit.isEmpty || theirSummit == autoFilledSummit {
                theirSummit = match.fullSummitReference
                autoFilledSummit = match.fullSummitReference
            }
            return
        }

        // No match. Clear only if the current value is one we wrote — never
        // clobber something the user typed by hand.
        if let auto = autoFilledSummit, theirSummit == auto {
            theirSummit = ""
            autoFilledSummit = nil
        }
    }
}
