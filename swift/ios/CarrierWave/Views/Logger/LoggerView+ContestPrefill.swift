import CarrierWaveCore
import CarrierWaveData
import Foundation

extension LoggerView {
    /// If we're in a contest that takes member-list exchanges (CWT today)
    /// and the entered callsign matches an enrichment row, prefill the
    /// exchange fields from cached enrichment data plus QRZ nickname.
    /// Re-runnable: each call clears the previous auto-fill (only if the
    /// user hasn't edited it) and re-applies, so a later QRZ result with
    /// a richer nickname can replace an earlier PoLo-only fill.
    /// Gated by `contestAutoFillExchange`.
    func prefillContestExchangeFromEnrichment(for callsign: String) {
        let autoFillEnabled = UserDefaults.standard.object(
            forKey: "contestAutoFillExchange"
        ) as? Bool ?? true
        guard autoFillEnabled else {
            return
        }
        guard isContestSession,
              let contestId = sessionManager?.activeSession?.contestId,
              ContestEnrichmentMatcher.sourceSlug(forContestId: contestId) != nil
        else {
            return
        }

        // Cache lookup may miss for non-CWops members — that's fine,
        // we still prefill name + S/P/C from the QRZ result below.
        let entry = CallsignEnrichmentCache.shared.lookup(callsign: callsign)

        // Drop our previous auto-fills before re-running so a richer
        // source (e.g. QRZ nickname arriving after the cached PoLo name)
        // can overwrite. User-typed values are preserved by the equality
        // check.
        clearAutoPrefilledContestFields()

        // CWT exchange convention: operator nickname ("Tim") beats the
        // PoLo registered first name ("Timothy D"). Fall back to fname
        // when nickname is absent from QRZ.
        let preferredName = (lookupResult?.nickname?.nonEmpty
            ?? lookupResult?.firstName?.nonEmpty)

        // Non-member identifier (S/P/C). State is reliable for US +
        // Canada; for DX, use the DXCC primary prefix derived from the
        // callsign so a German station gets `DL`, not whatever
        // freeform region tag QRZ may have stored in `<state>`.
        let fallbackIdentifier = nonMemberFallbackIdentifier(
            for: lookupResult,
            callsign: callsign
        )

        let written = ContestEnrichmentMatcher.prefill(
            from: entry,
            contestId: contestId,
            preferredName: preferredName,
            fallbackIdentifier: fallbackIdentifier,
            into: &contestExchangeValues
        )
        for (field, value) in written {
            prefilledContestFields[field] = value
        }
    }

    /// Resolve the non-member CWT exchange identifier:
    /// - US callsigns → state (e.g. `MD`)
    /// - Canadian callsigns → province (e.g. `ON`)
    /// - DX → DXCC primary prefix derived from the callsign (e.g. `DL`)
    /// Returns nil when none of the above can be resolved.
    private func nonMemberFallbackIdentifier(
        for info: CallsignInfo?,
        callsign: String
    ) -> String? {
        let countryLower = (info?.country ?? "").lowercased()
        let isUSorCanada = countryLower.contains("united states")
            || countryLower.contains("canada")

        if isUSorCanada,
           let state = info?.state?.trimmingCharacters(in: .whitespaces).nonEmpty
        {
            return state
        }

        if let entity = LocationPrefixLookup.entity(forCallsign: callsign) {
            return entity.prefix
        }

        return nil
    }

    /// Clear the contest exchange fields we previously auto-filled, but
    /// only if the user hasn't edited them since. Called when the callsign
    /// input is cleared so prior name/number don't linger, and before
    /// re-running the prefill so a richer source can replace an earlier
    /// auto-fill.
    func clearAutoPrefilledContestFields() {
        guard !prefilledContestFields.isEmpty else {
            return
        }
        for (field, prefilledValue) in prefilledContestFields
            where contestExchangeValues[field] == prefilledValue
        {
            contestExchangeValues[field] = ""
        }
        prefilledContestFields = [:]
    }
}
