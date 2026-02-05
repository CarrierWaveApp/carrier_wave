// swiftlint:disable identifier_name
import Foundation

// MARK: - MorseEditDistance

/// Computes edit distance between morse code patterns.
/// Used to suggest corrections for commonly misheard CW words.
public enum MorseEditDistance {
    // MARK: - Pattern Distance

    /// Calculate Levenshtein edit distance between two morse patterns.
    /// Each dit (.) and dah (-) is treated as a single character.
    /// - Parameters:
    ///   - pattern1: First morse pattern (e.g., "-.-.--.-")
    ///   - pattern2: Second morse pattern
    /// - Returns: Minimum number of insertions, deletions, or substitutions
    public static func patternDistance(_ pattern1: String, _ pattern2: String) -> Int {
        let s1 = Array(pattern1)
        let s2 = Array(pattern2)
        let m = s1.count
        let n = s2.count

        // Edge cases
        if m == 0 {
            return n
        }
        if n == 0 {
            return m
        }

        // DP table: dp[i][j] = distance between s1[0..<i] and s2[0..<j]
        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        // Base cases
        for i in 0 ... m {
            dp[i][0] = i
        }
        for j in 0 ... n {
            dp[0][j] = j
        }

        // Fill table
        for i in 1 ... m {
            for j in 1 ... n {
                if s1[i - 1] == s2[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] =
                        1
                            + min(
                                dp[i - 1][j], // deletion
                                dp[i][j - 1], // insertion
                                dp[i - 1][j - 1] // substitution
                            )
                }
            }
        }

        return dp[m][n]
    }

    // MARK: - Word Distance

    /// Calculate edit distance between two words via their morse representations.
    /// Converts each word to morse (without inter-character gaps) and computes distance.
    /// - Parameters:
    ///   - word1: First word (e.g., "CQ")
    ///   - word2: Second word (e.g., "CZ")
    /// - Returns: Edit distance, or Int.max if either word can't be encoded
    public static func wordDistance(_ word1: String, _ word2: String) -> Int {
        guard let morse1 = wordToMorse(word1),
              let morse2 = wordToMorse(word2)
        else {
            return Int.max
        }
        return patternDistance(morse1, morse2)
    }

    /// Convert a word to its morse pattern (concatenated, no gaps).
    /// - Parameter word: Word to convert
    /// - Returns: Concatenated morse pattern, or nil if any character can't be encoded
    public static func wordToMorse(_ word: String) -> String? {
        var result = ""
        for char in word.uppercased() {
            guard let pattern = MorseCode.charToMorse[String(char)] else {
                return nil
            }
            result += pattern
        }
        return result
    }

    // MARK: - Similarity Search

    /// Find all words from candidates that are within maxDistance of the target word.
    /// - Parameters:
    ///   - word: Target word to match against
    ///   - maxDistance: Maximum edit distance to include
    ///   - candidates: Set of candidate words to check
    /// - Returns: Array of (word, distance) tuples, sorted by distance ascending
    public static func findSimilar(
        to word: String,
        maxDistance: Int,
        candidates: Set<String>
    ) -> [(word: String, distance: Int)] {
        // Skip if word is already in candidates (exact match)
        let upperWord = word.uppercased()
        if candidates.contains(upperWord) {
            return []
        }

        var results: [(word: String, distance: Int)] = []

        for candidate in candidates {
            let distance = wordDistance(upperWord, candidate)
            if distance <= maxDistance, distance > 0 {
                results.append((candidate, distance))
            }
        }

        return results.sorted { $0.distance < $1.distance }
    }

    /// Find the best suggestion for a word, if any exists within maxDistance.
    /// - Parameters:
    ///   - word: Target word
    ///   - maxDistance: Maximum edit distance
    ///   - candidates: Set of candidate words
    /// - Returns: Best matching word, or nil if none within distance
    public static func findBestMatch(
        for word: String,
        maxDistance: Int,
        candidates: Set<String>
    ) -> String? {
        let matches = findSimilar(to: word, maxDistance: maxDistance, candidates: candidates)
        return matches.first?.word
    }
}
