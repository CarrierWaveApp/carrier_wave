import CarrierWaveData
import Foundation

// MARK: - ProgramCrossReferenceService

/// Suggests matching references across activation programs (POTA, WWFF, SOTA).
///
/// Two matching strategies:
/// - **Number match**: Extract numeric part from a POTA reference (e.g., "1234" from "US-1234"),
///   try WWFF lookup as "KFF-1234". Works for US parks where POTA and WWFF share numbering.
/// - **Name match**: Search other caches by the park/summit name using word overlap scoring.
actor ProgramCrossReferenceService {
    // MARK: Internal

    /// A suggested cross-reference match from another program
    struct Suggestion: Sendable, Identifiable {
        enum MatchType: Sendable {
            case numberMatch
            case nameMatch(score: Double)
        }

        let id = UUID()
        let program: String // "pota", "wwff", or "sota"
        let reference: String // e.g., "KFF-1234" or "W4C/CM-001"
        let name: String // e.g., "Yellowstone National Park"
        let matchType: MatchType
    }

    /// Find matching references in other programs for a given reference.
    /// - Parameters:
    ///   - reference: The reference to match (e.g., "US-1234", "KFF-1234", "W4C/CM-001")
    ///   - program: The source program slug ("pota", "wwff", or "sota")
    ///   - activePrograms: Programs already selected (suggestions skip these)
    /// - Returns: Suggestions for other programs, best matches first.
    func findMatches(
        for reference: String,
        program: String,
        activePrograms: Set<String>
    ) async -> [Suggestion] {
        let trimmed = reference.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else {
            return []
        }

        var results: [Suggestion] = []

        switch program {
        case "pota":
            if !activePrograms.contains("wwff") {
                results += await potaToWWFF(potaRef: trimmed)
            }
            if !activePrograms.contains("sota") {
                results += await nameMatchToSOTA(name: potaName(trimmed))
            }
        case "wwff":
            if !activePrograms.contains("pota") {
                results += await wwffToPOTA(wwffRef: trimmed)
            }
            if !activePrograms.contains("sota") {
                results += await nameMatchToSOTA(name: wwffName(trimmed))
            }
        case "sota":
            let name = sotaName(trimmed)
            if !activePrograms.contains("pota") {
                results += await nameMatchToPOTA(name: name)
            }
            if !activePrograms.contains("wwff") {
                results += await nameMatchToWWFF(name: name)
            }
        default:
            break
        }

        return results
    }

    // MARK: Private

    // MARK: - Number Matching

    /// POTA US-XXXX → WWFF KFF-XXXX (number match)
    private func potaToWWFF(potaRef: String) async -> [Suggestion] {
        // Extract numeric part: "US-1234" → "1234"
        guard let numeric = extractNumeric(from: potaRef) else {
            return []
        }
        let wwffCode = "KFF-\(numeric)"
        guard let ref = await WWFFReferencesCache.shared.reference(for: wwffCode) else {
            return []
        }
        return [Suggestion(
            program: "wwff",
            reference: ref.reference,
            name: ref.name,
            matchType: .numberMatch
        )]
    }

    /// WWFF KFF-XXXX → POTA US-XXXX (number match)
    private func wwffToPOTA(wwffRef: String) async -> [Suggestion] {
        guard let numeric = extractNumeric(from: wwffRef) else {
            return []
        }
        let potaCode = "US-\(numeric)"
        guard let park = await POTAParksCache.shared.park(for: potaCode) else {
            return []
        }
        return [Suggestion(
            program: "pota",
            reference: park.reference,
            name: park.name,
            matchType: .numberMatch
        )]
    }

    // MARK: - Name Matching

    private func nameMatchToPOTA(name: String?) async -> [Suggestion] {
        guard let name, !name.isEmpty else {
            return []
        }
        let results = POTAParksCache.shared.searchByName(name, limit: 5)
        let scored = results.compactMap { park in
            let score = wordOverlapScore(query: name, candidate: park.name)
            guard score >= 0.5 else {
                return nil as Suggestion?
            }
            return Suggestion(
                program: "pota",
                reference: park.reference,
                name: park.name,
                matchType: .nameMatch(score: score)
            )
        }
        .sorted { lhsScore($0) > lhsScore($1) }
        return Array(scored.prefix(1))
    }

    private func nameMatchToWWFF(name: String?) async -> [Suggestion] {
        guard let name, !name.isEmpty else {
            return []
        }
        let results = WWFFReferencesCache.shared.searchByName(name, limit: 5)
        let scored = results.compactMap { ref in
            let score = wordOverlapScore(query: name, candidate: ref.name)
            guard score >= 0.5 else {
                return nil as Suggestion?
            }
            return Suggestion(
                program: "wwff",
                reference: ref.reference,
                name: ref.name,
                matchType: .nameMatch(score: score)
            )
        }
        .sorted { lhsScore($0) > lhsScore($1) }
        return Array(scored.prefix(1))
    }

    private func nameMatchToSOTA(name: String?) async -> [Suggestion] {
        guard let name, !name.isEmpty else {
            return []
        }
        let results = SOTASummitsCache.shared.searchByName(name, limit: 5)
        let scored = results.compactMap { summit in
            let score = wordOverlapScore(query: name, candidate: summit.name)
            guard score >= 0.5 else {
                return nil as Suggestion?
            }
            return Suggestion(
                program: "sota",
                reference: summit.code,
                name: summit.name,
                matchType: .nameMatch(score: score)
            )
        }
        .sorted { lhsScore($0) > lhsScore($1) }
        return Array(scored.prefix(1))
    }

    // MARK: - Helpers

    private func extractNumeric(from reference: String) -> String? {
        // "US-1234" → "1234", "KFF-1234" → "1234"
        guard let dashIndex = reference.lastIndex(of: "-") else {
            return nil
        }
        let numeric = String(reference[reference.index(after: dashIndex)...])
        guard !numeric.isEmpty, numeric.allSatisfy(\.isNumber) else {
            return nil
        }
        return numeric
    }

    private func potaName(_ ref: String) -> String? {
        POTAParksCache.shared.nameSync(for: ref)
    }

    private func wwffName(_ ref: String) -> String? {
        WWFFReferencesCache.shared.nameSync(for: ref)
    }

    private func sotaName(_ ref: String) -> String? {
        SOTASummitsCache.shared.nameSync(for: ref)
    }

    /// Word overlap score between a query and candidate string (0.0 to 1.0).
    /// Measures fraction of query words found in candidate words.
    private func wordOverlapScore(query: String, candidate: String) -> Double {
        let stopWords: Set<String> = [
            "the", "of", "and", "in", "at", "a", "an", "to", "for",
            "national", "state", "park", "forest", "area", "recreation",
        ]
        let queryWords = significantWords(query, stopWords: stopWords)
        let candidateWords = significantWords(candidate, stopWords: stopWords)
        guard !queryWords.isEmpty else {
            return 0
        }
        let matches = queryWords.filter { candidateWords.contains($0) }
        return Double(matches.count) / Double(queryWords.count)
    }

    private func significantWords(
        _ text: String,
        stopWords: Set<String>
    ) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 1 }
        return Set(words).subtracting(stopWords)
    }

    private func lhsScore(_ suggestion: Suggestion) -> Double {
        switch suggestion.matchType {
        case .numberMatch: 1.0
        case let .nameMatch(score): score
        }
    }
}
