// Callsign Lookup — orchestration + merge
//
// The single-result async API and the new streaming API both fan out to
// the same source backends (Polo notes, QRZ, local operator cache, HamDB,
// FCC) and merge results with this precedence for the displayed card:
//
//     QRZ > local cache > HamDB > FCC
//
// Polo notes always overlay emoji/note on top. HamDB never overwrites a
// value already present in QRZ or the local cache — it can only fill nil
// fields when no richer source is available. QRZ writes back to the
// local DB whenever its result changes the cached row.

import CarrierWaveData
import Foundation

extension CallsignLookupService {
    /// Look up a callsign with detailed result information.
    ///
    /// Cache hits short-circuit and return immediately — the in-memory LRU
    /// (current session) and the disk-backed operator-profile snapshot
    /// (prior QSOs + previous QRZ enrichment) are both consulted. When
    /// the disk cache hits, a background enrichment task fires so the
    /// next call sees fresh QRZ data and the local DB stays current.
    func lookupWithResult(_ callsign: String) async -> CallsignLookupResult {
        let normalizedCallsign = callsign.uppercased()

        if let cached = cache[normalizedCallsign], cached.age < maxCacheAge {
            return .success(cached)
        }

        // Disk rows have no TTL, so gate the fast path on enrichment age:
        // a fresh row short-circuits with background re-enrichment; a stale
        // (or undated) row must not — the operator may have changed name,
        // QTH, or even callsign since it was written. The full lookup still
        // falls back to the cached row when the network is unavailable.
        if let diskCached = OperatorProfileService.shared.cachedInfoSync(for: normalizedCallsign),
           Date().timeIntervalSince(diskCached.lookupDate) < OperatorProfileService.enrichmentStaleness
        {
            scheduleBackgroundEnrichment(for: normalizedCallsign)
            return .success(diskCached)
        }

        return await runFullLookup(normalizedCallsign)
    }

    /// Fan out to all sources, merge with QRZ-priority precedence, and
    /// write QRZ enrichment back to the local DB. Coalesces concurrent
    /// callers via `pendingResultLookups`.
    private func runFullLookup(_ normalizedCallsign: String) async -> CallsignLookupResult {
        if let pending = pendingResultLookups[normalizedCallsign] {
            return await pending.value
        }

        let task = Task<CallsignLookupResult, Never> {
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))

            async let poloInfoTask = lookupInPoloNotes(normalizedCallsign)
            async let qrzResultTask = lookupInQRZWithResult(normalizedCallsign)
            async let hamdbInfoTask = lookupInHamDB(normalizedCallsign)
            async let fccInfoTask = lookupInFCC(normalizedCallsign)
            async let cachedInfoTask = OperatorProfileService.shared.info(for: normalizedCallsign)

            let poloInfo = await poloInfoTask
            let qrzResult = await qrzResultTask
            let hamdbInfo = await hamdbInfoTask
            let fccInfo = await fccInfoTask
            let cachedInfo = await cachedInfoTask

            if let qrzInfo = qrzResult.info {
                await OperatorProfileService.shared.record(qrzInfo)
                await dropStaleAlias(queried: normalizedCallsign, canonical: qrzInfo.callsign)
            }

