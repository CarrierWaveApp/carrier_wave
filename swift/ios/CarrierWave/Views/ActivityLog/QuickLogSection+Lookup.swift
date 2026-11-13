import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData
import SwiftUI

// MARK: - QuickLogSection Callsign Lookup

extension QuickLogSection {
    /// Trigger callsign lookup when input changes.
    /// Handles both single and multi-callsign quick entry.
    func onCallsignInputChanged(_ callsign: String) {
        let trimmed = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let multiResults = QuickEntryParser.parseMulti(trimmed, rstOrder: rstParseOrder)

        let currentCallsigns: [String] = if let multi = multiResults, multi.count >= 2 {
            multi.map { $0.callsign.uppercased() }
        } else {
            // A quick-entry line carries metadata after the callsign; dedup on the
            // parsed callsign so appending a park/RST doesn't re-trigger lookups.
            [QuickEntryParser.parse(trimmed, rstOrder: rstParseOrder)?.callsign.uppercased() ?? trimmed]
        }

        // Skip if detected callsigns haven't changed
        guard currentCallsigns != lastLookedUpCallsigns else {
            return
        }
        lastLookedUpCallsigns = currentCallsigns
        lookupTask?.cancel()

        // Multi-callsign path
        if let multi = multiResults, multi.count >= 2 {
            performMultiCallsignLookup(multi)
            return
        }

        // Clear multi-lookup state when back to single callsign
        if !multiLookupResults.isEmpty {
            multiLookupResults = []
            selectedMultiLookupIndex = 0
        }

        performSingleLookup(trimmed)
    }

    /// Look up a single callsign with 300ms debounce
    func performSingleLookup(_ input: String) {
        // Quick-entry lines carry metadata (park, RST, grid…) after the callsign;
        // enrich the callsign token, not the whole string. A bare callsign parses
        // to nil (needs 2+ tokens), so fall back to the input as-is. The command
        // guard still checks the full input so `FREQ 14.074` etc. skip lookup.
        let callsign = QuickEntryParser.parse(input, rstOrder: rstParseOrder)?.callsign ?? input
        let primary = extractPrimary(callsign)

        guard primary.count >= 3,
              LoggerCommand.parse(input) == nil
        else {
            if !input.isEmpty {
                lookupResult = nil
            }
            previousQSOCount = 0
            return
        }

        let context = modelContext
        lookupTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }

            let service = CallsignLookupService(modelContext: context)
            previousQSOCount = Self.fetchQSOCount(for: primary, context: context)

