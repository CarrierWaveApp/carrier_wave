import Foundation

// MARK: - SuggestionCategory

/// Category of suggested CW word
public enum SuggestionCategory: String, Equatable, Sendable {
    case prosign
    case abbreviation
    case number
}
