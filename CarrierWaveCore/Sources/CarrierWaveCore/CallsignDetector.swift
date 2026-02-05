import Foundation

// MARK: - TranscriptEntryProtocol

/// Protocol for transcript entries that can be used with CallsignDetector
public protocol TranscriptEntryProtocol {
    var text: String { get }
}

// MARK: - CallsignDetector

/// Detects and extracts callsigns from decoded CW text
public enum CallsignDetector {
    // MARK: Public

    // MARK: - Public API

    /// Extract all callsigns from text
    /// - Parameter text: Decoded CW text
    /// - Returns: Array of unique callsigns found
    public static func extractCallsigns(from text: String) -> [String] {
        guard let regex = callsignRegex else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text.uppercased(), options: [], range: range)

        var callsigns: [String] = []
        var seen = Set<String>()

        for match in matches {
            if let swiftRange = Range(match.range, in: text.uppercased()) {
                let callsign = String(text.uppercased()[swiftRange])
                // Filter out false positives (too short, common words)
                if isValidCallsign(callsign), !seen.contains(callsign) {
                    callsigns.append(callsign)
                    seen.insert(callsign)
                }
            }
        }

        return callsigns
    }

    /// Detect the most likely "other station" callsign from transcript
    /// Uses context clues like CQ, DE, and position to determine
    /// - Parameter entries: Transcript entries conforming to TranscriptEntryProtocol
    /// - Returns: Most likely callsign to log, if found
    public static func detectPrimaryCallsign(
        from entries: [some TranscriptEntryProtocol]
    ) -> DetectedCallsign? {
        let fullText = entries.map(\.text).joined(separator: " ").uppercased()
        let words = fullText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        var candidates: [DetectedCallsign] = []

        for (index, word) in words.enumerated() {
            guard isValidCallsign(word) else {
                continue
            }

            // Check context
            let context = determineContext(for: word, at: index, in: words)
            let candidate = DetectedCallsign(callsign: word, context: context)
            candidates.append(candidate)
        }

        // Prioritize by context: DE identifier > CQ call > response > unknown
        let priority: [DetectedCallsign.CallsignContext] = [
            .deIdentifier, .cqCall, .response, .unknown,
        ]

        for targetContext in priority {
            if let match = candidates.last(where: { $0.context == targetContext }) {
                return match
            }
        }

        return candidates.last
    }

    /// Detect the most likely "other station" callsign from raw text
    /// Uses context clues like CQ, DE, and position to determine
    /// - Parameter text: Raw transcript text
    /// - Returns: Most likely callsign to log, if found
    public static func detectPrimaryCallsign(from text: String) -> DetectedCallsign? {
        let fullText = text.uppercased()
        let words = fullText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        var candidates: [DetectedCallsign] = []

        for (index, word) in words.enumerated() {
            guard isValidCallsign(word) else {
                continue
            }

            let context = determineContext(for: word, at: index, in: words)
            let candidate = DetectedCallsign(callsign: word, context: context)
            candidates.append(candidate)
        }

        let priority: [DetectedCallsign.CallsignContext] = [
            .deIdentifier, .cqCall, .response, .unknown,
        ]

        for targetContext in priority {
            if let match = candidates.last(where: { $0.context == targetContext }) {
                return match
            }
        }

        return candidates.last
    }

    /// Parse text into highlighted elements
    /// - Parameter text: Raw decoded CW text
    /// - Returns: Array of text elements with highlighting info
    public static func parseElements(from text: String) -> [CWTextElement] {
        let uppercased = text.uppercased()
        var elements: [CWTextElement] = []
        var currentIndex = uppercased.startIndex

        // Find all callsigns and their ranges
        guard let regex = callsignRegex else {
            return [.text(text)]
        }

        let nsRange = NSRange(uppercased.startIndex..., in: uppercased)
        let matches = regex.matches(in: uppercased, options: [], range: nsRange)

        for match in matches {
            guard let range = Range(match.range, in: uppercased) else {
                continue
            }

            let callsign = String(uppercased[range])
            guard isValidCallsign(callsign) else {
                continue
            }

            // Add text before this callsign
            if currentIndex < range.lowerBound {
                let beforeText = String(uppercased[currentIndex ..< range.lowerBound])
                let beforeElements = parseNonCallsignText(beforeText)
                elements.append(contentsOf: beforeElements)
            }

            // Determine callsign role from surrounding context
            let role = determineRole(for: callsign, in: uppercased, at: range)
            elements.append(.callsign(callsign, role: role))

            currentIndex = range.upperBound
        }

        // Add remaining text
        if currentIndex < uppercased.endIndex {
            let remainingText = String(uppercased[currentIndex...])
            let remainingElements = parseNonCallsignText(remainingText)
            elements.append(contentsOf: remainingElements)
        }

        return elements.isEmpty ? [.text(text)] : elements
    }

    // MARK: Private

    // MARK: - Callsign Pattern

    /// International amateur radio callsign pattern
    /// Format: Prefix (1-3 alphanumeric) + Number + Suffix (1-4 letters)
    /// Examples: W1AW, VK2ABC, JA1XYZ, 9A2AA, 3DA0RS
    private static let callsignPattern = #"[A-Z0-9]{1,3}[0-9][A-Z]{1,4}"#

    /// Signal report pattern (RST format)
    private static let signalReportPattern = #"\b[1-5][1-9][1-9]?\b"#

    /// Common prosigns to identify
    private static let prosigns = Set([
        "CQ", "DE", "K", "KN", "BK", "SK", "AR", "BT", "AS", "R", "TU", "QSL",
    ])

    /// Keywords that precede a name in CW QSOs
    private static let nameKeywords = Set(["NAME", "OP", "OPR"])

    /// Keywords that precede a signal report
    private static let rstKeywords = Set(["UR", "RST", "YR"])

    /// Grid square pattern (e.g., EM74, FN31pr)
    private static let gridPattern = #"\b[A-R]{2}[0-9]{2}([A-X]{2})?\b"#

    /// Power pattern (e.g., 100W, 5W, 1KW)
    private static let powerPattern = #"\b[0-9]+K?W\b"#

    /// Compiled regex for callsigns
    private static let callsignRegex = try? NSRegularExpression(
        pattern: callsignPattern,
        options: [.caseInsensitive]
    )

    /// Compiled regex for signal reports
    private static let rstRegex = try? NSRegularExpression(
        pattern: signalReportPattern,
        options: []
    )

    /// Compiled regex for grid squares
    private static let gridRegex = try? NSRegularExpression(
        pattern: gridPattern,
        options: [.caseInsensitive]
    )

    /// Compiled regex for power
    private static let powerRegex = try? NSRegularExpression(
        pattern: powerPattern,
        options: [.caseInsensitive]
    )

    // MARK: - Private Helpers

    /// Validate that a string is a plausible callsign
    private static func isValidCallsign(_ candidate: String) -> Bool {
        // Must be at least 4 characters (e.g., W1AW)
        guard candidate.count >= 4 else {
            return false
        }

        // Must not be all numbers
        guard candidate.contains(where: \.isLetter) else {
            return false
        }

        // Must contain at least one number
        guard candidate.contains(where: \.isNumber) else {
            return false
        }

        // Filter out common false positives
        let falsePositives = Set(["1ST", "2ND", "3RD", "4TH", "5TH", "73S", "88S", "599S"])
        if falsePositives.contains(candidate) {
            return false
        }

        return true
    }

    /// Determine the context of a callsign based on surrounding words
    private static func determineContext(
        for callsign: String,
        at index: Int,
        in words: [String]
    ) -> DetectedCallsign.CallsignContext {
        // Check if preceded by DE
        if index > 0, words[index - 1] == "DE" {
            return .deIdentifier
        }

        // Check if part of CQ sequence
        if index > 0 {
            let preceding = words[max(0, index - 3) ..< index]
            if preceding.contains("CQ") {
                return .cqCall
            }
        }

        // Check if followed by DE (this is the station being called)
        if index < words.count - 1, words[index + 1] == "DE" {
            return .response
        }

        return .unknown
    }

    /// Determine the role of a callsign based on context
    private static func determineRole(
        for callsign: String,
        in text: String,
        at range: Range<String.Index>
    ) -> CWTextElement.CallsignRole {
        // Check what comes before
        let beforeStart =
            text.index(range.lowerBound, offsetBy: -4, limitedBy: text.startIndex)
                ?? text.startIndex
        let beforeText = String(text[beforeStart ..< range.lowerBound]).trimmingCharacters(
            in: .whitespaces
        )

        if beforeText.hasSuffix("DE") {
            return .callee
        }

        if beforeText.contains("CQ") {
            return .caller
        }

        // Check what comes after
        if range.upperBound < text.endIndex {
            let afterEnd =
                text.index(range.upperBound, offsetBy: 4, limitedBy: text.endIndex) ?? text.endIndex
            let afterText = String(text[range.upperBound ..< afterEnd]).trimmingCharacters(
                in: .whitespaces
            )

            if afterText.hasPrefix("DE") {
                return .caller
            }
        }

        return .unknown
    }

    /// Parse non-callsign text into prosigns, RST, grid, power, name, and plain text
    private static func parseNonCallsignText(_ text: String) -> [CWTextElement] {
        var elements: [CWTextElement] = []
        let words = text.components(separatedBy: .whitespaces)
        var pendingNameKeyword = false

        for (index, word) in words.enumerated() {
            let trimmed = word.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                continue
            }

            if let element = classifyWord(
                trimmed, index: index, words: words,
                pendingNameKeyword: &pendingNameKeyword
            ) {
                appendElement(element, to: &elements)
            }
        }

        return elements
    }

    /// Classify a word into a CWTextElement type
    private static func classifyWord(
        _ word: String, index: Int, words: [String],
        pendingNameKeyword: inout Bool
    ) -> CWTextElement? {
        // Handle name after keyword
        if pendingNameKeyword {
            pendingNameKeyword = false
            if !isLikelyNonName(word) {
                return .name(word)
            }
        }

        // Check for name keyword
        if nameKeywords.contains(word) {
            pendingNameKeyword = true
            return .text(word)
        }

        if prosigns.contains(word) {
            return .prosign(word)
        }
        if rstKeywords.contains(word) {
            return .text(word)
        }
        if isSignalReport(word) {
            return .signalReport(word)
        }
        if isGridSquare(word) {
            return .grid(word)
        }
        if isPowerLevel(word) {
            return .power(word)
        }

        return .text(word)
    }

    /// Append element, merging adjacent text elements
    private static func appendElement(_ element: CWTextElement, to elements: inout [CWTextElement]) {
        if case let .text(newText) = element, case let .text(existing) = elements.last {
            elements.removeLast()
            elements.append(.text(existing + " " + newText))
        } else {
            elements.append(element)
        }
    }

    /// Check if word is likely NOT a name (common QSO abbreviations)
    private static func isLikelyNonName(_ word: String) -> Bool {
        let nonNames = Set(["IS", "ES", "HR", "HW", "FB", "GM", "GA", "GE", "GN", "73", "88", "GL"])
        return nonNames.contains(word) || isSignalReport(word) || prosigns.contains(word)
    }

    /// Check if text is a grid square (e.g., EM74, FN31pr)
    private static func isGridSquare(_ text: String) -> Bool {
        guard let regex = gridRegex else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text.uppercased(), options: [], range: range) != nil
    }

    /// Check if text is a power level (e.g., 100W, 5W, 1KW)
    private static func isPowerLevel(_ text: String) -> Bool {
        guard let regex = powerRegex else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text.uppercased(), options: [], range: range) != nil
    }

    /// Check if text is a signal report (RST format)
    private static func isSignalReport(_ text: String) -> Bool {
        guard text.count == 3 || text.count == 2 else {
            return false
        }
        guard text.allSatisfy(\.isNumber) else {
            return false
        }

        // RST: R=1-5, S=1-9, T=1-9 (optional)
        let chars = Array(text)
        guard let readability = chars[0].wholeNumberValue, readability >= 1, readability <= 5 else {
            return false
        }
        guard let strength = chars[1].wholeNumberValue, strength >= 1, strength <= 9 else {
            return false
        }
        if chars.count == 3 {
            guard let tone = chars[2].wholeNumberValue, tone >= 1, tone <= 9 else {
                return false
            }
        }

        return true
    }
}
