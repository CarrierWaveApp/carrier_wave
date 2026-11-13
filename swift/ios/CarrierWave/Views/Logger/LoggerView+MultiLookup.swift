import CarrierWaveCore
import Foundation

// MARK: - IndexedLookupResult

/// Result of a single callsign lookup with its position in the multi-lookup array
private struct IndexedLookupResult {
    let index: Int
    let callsign: String
    let result: CallsignLookupResult
}

// MARK: - LoggerView Multi-Callsign Lookup

extension LoggerView {
    /// Look up multiple callsigns concurrently for multi-op contacts.
    /// Preserves existing lookup results for callsigns already resolved —
    /// only new or changed callsigns trigger network requests.
    func performMultiCallsignLookup(_ results: [QuickEntryResult]) {
        let callsigns = results.map {
            $0.callsign.trimmingCharacters(in: .whitespaces).uppercased()
        }

        let primaries = callsigns.map { extractPrimaryCallsign($0) }
        guard primaries.contains(where: { $0.count >= 3 }) else {
            return
        }

        // Carry over existing results; mark new callsigns as loading
        let (newResults, indicesToLookup) = mergeExistingLookups(callsigns: callsigns)
        multiLookupResults = newResults

        guard !indicesToLookup.isEmpty else {
            return
        }

        let service = CallsignLookupService(modelContext: modelContext)
        lookupTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }

            let lookupResults = await concurrentLookups(
                callsigns: callsigns, primaries: primaries,
                service: service, onlyIndices: indicesToLookup
            )

            for entry in lookupResults {
                guard !Task.isCancelled else {
                    return
                }
                let count = fetchPreviousQSOCount(for: primaries[entry.index])
                let state = toLookupState(
                    result: entry.result, callsign: entry.callsign, count: count
                )
                applyMultiLookupResult(index: entry.index, state: state)
            }
        }
    }

    /// Build new results array preserving already-resolved lookups.
    /// Returns the merged state array and indices that still need lookup.
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

    /// Run concurrent callsign lookups via TaskGroup, optionally restricted to specific indices
    private func concurrentLookups(
        callsigns: [String],
        primaries: [String],
        service: CallsignLookupService,
        onlyIndices: [Int]? = nil
    ) async -> [IndexedLookupResult] {
        let indices = onlyIndices ?? Array(callsigns.indices)
        return await withTaskGroup(of: IndexedLookupResult.self) { group in
            for index in indices {
                let primary = primaries[index]
                let callsign = callsigns[index]
                guard primary.count >= 3 else {
                    continue
                }
                group.addTask {
                    let result = await service.lookupWithResult(primary)
                    return IndexedLookupResult(
                        index: index, callsign: callsign, result: result
                    )
                }
            }
            var collected: [IndexedLookupResult] = []
            for await entry in group {
                collected.append(entry)
            }
            return collected
        }
    }

    /// Convert a lookup result to a MultiCallsignLookupState
    private func toLookupState(
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
        // Set lookupResult to first found result for form field compatibility
        if index == 0, let info = state.info {
            lookupResult = info
            previousQSOCount = state.previousQSOCount
        }
    }
}
