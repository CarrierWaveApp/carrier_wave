// swiftlint:disable cyclomatic_complexity function_body_length identifier_name

import Foundation

// MARK: - QueryLexer

/// Tokenizes a query string into a sequence of tokens
public struct QueryLexer {
    // MARK: Lifecycle

    public init(_ input: String) {
        self.input = input
        currentIndex = input.startIndex
    }

    // MARK: Public

    /// Tokenize the entire input
    public mutating func tokenize() -> Result<[PositionedToken], QueryError> {
        var tokens: [PositionedToken] = []

        while !isAtEnd {
            skipWhitespace()
            if isAtEnd {
                break
            }

            let startOffset = input.distance(from: input.startIndex, to: currentIndex)

            switch peek() {
            case "|":
                advance()
                tokens.append(
                    PositionedToken(
                        token: .or,
                        position: SourcePosition(offset: startOffset, length: 1),
                        rawText: "|"
                    )
                )

            case "-":
                advance()
                tokens.append(
                    PositionedToken(
                        token: .not,
                        position: SourcePosition(offset: startOffset, length: 1),
                        rawText: "-"
                    )
                )

            case "(":
                advance()
                tokens.append(
                    PositionedToken(
                        token: .openParen,
                        position: SourcePosition(offset: startOffset, length: 1),
                        rawText: "("
                    )
                )

            case ")":
                advance()
                tokens.append(
                    PositionedToken(
                        token: .closeParen,
                        position: SourcePosition(offset: startOffset, length: 1),
                        rawText: ")"
                    )
                )

            case ">":
                advance()
                if peek() == "=" {
                    advance()
                    tokens.append(
                        PositionedToken(
                            token: .greaterThanOrEqual,
                            position: SourcePosition(offset: startOffset, length: 2),
                            rawText: ">="
                        )
                    )
                } else {
                    tokens.append(
                        PositionedToken(
                            token: .greaterThan,
                            position: SourcePosition(offset: startOffset, length: 1),
                            rawText: ">"
                        )
                    )
                }

            case "<":
                advance()
                if peek() == "=" {
                    advance()
                    tokens.append(
                        PositionedToken(
                            token: .lessThanOrEqual,
                            position: SourcePosition(offset: startOffset, length: 2),
                            rawText: "<="
                        )
                    )
                } else {
                    tokens.append(
                        PositionedToken(
                            token: .lessThan,
                            position: SourcePosition(offset: startOffset, length: 1),
                            rawText: "<"
                        )
                    )
                }

            case "\"":
                // Quoted string
                switch scanQuotedString() {
                case let .success(value):
                    let length =
                        input.distance(from: input.startIndex, to: currentIndex) - startOffset
                    tokens.append(
                        PositionedToken(
                            token: .value(value),
                            position: SourcePosition(offset: startOffset, length: length),
                            rawText: value
                        )
                    )
                case let .failure(error):
                    return .failure(error)
                }

            default:
                // Word or field:value
                let word = scanWord()
                let length = word.count

                if peek() == ":" {
                    // This is a field qualifier
                    advance() // consume ':'
                    if let field = QueryField.parse(word) {
                        tokens.append(
                            PositionedToken(
                                token: .field(field),
                                position: SourcePosition(offset: startOffset, length: length + 1),
                                rawText: word + ":"
                            )
                        )
                    } else {
                        // Unknown field - suggest similar
                        let suggestion = findSimilarField(word)
                        return .failure(
                            QueryError.unknownField(
                                word,
                                suggestion: suggestion,
                                position: SourcePosition(offset: startOffset, length: length)
                            )
                        )
                    }
                } else if word == ".." {
                    // Range operator
                    tokens.append(
                        PositionedToken(
                            token: .range,
                            position: SourcePosition(offset: startOffset, length: 2),
                            rawText: ".."
                        )
                    )
                } else if word.contains("..") {
                    // Value with embedded range - split it
                    let parts = word.split(
                        separator: ".", maxSplits: 2, omittingEmptySubsequences: false
                    )
                    if parts.count >= 2 {
                        let beforeRange = String(parts[0])
                        let afterRange = word.dropFirst(beforeRange.count + 2)

                        if !beforeRange.isEmpty {
                            tokens.append(
                                PositionedToken(
                                    token: .value(beforeRange),
                                    position: SourcePosition(
                                        offset: startOffset, length: beforeRange.count
                                    ),
                                    rawText: beforeRange
                                )
                            )
                        }

                        tokens.append(
                            PositionedToken(
                                token: .range,
                                position: SourcePosition(
                                    offset: startOffset + beforeRange.count, length: 2
                                ),
                                rawText: ".."
                            )
                        )

                        if !afterRange.isEmpty {
                            tokens.append(
                                PositionedToken(
                                    token: .value(String(afterRange)),
                                    position: SourcePosition(
                                        offset: startOffset + beforeRange.count + 2,
                                        length: afterRange.count
                                    ),
                                    rawText: String(afterRange)
                                )
                            )
                        }
                    }
                } else {
                    // Plain value
                    tokens.append(
                        PositionedToken(
                            token: .value(word),
                            position: SourcePosition(offset: startOffset, length: length),
                            rawText: word
                        )
                    )
                }
            }
        }

        tokens.append(
            PositionedToken(
                token: .eof,
                position: SourcePosition(offset: input.count, length: 0),
                rawText: ""
            )
        )

        return .success(tokens)
    }

