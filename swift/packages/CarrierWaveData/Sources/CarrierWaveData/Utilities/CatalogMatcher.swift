import Foundation

// MARK: - CatalogMatcher

/// Fuzzy-matches user-entered equipment names against the canonical catalog.
///
/// Uses normalized string comparison with alias support. When a user types
/// "mtr4b" or "mountain topper", this finds the canonical "Mountain Topper MTR-4B"
/// entry with a confidence score.
public enum CatalogMatcher {
    // MARK: Public

    /// Search the catalog for entries matching a user query.
    /// Returns results sorted by confidence (highest first).
    ///
    /// - Parameters:
    ///   - query: User-entered equipment name (e.g., "kx2", "mtr-4b")
    ///   - catalog: Available catalog entries to search
    ///   - category: Optional category filter
    ///   - limit: Maximum number of results (default 5)
    /// - Returns: Matched entries with confidence scores.
    public static func search(
        query: String,
        in catalog: [CatalogEntry],
        category: EquipmentCategory? = nil,
        limit: Int = 5
    ) -> [CatalogSearchResult] {
        let normalized = normalize(query)
        guard !normalized.isEmpty else {
            return []
        }

        var filtered = catalog
        if let category {
            filtered = filtered.filter { $0.category == category }
        }

        let scored: [(CatalogEntry, Double)] = filtered.compactMap { entry in
            let score = matchScore(query: normalized, entry: entry)
            guard score > 0.3 else {
                return nil
            }
            return (entry, score)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { CatalogSearchResult(entry: $0.0, confidence: $0.1, originalInput: query) }
    }

    /// Find the single best match above a confidence threshold.
    public static func bestMatch(
        for query: String,
        in catalog: [CatalogEntry],
        category: EquipmentCategory? = nil,
        threshold: Double = 0.6
    ) -> CatalogSearchResult? {
        let results = search(query: query, in: catalog, category: category, limit: 1)
        guard let best = results.first, best.confidence >= threshold else {
            return nil
        }
        return best
    }

    // MARK: Private

    private static func normalize(_ input: String) -> String {
        input
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchScore(query: String, entry: CatalogEntry) -> Double {
        // Phase 1: Exact matches (case-insensitive, unnormalized)
        let queryLower = query.lowercased()
        if entry.name.lowercased() == queryLower
            || entry.fullName.lowercased() == queryLower
        {
            return 1.0
        }
        if entry.aliases.contains(where: { $0.lowercased() == queryLower }) {
            return 1.0
        }

        // Phase 2: Word-level comparison
        // Split into tokens and compare — "Elecraft K3" vs "Elecraft KX3"
        // should score lower than "Elecraft K3" vs "Elecraft K3"
        let queryWords = tokenize(query)
        let wordScore = wordMatchScore(
            queryWords: queryWords,
            targetWords: tokenize(entry.fullName)
        )
        if wordScore >= 0.95 {
            return wordScore
        }

        // Phase 3: Fuzzy matching on normalized strings
        var bestScore = wordScore

        let normalizedQuery = normalize(query)

        let nameScore = stringScore(
            query: normalizedQuery, target: normalize(entry.name)
        )
        bestScore = max(bestScore, nameScore)

        let fullScore = stringScore(
            query: normalizedQuery, target: normalize(entry.fullName)
        )
        bestScore = max(bestScore, fullScore)

        let mfgScore = stringScore(
            query: normalizedQuery, target: normalize(entry.manufacturer)
        )
        if mfgScore > 0.8 {
            bestScore = max(bestScore, mfgScore * 0.7)
        }

        for alias in entry.aliases {
            let aliasScore = stringScore(
                query: normalizedQuery, target: normalize(alias)
            )
            bestScore = max(bestScore, aliasScore)
        }

        let slugScore = stringScore(
            query: normalizedQuery, target: normalize(entry.id)
        )
        bestScore = max(bestScore, slugScore * 0.9)

        return bestScore
    }

    /// Score how well a query matches a target string.
    /// Returns 0.0–1.0 where 1.0 is exact match.
    private static func stringScore(query: String, target: String) -> Double {
        if query == target {
            return 1.0
        }

        // Substring containment — penalize based on length difference
        // "k3" in "kx3" should score lower than "k3" in "k3s"
        if target.contains(query) {
            let lenRatio = Double(query.count) / Double(target.count)
            return 0.7 + (0.25 * lenRatio)
        }
        if query.contains(target) {
            let lenRatio = Double(target.count) / Double(query.count)
            return 0.6 + (0.2 * lenRatio)
        }

        // Levenshtein-based similarity for typo tolerance
        let distance = editDistance(query, target)
        let maxLen = max(query.count, target.count)
        guard maxLen > 0 else {
            return 0.0
        }
        let similarity = 1.0 - (Double(distance) / Double(maxLen))
        return max(0.0, similarity)
    }

    /// Split a string into lowercase tokens for word-level matching.
    private static func tokenize(_ input: String) -> [String] {
        input.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Score based on word-level matching. Each query word must match
    /// a target word exactly or very closely. Returns average of per-word scores.
    private static func wordMatchScore(
        queryWords: [String], targetWords: [String]
    ) -> Double {
        guard !queryWords.isEmpty, !targetWords.isEmpty else {
            return 0.0
        }

        var totalScore = 0.0
        for qw in queryWords {
            var bestWordScore = 0.0
            for tw in targetWords {
                if qw == tw {
                    bestWordScore = 1.0
                    break
                }
                // Only allow close matches for longer tokens (3+ chars)
                if qw.count >= 3, tw.count >= 3 {
                    let dist = editDistance(qw, tw)
                    let maxLen = max(qw.count, tw.count)
                    let sim = 1.0 - (Double(dist) / Double(maxLen))
                    // Require high similarity for word-level match
                    if sim >= 0.75 {
                        bestWordScore = max(bestWordScore, sim * 0.9)
                    }
                }
            }
            totalScore += bestWordScore
        }

        return totalScore / Double(queryWords.count)
    }

    /// Levenshtein edit distance between two strings.
    private static func editDistance(_ source: String, _ target: String) -> Int {
        let srcChars = Array(source)
        let tgtChars = Array(target)
        let srcLen = srcChars.count
        let tgtLen = tgtChars.count

        if srcLen == 0 {
            return tgtLen
        }
        if tgtLen == 0 {
            return srcLen
        }

        var prev = Array(0 ... tgtLen)
        var curr = Array(repeating: 0, count: tgtLen + 1)

        for si in 1 ... srcLen {
            curr[0] = si
            for ti in 1 ... tgtLen {
                let cost = srcChars[si - 1] == tgtChars[ti - 1] ? 0 : 1
                curr[ti] = min(
                    prev[ti] + 1,
                    curr[ti - 1] + 1,
                    prev[ti - 1] + cost
                )
            }
            swap(&prev, &curr)
        }

        return prev[tgtLen]
    }
}
