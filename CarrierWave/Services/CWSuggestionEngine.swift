// swiftlint:disable function_body_length large_tuple
import CarrierWaveCore
import Combine
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

// MARK: - CWSuggestionEngine

/// Engine for suggesting corrections to commonly misheard CW words.
/// Uses morse code edit distance to find likely intended words.
@MainActor
final class CWSuggestionEngine: ObservableObject {
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
    var suggestionsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "cw.suggestions.enabled") as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "cw.suggestions.enabled")
        }
    }

    /// Maximum edit distance for suggestions (1=strict, 2=moderate, 3=aggressive)
    var maxEditDistance: Int {
        get { UserDefaults.standard.object(forKey: "cw.suggestions.maxDistance") as? Int ?? 2 }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "cw.suggestions.maxDistance")
        }
    }

    /// Suggest prosigns (CQ, DE, K, AR, SK, etc.)
    var suggestProsigns: Bool {
        get { UserDefaults.standard.object(forKey: "cw.suggestions.prosigns") as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "cw.suggestions.prosigns")
        }
    }

    /// Suggest common abbreviations (73, TU, UR, QTH, etc.)
    var suggestAbbreviations: Bool {
        get {
            UserDefaults.standard.object(forKey: "cw.suggestions.abbreviations") as? Bool ?? true
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "cw.suggestions.abbreviations")
        }
    }

    /// Suggest number corrections (less common, off by default)
    var suggestNumbers: Bool {
        get { UserDefaults.standard.object(forKey: "cw.suggestions.numbers") as? Bool ?? false }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "cw.suggestions.numbers")
        }
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
        var bestMatch: (word: String, distance: Int, category: SuggestionCategory)?

        if suggestProsigns {
            if let match = MorseEditDistance.findBestMatch(
                for: upperWord,
                maxDistance: maxEditDistance,
                candidates: Self.prosigns
            ) {
                let distance = MorseEditDistance.wordDistance(upperWord, match)
                if bestMatch == nil || distance < bestMatch!.distance {
                    bestMatch = (match, distance, .prosign)
                }
            }
        }

        if suggestAbbreviations {
            if let match = MorseEditDistance.findBestMatch(
                for: upperWord,
                maxDistance: maxEditDistance,
                candidates: Self.abbreviations
            ) {
                let distance = MorseEditDistance.wordDistance(upperWord, match)
                if bestMatch == nil || distance < bestMatch!.distance {
                    bestMatch = (match, distance, .abbreviation)
                }
            }
        }

        if suggestNumbers {
            if let match = MorseEditDistance.findBestMatch(
                for: upperWord,
                maxDistance: maxEditDistance,
                candidates: Self.numbers
            ) {
                let distance = MorseEditDistance.wordDistance(upperWord, match)
                if bestMatch == nil || distance < bestMatch!.distance {
                    bestMatch = (match, distance, .number)
                }
            }
        }

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
}
