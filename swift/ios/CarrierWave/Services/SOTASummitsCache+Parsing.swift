// SOTA Summits Cache - Name Index
//
// Name index building and distance helpers for the SOTA summits cache
// full-text and nearby search. Summit download, CSV parsing, and storage
// live in the Rust core (`ReferenceDataApi`).

import Foundation

extension SOTASummitsCache {
    /// Build the name index for full-text search
    /// Maps lowercase words to arrays of summit codes.
    /// Indexes summit name words and code segments (association, region).
    /// Produces a sorted array for O(log n) prefix search.
    func buildNameIndex() {
        var index: [String: [String]] = [:]
        let snapshot = summitsSnapshot()

        for (code, summit) in snapshot {
            let nameWords = summit.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && $0.count >= 2 }

            let codeWords = code.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }

            for word in nameWords + codeWords {
                index[word, default: []].append(code)
            }
        }

        let built = index
            .map { (word: $0.key, codes: $0.value) }
            .sorted { $0.word < $1.word }
        storeNameIndex(built)
    }

    /// Calculate distance between two coordinates using Haversine formula
    nonisolated func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        HaversineDistance.distance(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
    }
}
