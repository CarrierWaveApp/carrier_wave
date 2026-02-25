import Foundation

// MARK: - CallsignEditDistance

/// Levenshtein edit distance for callsign comparison.
/// Used to detect near-misses between spotted callsigns and logged QSOs.
public enum CallsignEditDistance {
    /// Calculate Levenshtein edit distance between two strings (case-insensitive).
    /// - Returns: Minimum number of single-character insertions, deletions, or substitutions.
    public static func distance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1.uppercased())
        let b = Array(s2.uppercased())
        let m = a.count
        let n = b.count

        if m == 0 {
            return n
        }
        if n == 0 {
            return m
        }

        var previousRow = Array(0 ... n)
        var currentRow = [Int](repeating: 0, count: n + 1)

        for i in 1 ... m {
            currentRow[0] = i
            for j in 1 ... n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                currentRow[j] = min(
                    previousRow[j] + 1,
                    currentRow[j - 1] + 1,
                    previousRow[j - 1] + cost
                )
            }
            swap(&previousRow, &currentRow)
        }

        return previousRow[n]
    }

    /// Find candidates within a given edit distance of a target callsign.
    /// Skips exact matches (distance == 0).
    /// - Returns: Array of (candidate, distance) sorted by distance ascending.
    public static func findNearMatches(
        for callsign: String,
        maxDistance: Int,
        candidates: some Collection<String>
    ) -> [(callsign: String, distance: Int)] {
        let upper = callsign.uppercased()
        var results: [(callsign: String, distance: Int)] = []

        for candidate in candidates {
            let candidateUpper = candidate.uppercased()
            guard candidateUpper != upper else {
                continue
            }

            // Quick length check: if lengths differ by more than maxDistance, skip
            if abs(candidateUpper.count - upper.count) > maxDistance {
                continue
            }

            let dist = distance(upper, candidateUpper)
            if dist > 0, dist <= maxDistance {
                results.append((candidateUpper, dist))
            }
        }

        return results.sorted { $0.distance < $1.distance }
    }
}
