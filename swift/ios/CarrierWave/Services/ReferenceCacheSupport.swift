// Reference Cache Support
//
// Shared status enum and query-side helpers (name-index search, haversine)
// for the reference data caches (POTAParksCache, SOTASummitsCache,
// WWFFReferencesCache). Download, parse, and persistence live in the Rust
// core (`ReferenceDataApi`); the old CSV/disk pipeline is gone.

import Foundation

// MARK: - ReferenceCacheStatus

/// Shared status enum for all reference caches
nonisolated enum ReferenceCacheStatus {
    case notLoaded
    case loading
    case loaded(recordCount: Int, downloadedAt: Date?)
    case downloading
    case failed(String)
}

// MARK: - NameIndexSearch

/// Shared binary search + prefix matching for sorted name indexes.
/// Used by SOTASummitsCache and WWFFReferencesCache for full-text search.
nonisolated enum NameIndexSearch {
    /// Find all codes whose indexed word starts with `prefix` using binary search
    static func codesMatchingPrefix(
        _ prefix: String,
        in index: [(word: String, codes: [String])]
    ) -> Set<String> {
        guard !index.isEmpty else {
            return []
        }

        var lo = 0
        var hi = index.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if index[mid].word < prefix {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        var result = Set<String>()
        while lo < index.count, index[lo].word.hasPrefix(prefix) {
            result.formUnion(index[lo].codes)
            lo += 1
        }
        return result
    }

    /// Search by name across all query words, returning codes matching ALL words
    static func searchByName(
        _ query: String,
        in index: [(word: String, codes: [String])],
        limit: Int = 20
    ) -> Set<String> {
        let queryWords = query.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard !queryWords.isEmpty else {
            return []
        }

        var matchingCodes: Set<String>?

        for word in queryWords {
            let wordMatches = codesMatchingPrefix(word, in: index)

            if let existing = matchingCodes {
                matchingCodes = existing.intersection(wordMatches)
            } else {
                matchingCodes = wordMatches
            }

            if matchingCodes?.isEmpty == true {
                return []
            }
        }

        return matchingCodes ?? []
    }
}

// MARK: - HaversineDistance

/// Haversine formula for great-circle distance. Used by SOTA and WWFF nearby lookups.
nonisolated enum HaversineDistance {
    static func distance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let earthRadiusKm = 6_371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let lat1Rad = lat1 * .pi / 180
        let lat2Rad = lat2 * .pi / 180
        let haversineLat = sin(dLat / 2) * sin(dLat / 2)
        let haversineLon = sin(dLon / 2) * sin(dLon / 2) * cos(lat1Rad) * cos(lat2Rad)
        let centralAngle =
            2 * atan2(
                sqrt(haversineLat + haversineLon),
                sqrt(1 - haversineLat - haversineLon)
            )
        return earthRadiusKm * centralAngle
    }
}
