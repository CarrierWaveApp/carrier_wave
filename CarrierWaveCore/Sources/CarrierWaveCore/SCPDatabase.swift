import Foundation

// MARK: - SCPDatabase

/// In-memory Super Check Partial database for fast callsign matching.
/// Holds ~80K callsigns from MASTER.SCP and provides partial, exact, and fuzzy lookup.
public struct SCPDatabase: Sendable {
    // MARK: Lifecycle

    /// Initialize from a collection of callsigns. Deduplicates and uppercases.
    public init(callsigns: some Collection<String>) {
        var seen = Set<String>()
        var unique: [String] = []
        for call in callsigns {
            let upper = call.uppercased()
            guard !upper.isEmpty, seen.insert(upper).inserted else { continue }
            unique.append(upper)
        }
        unique.sort()
        self.sorted = unique
        self.callsignSet = seen
    }

    // MARK: Public

    /// Number of callsigns in the database.
    public var count: Int { sorted.count }

    /// Whether the database has no callsigns loaded.
    public var isEmpty: Bool { sorted.isEmpty }

    /// Classic SCP: all callsigns containing the fragment (case-insensitive).
    /// Returns up to `limit` matches, sorted alphabetically.
    /// Fragments shorter than 3 characters return empty results.
    public func partialMatch(_ fragment: String, limit: Int = 20) -> [String] {
        let upper = fragment.uppercased()
        guard upper.count >= 3 else { return [] }

        var results: [String] = []
        results.reserveCapacity(limit)

        // Prefix matches first (most relevant), then substring
        for call in sorted {
            guard results.count < limit else { break }
            if call.hasPrefix(upper) {
                results.append(call)
            }
        }

        if results.count < limit {
            for call in sorted {
                guard results.count < limit else { break }
                if !call.hasPrefix(upper), call.contains(upper) {
                    results.append(call)
                }
            }
        }

        return results
    }

    /// Is this exact callsign in the database? (Case-insensitive)
    public func contains(_ callsign: String) -> Bool {
        callsignSet.contains(callsign.uppercased())
    }

    /// Near-misses within edit distance. Only useful for complete callsigns (4+ chars).
    /// Skips exact matches (distance == 0).
    public func nearMatches(
        for callsign: String,
        maxDistance: Int = 1
    ) -> [(callsign: String, distance: Int)] {
        guard callsign.count >= 4 else { return [] }
        return CallsignEditDistance.findNearMatches(
            for: callsign,
            maxDistance: maxDistance,
            candidates: sorted
        )
    }

    // MARK: Private

    private let sorted: [String]
    private let callsignSet: Set<String>
}