            // Streamed lookup: cached row first (instant from disk),
            // enriched row once QRZ/HamDB resolves.
            for await result in service.lookupStream(primary) {
                guard !Task.isCancelled else {
                    return
                }
                lookupResult = result.info
            }
        }
    }

    /// Look up multiple callsigns concurrently
    func performMultiCallsignLookup(_ results: [QuickEntryResult]) {
        let callsigns = results.map {
            $0.callsign.trimmingCharacters(in: .whitespaces).uppercased()
        }
        let primaries = callsigns.map { extractPrimary($0) }

        guard primaries.contains(where: { $0.count >= 3 }) else {
            return
        }

        let (merged, needed) = mergeExistingLookups(callsigns: callsigns)
        multiLookupResults = merged

        guard !needed.isEmpty else {
            return
        }

        let context = modelContext
        lookupTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }

            let results = await Self.concurrentLookups(
                callsigns: callsigns, primaries: primaries,
                indices: needed, context: context
            )

            for (index, state) in results {
                guard !Task.isCancelled else {
                    return
                }
                applyMultiLookupResult(index: index, state: state)
            }
        }
    }

    /// Run concurrent callsign lookups via TaskGroup.
    /// Lookups run concurrently; QSO counts are fetched on MainActor after.
    private static func concurrentLookups(
        callsigns: [String],
        primaries: [String],
        indices: [Int],
        context: ModelContext
    ) async -> [(Int, MultiCallsignLookupState)] {
        let service = CallsignLookupService(modelContext: context)

        // Phase 1: concurrent network lookups (no ModelContext access)
        let rawResults = await withTaskGroup(
            of: RawLookupResult.self
        ) { group in
            for index in indices {
                let primary = primaries[index]
                let callsign = callsigns[index]
                guard primary.count >= 3 else {
                    continue
                }
                group.addTask {
                    let result = await service.lookupWithResult(primary)
                    return RawLookupResult(
                        index: index, callsign: callsign, result: result
                    )
                }
            }
            var collected: [RawLookupResult] = []
            for await entry in group {
                collected.append(entry)
            }
            return collected
        }

        // Phase 2: build states with QSO counts (MainActor)
        return rawResults.map { raw in
            let primary = primaries[raw.index]
            let count = fetchQSOCount(for: primary, context: context)
            let state = toLookupState(
                result: raw.result, callsign: raw.callsign, count: count
            )
            return (raw.index, state)
        }
    }

    /// Clear all lookup state
    func clearLookupState() {
        lookupResult = nil
        previousQSOCount = 0
        multiLookupResults = []
        selectedMultiLookupIndex = 0
        lastLookedUpCallsigns = []
        lookupTask?.cancel()
        parkNames = [:]
        parkLookupTask?.cancel()
    }

    // MARK: - Helpers

    /// Extract primary callsign from portable/prefix callsigns
    /// e.g., "I/W6JSV/P" -> "W6JSV", "VE3/W6JSV" -> "W6JSV"
    func extractPrimary(_ callsign: String) -> String {
        let parts = callsign.split(separator: "/").map(String.init)
        guard parts.count > 1 else {
            return callsign
        }

        let knownSuffixes: Set = ["P", "M", "MM", "AM", "QRP", "R", "A", "B"]

        if parts.count == 2 {
            let first = parts[0]
            let second = parts[1]
            if knownSuffixes.contains(second) || second.count <= 2 {
                return first
            }
            if first.count <= 2 {
                return second
            }
            return first.count >= second.count ? first : second
        }
        if parts.count == 3 {
            return parts[1]
        }
        return parts.max(by: { $0.count < $1.count }) ?? parts[0]
    }

    /// Count all-time QSOs with a callsign (static to avoid isolation issues)
    @MainActor
    static func fetchQSOCount(for callsign: String, context: ModelContext) -> Int {
        let upper = callsign.uppercased()
        return
            (try? context.boundedCount(
                QSO.self,
                predicate: #Predicate<QSO> { qso in
                    qso.callsign == upper
                        && !qso.isHidden
                        && qso.mode != "WEATHER"
                        && qso.mode != "SOLAR"
                        && qso.mode != "NOTE"
                }
            )) ?? 0
    }

    /// Build merged state array, preserving resolved lookups
    private func mergeExistingLookups(
        callsigns: [String]
    ) -> ([MultiCallsignLookupState], [Int]) {
        let previousByCallsign = Dictionary(
            multiLookupResults.map { ($0.callsign, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var merged: [MultiCallsignLookupState] = []
        var needed: [Int] = []

        for (index, callsign) in callsigns.enumerated() {
            if let existing = previousByCallsign[callsign], !existing.isLoading {
                merged.append(existing)
            } else {
                merged.append(.loading(callsign: callsign))
                needed.append(index)
            }
        }
        return (merged, needed)
    }

    /// Convert a lookup result to MultiCallsignLookupState
    static func toLookupState(
        result: CallsignLookupResult,
        callsign: String,
        count: Int
    ) -> MultiCallsignLookupState {
        if let info = result.info {
            .found(info: info, previousQSOCount: count)
        } else if result.error == .notFound {
            .notFound(callsign: callsign)
        } else {
            .error(callsign: callsign, error: result.error ?? .notFound)
        }
    }

    /// Apply a single multi-lookup result to the state array
    private func applyMultiLookupResult(
        index: Int,
        state: MultiCallsignLookupState
    ) {
        guard index < multiLookupResults.count else {
            return
        }
        multiLookupResults[index] = state
        if index == 0, let info = state.info {
            lookupResult = info
            previousQSOCount = state.previousQSOCount
        }
    }
}

// MARK: - QuickLogSection Park Name Enrichment

extension QuickLogSection {
    /// Park references parsed from the current input, in typed order (each park
    /// of an n-fer). Empty when the line has no park token.
    var currentParkRefs: [String] {
        let trimmed = callsignInput.trimmingCharacters(in: .whitespaces)
        guard let park = QuickEntryParser.parse(trimmed, rstOrder: rstParseOrder)?.theirPark else {
            return []
        }
        return POTAClient.splitParkReferences(park)
    }

    /// Resolve POTA park names for the typed park refs, 300ms-debounced. Prunes
    /// cached names no longer referenced; looks up each still-unknown park.
    func resolveParks(_ input: String) {
        let refs = QuickEntryParser.parse(
            input.trimmingCharacters(in: .whitespaces), rstOrder: rstParseOrder
        )?.theirPark.map { POTAClient.splitParkReferences($0) } ?? []

        // Drop cached names for refs no longer present in the input.
        parkNames = parkNames.filter { refs.contains($0.key) }

        let needed = refs.filter { parkNames[$0] == nil }
        guard !needed.isEmpty else {
            return
        }

        parkLookupTask?.cancel()
        parkLookupTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }
            let loader = ParkDetailLoader()
            for ref in needed {
                guard let info = try? await loader.fetchPark(reference: ref),
                      !Task.isCancelled
                else {
                    continue
                }
                parkNames[ref] = info.name
            }
        }
    }

    /// Resolved park name(s) beneath the quick-entry preview — one row per park,
    /// showing the reference and its name (or a loading placeholder).
    @ViewBuilder
    var parkNameDisplay: some View {
        if !currentParkRefs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(currentParkRefs, id: \.self) { ref in
                    HStack(spacing: 6) {
                        Image(systemName: "tree.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(ref)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(parkNames[ref] ?? "Looking up…")
                            .font(.caption)
                            .foregroundStyle(parkNames[ref] == nil ? Color.secondary : Color.primary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - RawLookupResult

/// Intermediate result from concurrent lookup before QSO count enrichment
private struct RawLookupResult {
    let index: Int
    let callsign: String
    let result: CallsignLookupResult
}