            return mergeResults(
                polo: poloInfo,
                qrz: qrzResult,
                cached: cachedInfo,
                hamdb: hamdbInfo,
                fcc: fccInfo
            )
        }

        pendingResultLookups[normalizedCallsign] = task
        let result = await task.value
        pendingResultLookups[normalizedCallsign] = nil
        return result
    }

    /// Fire-and-forget enrichment after a fast-path cache hit. The result
    /// is discarded — its only side effects are updating the LRU and
    /// writing the QRZ row back to `operator_profiles`. Coalesced via
    /// `pendingResultLookups` so simultaneous fast-path hits across
    /// views don't fan out duplicate QRZ requests.
    private func scheduleBackgroundEnrichment(for normalizedCallsign: String) {
        guard pendingResultLookups[normalizedCallsign] == nil else {
            return
        }
        Task { [weak self] in
            _ = await self?.runFullLookup(normalizedCallsign)
        }
    }

    /// Streamed lookup: yields the locally-cached result first (instant,
    /// from disk), then a single enriched result once the network sources
    /// resolve. HamDB never overwrites a cached or QRZ value in the
    /// displayed card — it can only fill nil fields when no richer source
    /// is available. QRZ always wins and writes back to the local DB on
    /// change.
    func lookupStream(_ callsign: String) -> AsyncStream<CallsignLookupResult> {
        let normalizedCallsign = callsign.uppercased()
        return AsyncStream { continuation in
            let task = Task {
                let cachedInfo = await OperatorProfileService.shared.info(for: normalizedCallsign)
                let initialPolo = await lookupInPoloNotes(normalizedCallsign)
                if let initial = mergeCachedFirstEmission(cached: cachedInfo, polo: initialPolo) {
                    continuation.yield(initial)
                }

                try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))

                async let qrzResultTask = lookupInQRZWithResult(normalizedCallsign)
                async let hamdbInfoTask = lookupInHamDB(normalizedCallsign)
                async let fccInfoTask = lookupInFCC(normalizedCallsign)
                async let poloInfoTask = lookupInPoloNotes(normalizedCallsign)

                let qrzResult = await qrzResultTask
                let hamdbInfo = await hamdbInfoTask
                let fccInfo = await fccInfoTask
                let poloInfo = await poloInfoTask

                if let qrzInfo = qrzResult.info {
                    await OperatorProfileService.shared.record(qrzInfo)
                    await dropStaleAlias(queried: normalizedCallsign, canonical: qrzInfo.callsign)
                }

                let enriched = mergeResults(
                    polo: poloInfo,
                    qrz: qrzResult,
                    cached: cachedInfo,
                    hamdb: hamdbInfo,
                    fcc: fccInfo
                )
                continuation.yield(enriched)
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// QRZ's `<call>` element is the operator's CURRENT call, so a lookup
    /// of an old (pre-vanity-change) callsign resolves forward. The fresh
    /// data was just recorded under the canonical call; drop the row and
    /// LRU entry keyed by the old call, or they'd keep rendering the stale
    /// identity on every future lookup.
    private func dropStaleAlias(queried: String, canonical: String) async {
        let canonicalUpper = canonical.uppercased()
        guard !canonicalUpper.isEmpty, canonicalUpper != queried else {
            return
        }
        await OperatorProfileService.shared.forget(queried)
        removeCachedEntry(for: queried)
    }

    // MARK: - Merge

    func mergeResults(
        polo: CallsignInfo?,
        qrz: CallsignLookupResult,
        cached: CallsignInfo?,
        hamdb: CallsignInfo?,
        fcc: CallsignInfo? = nil
    ) -> CallsignLookupResult {
        let stack: [CallsignInfo?] = [qrz.info, cached, hamdb, fcc]
        let canonicalCallsign = stack.compactMap { $0?.callsign }.first
        let hasOperatorData = stack.contains { $0 != nil }
        let displaySource: CallsignInfoSource =
            qrz.info != nil
                ? .qrz
                : cached?.source ?? (hamdb != nil ? .hamdb : .fcc)

        let memberships = enrichmentMemberships(for: canonicalCallsign ?? polo?.callsign)

        if !hasOperatorData {
            if let polo {
                let withMemberships = polo.withMemberships(memberships)
                updateCache(withMemberships)
                return .success(withMemberships)
            }
            if let error = qrz.error {
                return .error(error, qrzAttempted: true, poloNotesChecked: true)
            }
            return .notFound(qrzAttempted: true, poloNotesChecked: true)
        }

        // Preserve polo name as note when polo.note is nil — user-authored
        // context (e.g., "Bob") that would otherwise be replaced by the
        // remote name field.
        let poloNote = polo?.note ?? polo?.name

        let merged = CallsignInfo(
            callsign: canonicalCallsign ?? "",
            name: firstNonNil(stack, \.name),
            firstName: firstNonNil(stack, \.firstName),
            nickname: firstNonNil(stack, \.nickname),
            note: poloNote,
            emoji: polo?.emoji,
            qth: firstNonNil(stack, \.qth),
            state: firstNonNil(stack, \.state),
            country: firstNonNil(stack, \.country),
            grid: firstNonNil(stack, \.grid),
            licenseClass: firstNonNil(stack, \.licenseClass),
            previousCallsign: firstNonNil(stack, \.previousCallsign),
            source: displaySource,
            allEmojis: polo?.allEmojis,
            matchingSources: polo?.matchingSources,
            callsignChangeNote: firstNonNil(stack, \.callsignChangeNote),
            memberships: memberships
        )

        updateCache(merged)
        switch displaySource {
        case .qrz:
            return .fromQRZ(merged)
        case .hamdb:
            return .fromHamDB(merged)
        default:
            return .success(merged)
        }
    }

    /// Build the cached-only first-phase emission for the streaming API.
    /// Returns nil if neither the local cache nor Polo notes have anything
    /// to show — in that case the stream waits for the network.
    func mergeCachedFirstEmission(
        cached: CallsignInfo?,
        polo: CallsignInfo?
    ) -> CallsignLookupResult? {
        guard cached != nil || polo != nil else {
            return nil
        }
        let stack: [CallsignInfo?] = [cached]
        let poloNote = polo?.note ?? polo?.name
        let displaySource: CallsignInfoSource = cached?.source ?? .poloNotes
        let canonicalCallsign = cached?.callsign ?? polo?.callsign ?? ""
        let memberships = enrichmentMemberships(for: canonicalCallsign)
        let merged = CallsignInfo(
            callsign: canonicalCallsign,
            name: firstNonNil(stack, \.name) ?? polo?.name,
            firstName: firstNonNil(stack, \.firstName),
            nickname: firstNonNil(stack, \.nickname),
            note: poloNote,
            emoji: polo?.emoji,
            qth: firstNonNil(stack, \.qth),
            state: firstNonNil(stack, \.state),
            country: firstNonNil(stack, \.country),
            grid: firstNonNil(stack, \.grid),
            licenseClass: firstNonNil(stack, \.licenseClass),
            previousCallsign: firstNonNil(stack, \.previousCallsign),
            source: displaySource,
            allEmojis: polo?.allEmojis,
            matchingSources: polo?.matchingSources,
            memberships: memberships
        )
        return .success(merged)
    }

    /// Server-side enrichment (CWops, etc.) keyed by the canonical callsign.
    private func enrichmentMemberships(
        for callsign: String?
    ) -> [CallsignEnrichmentMembership]? {
        guard let callsign, !callsign.isEmpty else {
            return nil
        }
        return CallsignEnrichmentCache.shared.lookup(callsign: callsign)?.memberships
    }

    private func firstNonNil<Value>(
        _ stack: [CallsignInfo?],
        _ keyPath: KeyPath<CallsignInfo, Value?>
    ) -> Value? {
        for entry in stack {
            if let value = entry?[keyPath: keyPath] {
                return value
            }
        }
        return nil
    }
}
