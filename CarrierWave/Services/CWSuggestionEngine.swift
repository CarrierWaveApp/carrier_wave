import CarrierWaveCore
import Foundation

// MARK: - WordSuggestion

/// A suggested correction for a decoded CW word
struct WordSuggestion: Identifiable, Equatable {
    let id = UUID()
    let originalWord: String
    let suggestedWord: String
    let editDistance: Int
    let category: SuggestionCategory

    static func == (lhs: WordSuggestion, rhs: WordSuggestion) -> Bool {
        lhs.originalWord == rhs.originalWord && lhs.suggestedWord == rhs.suggestedWord
            && lhs.editDistance == rhs.editDistance && lhs.category == rhs.category
    }
}

// MARK: - SuggestionMatch

/// A candidate match from dictionary lookup before building a full WordSuggestion.
private struct SuggestionMatch {
    let word: String
    let distance: Int
    let category: SuggestionCategory
}

// MARK: - CategorySearch

/// A category to search for suggestions, pairing enabled state with candidates.
private struct CategorySearch {
    let enabled: Bool
    let candidates: Set<String>
    let category: SuggestionCategory
}

// MARK: - CWSuggestionEngine

/// Engine for suggesting corrections to commonly misheard CW words.
/// Uses morse code edit distance to find likely intended words.
@MainActor
@Observable
final class CWSuggestionEngine {
    // MARK: Internal

    // MARK: - Word Dictionaries

    /// Common prosigns in CW QSOs
    static let prosigns: Set<String> = [
        "CQ", "DE", "K", "KN", "AR", "SK", "BK", "BT", "AS", "R",
    ]

    /// Common abbreviations in CW QSOs
    static let abbreviations: Set<String> = [
        // Greetings and sign-offs
        "GM", "GA", "GE", "GN", "73", "88", "TU", "TNX",
        // Common exchanges
        "UR", "RST", "NAME", "QTH", "RIG", "ANT", "WX", "PWR",
        "HR", "HW", "CPY", "FB", "VY",
        // Operators
        "OM", "YL", "XYL", "OP",
        // Q-codes
        "QSL", "QRZ", "QRS", "QRQ", "QRM", "QRN", "QSB", "QSY",
        // Other common
        "AGN", "CFM", "CUL", "FER", "NR", "PSE", "RPT", "SIG", "ES",
    ]

    /// Numbers (0-9)
    static let numbers: Set<String> = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    ]

    // MARK: - Settings

    /// Whether suggestions are enabled at all
    var suggestionsEnabled: Bool = UserDefaults.standard.object(
        forKey: "cw.suggestions.enabled"
    ) as? Bool ?? true {
        didSet { UserDefaults.standard.set(suggestionsEnabled, forKey: "cw.suggestions.enabled") }
    }

    /// Maximum edit distance for suggestions (1=strict, 2=moderate, 3=aggressive)
    var maxEditDistance: Int = UserDefaults.standard.object(
        forKey: "cw.suggestions.maxDistance"
    ) as? Int ?? 2 {
        didSet { UserDefaults.standard.set(maxEditDistance, forKey: "cw.suggestions.maxDistance") }
    }

    /// Suggest prosigns (CQ, DE, K, AR, SK, etc.)
    var suggestProsigns: Bool = UserDefaults.standard.object(
        forKey: "cw.suggestions.prosigns"
    ) as? Bool ?? true {
        didSet { UserDefaults.standard.set(suggestProsigns, forKey: "cw.suggestions.prosigns") }
    }

    /// Suggest common abbreviations (73, TU, UR, QTH, etc.)
    var suggestAbbreviations: Bool = UserDefaults.standard.object(
        forKey: "cw.suggestions.abbreviations"
    ) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(suggestAbbreviations, forKey: "cw.suggestions.abbreviations")
        }
    }

    /// Suggest number corrections (less common, off by default)
    var suggestNumbers: Bool = UserDefaults.standard.object(
        forKey: "cw.suggestions.numbers"
    ) as? Bool ?? false {
        didSet { UserDefaults.standard.set(suggestNumbers, forKey: "cw.suggestions.numbers") }
    }

    // MARK: - API

    /// Get the active candidate set based on current settings
    var activeCandidates: Set<String> {
        var candidates = Set<String>()
        if suggestProsigns {
            candidates.formUnion(Self.prosigns)
        }
        if suggestAbbreviations {
            candidates.formUnion(Self.abbreviations)
        }
        if suggestNumbers {
            candidates.formUnion(Self.numbers)
        }
        return candidates
    }

    /// Suggest a correction for a single word.
    /// - Parameter word: Decoded word to check
    /// - Returns: Suggestion if a likely correction exists, nil otherwise
    func suggestCorrection(for word: String) -> WordSuggestion? {
        guard suggestionsEnabled else {
            return nil
        }

        let upperWord = word.uppercased()

        // Skip if word is already a known word
        if activeCandidates.contains(upperWord) {
            return nil
        }

        // Skip very short words (single letters are often intentional)
        guard word.count >= 1 else {
            return nil
        }

        // Find best match across enabled categories
        let bestMatch = findBestCategoryMatch(for: upperWord)

        guard let match = bestMatch else {
            return nil
        }

        return WordSuggestion(
            originalWord: upperWord,
            suggestedWord: match.word,
            editDistance: match.distance,
            category: match.category
        )
    }

    /// Suggest corrections for all words in text.
    /// - Parameter text: Decoded CW text (space-separated words)
    /// - Returns: Array of suggestions for words that have likely corrections
    func suggestCorrections(for text: String) -> [WordSuggestion] {
        guard suggestionsEnabled else {
            return []
        }

        let words = text.uppercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        return words.compactMap { suggestCorrection(for: $0) }
    }

    // MARK: Private

    /// Search all enabled categories for the best morse edit distance match
    private func findBestCategoryMatch(for upperWord: String) -> SuggestionMatch? {
        var bestMatch: SuggestionMatch?

        let categoriesToSearch: [CategorySearch] = [
            CategorySearch(enabled: suggestProsigns, candidates: Self.prosigns, category: .prosign),
            CategorySearch(enabled: suggestAbbreviations, candidates: Self.abbreviations, category: .abbreviation),
            CategorySearch(enabled: suggestNumbers, candidates: Self.numbers, category: .number),
        ]

        for search in categoriesToSearch {
            guard search.enabled else {
                continue
            }
            if let match = findMatchInCategory(
                for: upperWord, candidates: search.candidates,
                category: search.category, currentBest: bestMatch
            ) {
                bestMatch = match
            }
        }

        return bestMatch
    }

    /// Find a match in a single category, returning it only if better than currentBest
    private func findMatchInCategory(
        for word: String,
        candidates: Set<String>,
        category: SuggestionCategory,
        currentBest: SuggestionMatch?
    ) -> SuggestionMatch? {
        guard let match = MorseEditDistance.findBestMatch(
            for: word, maxDistance: maxEditDistance, candidates: candidates
        ) else {
            return nil
        }

        let distance = MorseEditDistance.wordDistance(word, match)
        if currentBest == nil || distance < currentBest!.distance {
            return SuggestionMatch(word: match, distance: distance, category: category)
        }
        return nil
    }
}