    // MARK: Private

    private let input: String
    private var currentIndex: String.Index

    private var isAtEnd: Bool {
        currentIndex >= input.endIndex
    }

    private func peek() -> Character? {
        guard !isAtEnd else {
            return nil
        }
        return input[currentIndex]
    }

    @discardableResult
    private mutating func advance() -> Character? {
        guard !isAtEnd else {
            return nil
        }
        let char = input[currentIndex]
        currentIndex = input.index(after: currentIndex)
        return char
    }

    private mutating func skipWhitespace() {
        while let char = peek(), char.isWhitespace {
            advance()
        }
    }

    private mutating func scanWord() -> String {
        var result = ""
        while let char = peek(), isWordCharacter(char) {
            result.append(char)
            advance()
        }
        return result
    }

    private func isWordCharacter(_ char: Character) -> Bool {
        // Word characters include alphanumeric, wildcards, slashes (for callsigns/SOTA),
        // hyphens (for park refs like K-1234), periods (for ranges and decimals)
        char.isLetter || char.isNumber || char == "*" || char == "/" || char == "-" || char == "."
            || char == "_"
    }

    private mutating func scanQuotedString() -> Result<String, QueryError> {
        let startOffset = input.distance(from: input.startIndex, to: currentIndex)
        advance() // consume opening quote

        var result = ""
        while let char = peek() {
            if char == "\"" {
                advance() // consume closing quote
                return .success(result)
            } else if char == "\\" {
                advance() // consume backslash
                if let escaped = advance() {
                    result.append(escaped)
                }
            } else {
                result.append(char)
                advance()
            }
        }

        // Unterminated string
        return .failure(
            QueryError.unterminatedString(
                position: SourcePosition(offset: startOffset, length: result.count + 1)
            )
        )
    }

    private func findSimilarField(_ input: String) -> String? {
        let lowercased = input.lowercased()
        let allNames = Array(QueryField.aliases.keys)

        // Find closest match using simple edit distance approximation
        var bestMatch: String?
        var bestScore = Int.max

        for name in allNames {
            let score = levenshteinDistance(lowercased, name)
            if score < bestScore, score <= 2 {
                bestScore = score
                bestMatch = name
            }
        }

        return bestMatch
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let m = s1.count
        let n = s2.count

        if m == 0 {
            return n
        }
        if n == 0 {
            return m
        }

        let s1Array = Array(s1)
        let s2Array = Array(s2)

        var previousRow = Array(0 ... n)
        var currentRow = [Int](repeating: 0, count: n + 1)

        for i in 1 ... m {
            currentRow[0] = i

            for j in 1 ... n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                currentRow[j] = min(
                    previousRow[j] + 1, // deletion
                    currentRow[j - 1] + 1, // insertion
                    previousRow[j - 1] + cost // substitution
                )
            }

            swap(&previousRow, &currentRow)
        }

        return previousRow[n]
    }
}

// MARK: - QueryError

/// Query parsing/analysis errors
public enum QueryError: Error, Equatable, Sendable {
    case unknownField(String, suggestion: String?, position: SourcePosition)
    case unterminatedString(position: SourcePosition)
    case unexpectedToken(expected: String, got: String, position: SourcePosition)
    case invalidDateFormat(String, position: SourcePosition)
    case invalidNumberFormat(String, position: SourcePosition)
    case emptyQuery
    case unmatchedParenthesis(position: SourcePosition)

    // MARK: Public

    public var message: String {
        switch self {
        case let .unknownField(field, suggestion, _):
            if let suggestion {
                "Unknown field '\(field)' - did you mean '\(suggestion)'?"
            } else {
                "Unknown field '\(field)'"
            }
        case .unterminatedString:
            "Unterminated quoted string"
        case let .unexpectedToken(expected, got, _):
            "Expected \(expected), got '\(got)'"
        case let .invalidDateFormat(value, _):
            "Invalid date format '\(value)' - use YYYY-MM-DD, 'today', 'yesterday', or '7d'"
        case let .invalidNumberFormat(value, _):
            "Invalid number '\(value)'"
        case .emptyQuery:
            "Empty query"
        case .unmatchedParenthesis:
            "Unmatched parenthesis"
        }
    }

    public var position: SourcePosition {
        switch self {
        case let .unknownField(_, _, position),
             let .unterminatedString(position),
             let .unexpectedToken(_, _, position),
             let .invalidDateFormat(_, position),
             let .invalidNumberFormat(_, position),
             let .unmatchedParenthesis(position):
            position
        case .emptyQuery:
            SourcePosition(offset: 0, length: 0)
        }
    }
}
