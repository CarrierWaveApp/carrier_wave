// Contest Enrichment Matcher
//
// Pure-logic mapping between contest IDs (`cwops-cwt`, future `skcc-wes`,
// etc.) and the enrichment source slug whose member list provides the
// exchange. Facade over `cw_domain::contest::enrichment` — the membership is
// resolved from the enrichment entry here (a Swift model), then the fill
// rules run in Rust so iOS Field and CW Sweep share them.

import CarrierWaveCore
import Foundation

public enum ContestEnrichmentMatcher {
    // MARK: Public

    /// Enrichment source slug whose membership data fills the exchange for a
    /// contest id, if the contest supports prefill.
    public static func sourceSlug(forContestId contestId: String) -> String? {
        contestEnrichmentSourceSlug(contestId: contestId)
    }

    /// Mutate `values` in place, populating the name/identifier fields if
    /// they're currently empty. Returns the keys/values that were written
    /// so the caller can later clear them (e.g. when the callsign is
    /// cleared) without disturbing user-typed entries.
    ///
    /// Sources, in priority order:
    /// - `name` ← `preferredName` (e.g. QRZ `<nickname>` → "TIM") overrides
    ///   the membership-list registered name; falls back to the membership
    ///   name when no nickname is available.
    /// - `identifier` ← member number from the matched membership. Falls
    ///   back to `fallbackIdentifier` for non-members (state for US,
    ///   province for Canada, DXCC prefix for DX).
    @discardableResult
    public static func prefill(
        from entry: CallsignEnrichmentEntry?,
        contestId: String,
        preferredName: String? = nil,
        fallbackIdentifier: String? = nil,
        into values: inout [String: String]
    ) -> [String: String] {
        guard let slug = sourceSlug(forContestId: contestId) else {
            return [:]
        }
        let membership = entry?.membership(forSourceSlug: slug)
        let written = contestEnrichmentPrefill(
            contestId: contestId,
            membershipName: membership?.name,
            memberNumber: membership?.memberNumber,
            preferredName: preferredName,
            fallbackIdentifier: fallbackIdentifier,
            currentValues: values
        )
        for (key, value) in written {
            values[key] = value
        }
        return written
    }

    // MARK: Internal

    /// Reduce a member-list / QRZ name to the first whitespace token in
    /// ALL CAPS — the CWT wire-format convention. `"Timothy D"` → `"TIMOTHY"`.
    static func formatExchangeName(_ rawName: String) -> String {
        contestFormatExchangeName(rawName: rawName)
    }
}
