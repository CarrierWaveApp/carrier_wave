import Foundation

/// Parses tokenized query into an AST
struct QueryParser {
    // MARK: Lifecycle

    init(_ tokens: [PositionedToken]) {
        self.tokens = tokens
        self.currentIndex = 0
    }

    // MARK: Internal

    /// Parse the token stream into a query AST
    mutating func parse() -> Result<ParsedQuery, QueryError> {
        if tokens.isEmpty || (tokens.count == 1 && tokens[0].token == .eof) {
            return .success(ParsedQuery(expression: .empty, sourceText: ""))
        }

        switch parseExpression() {
        case let .success(expr):
            let sourceText = tokens.dropLast().map(\.rawText).joined(separator: " ")
            return .success(ParsedQuery(expression: expr.flattened, sourceText: sourceText))
        case let .failure(error):
            return .failure(error)
        }
    }

    /// Convenience: parse a string directly
    static func parse(_ input: String) -> Result<ParsedQuery, QueryError> {
        var lexer = QueryLexer(input)
        switch lexer.tokenize() {
        case let .success(tokens):
            var parser = QueryParser(tokens)
            return parser.parse()
        case let .failure(error):
            return .failure(error)
        }
    }

    // MARK: Private

    private let tokens: [PositionedToken]
    private var currentIndex: Int

    private var isAtEnd: Bool {
        currentIndex >= tokens.count || tokens[currentIndex].token == .eof
    }

    private func peek() -> PositionedToken? {
        guard currentIndex < tokens.count else {
            return nil
        }
        return tokens[currentIndex]
    }

    private func peekToken() -> QueryToken? {
        peek()?.token
    }

    @discardableResult
    private mutating func advance() -> PositionedToken? {
        guard !isAtEnd else {
            return nil
        }
        let token = tokens[currentIndex]
        currentIndex += 1
        return token
    }

    private mutating func parseExpression() -> Result<QueryExpression, QueryError> {
        parseOr()
    }

    private mutating func parseOr() -> Result<QueryExpression, QueryError> {
        var terms: [QueryExpression] = []

        switch parseAnd() {
        case let .success(first):
            terms.append(first)
        case let .failure(error):
            return .failure(error)
        }

        while peekToken() == .or {
            advance() // consume '|'
            switch parseAnd() {
            case let .success(next):
                terms.append(next)
            case let .failure(error):
                return .failure(error)
            }
        }

        if terms.count == 1 {
            return .success(terms[0])
        }
        return .success(.or(terms))
    }

    private mutating func parseAnd() -> Result<QueryExpression, QueryError> {
        var terms: [QueryExpression] = []

        while !isAtEnd, peekToken() != .or, peekToken() != .closeParen {
            switch parseUnary() {
            case let .success(term):
                terms.append(term)
            case let .failure(error):
                return .failure(error)
            }
        }

        if terms.isEmpty {
            return .success(.empty)
        }
        if terms.count == 1 {
            return .success(terms[0])
        }
        return .success(.and(terms))
    }

    private mutating func parseUnary() -> Result<QueryExpression, QueryError> {
        if peekToken() == .not {
            let notToken = advance()!
            switch parsePrimary() {
            case let .success(inner):
                return .success(.not(inner))
            case let .failure(error):
                return .failure(error)
            }
        }

        return parsePrimary()
    }

    private mutating func parsePrimary() -> Result<QueryExpression, QueryError> {
        guard let token = peek() else {
            return .success(.empty)
        }

        switch token.token {
        case .openParen:
            return parseGroup()

        case let .field(field):
            return parseFieldTerm(field, position: token.position)

        case let .value(value):
            advance()
            return parseBareTerm(value, position: token.position)

        case .eof:
            return .success(.empty)

        default:
            return .failure(QueryError.unexpectedToken(
                expected: "search term",
                got: token.rawText,
                position: token.position
            ))
        }
    }

    private mutating func parseGroup() -> Result<QueryExpression, QueryError> {
        let openParen = advance()! // consume '('

        switch parseExpression() {
        case let .success(inner):
            if peekToken() == .closeParen {
                advance() // consume ')'
                return .success(inner)
            } else {
                return .failure(QueryError.unmatchedParenthesis(position: openParen.position))
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    private mutating func parseFieldTerm(_ field: QueryField, position: SourcePosition) -> Result<QueryExpression, QueryError> {
        advance() // consume field token

        // Check for comparison operator
        var comparison: QueryToken?
        if let token = peekToken() {
            switch token {
            case .greaterThan, .lessThan, .greaterThanOrEqual, .lessThanOrEqual:
                comparison = token
                advance()
            default:
                break
            }
        }

        // Get value
        guard let valueToken = peek(), case let .value(value) = valueToken.token else {
            return .failure(QueryError.unexpectedToken(
                expected: "value",
                got: peek()?.rawText ?? "end of input",
                position: peek()?.position ?? position
            ))
        }
        advance()

        // Check for range
        var endValue: String?
        if peekToken() == .range {
            advance() // consume '..'
            if let endToken = peek(), case let .value(end) = endToken.token {
                advance()
                endValue = end
            }
        }

        // Build condition based on field type and operators
        let conditionResult = buildCondition(
            field: field,
            value: value,
            endValue: endValue,
            comparison: comparison,
            position: valueToken.position
        )

        switch conditionResult {
        case let .success(condition):
            return .success(.term(QueryTerm(field: field, condition: condition, position: position)))
        case let .failure(error):
            return .failure(error)
        }
    }

    private mutating func parseBareTerm(_ value: String, position: SourcePosition) -> Result<QueryExpression, QueryError> {
        // Check for range
        var endValue: String?
        if peekToken() == .range {
            advance()
            if let endToken = peek(), case let .value(end) = endToken.token {
                advance()
                endValue = end
            }
        }

        // Determine what type of bare term this is
        let condition = buildBareTermCondition(value: value, endValue: endValue)
        return .success(.term(QueryTerm(field: nil, condition: condition, position: position)))
    }

    private func buildCondition(
        field: QueryField,
        value: String,
        endValue: String?,
        comparison: QueryToken?,
        position: SourcePosition
    ) -> Result<TermCondition, QueryError> {
        // Handle date fields
        if field == .date || field == .after || field == .before {
            return buildDateCondition(field: field, value: value, endValue: endValue, position: position)
        }

        // Handle numeric fields with comparisons
        if field == .frequency || field == .power || field == .dxcc {
            return buildNumericCondition(value: value, endValue: endValue, comparison: comparison, position: position)
        }

        // Handle boolean/service fields
        if field == .confirmed || field == .synced || field == .pending {
            return buildStatusCondition(field: field, value: value, position: position)
        }

        // Handle source field
        if field == .source {
            return buildSourceCondition(value: value, position: position)
        }

        // Handle string range
        if let endValue {
            return .success(.range(value, endValue))
        }

        // Handle wildcards
        if value.contains("*") {
            if value.hasPrefix("*") && value.hasSuffix("*") {
                let inner = String(value.dropFirst().dropLast())
                return .success(.contains(inner))
            } else if value.hasPrefix("*") {
                return .success(.suffix(String(value.dropFirst())))
            } else if value.hasSuffix("*") {
                return .success(.prefix(String(value.dropLast())))
            }
        }

        // Default to equals match
        return .success(.equals(value))
    }

    private func buildDateCondition(
        field: QueryField,
        value: String,
        endValue: String?,
        position: SourcePosition
    ) -> Result<TermCondition, QueryError> {
        guard let dateMatch = parseDateValue(value) else {
            return .failure(QueryError.invalidDateFormat(value, position: position))
        }

        if let endValue {
            guard let endMatch = parseDateValue(endValue) else {
                return .failure(QueryError.invalidDateFormat(endValue, position: position))
            }
            return .success(.dateRange(dateMatch, endMatch))
        }

        switch field {
        case .after:
            return .success(.dateAfter(dateMatch))
        case .before:
            return .success(.dateBefore(dateMatch))
        default:
            return .success(.dateEquals(dateMatch))
        }
    }

    private func buildNumericCondition(
        value: String,
        endValue: String?,
        comparison: QueryToken?,
        position: SourcePosition
    ) -> Result<TermCondition, QueryError> {
        guard let number = Double(value) else {
            return .failure(QueryError.invalidNumberFormat(value, position: position))
        }

        if let endValue {
            guard let endNumber = Double(endValue) else {
                return .failure(QueryError.invalidNumberFormat(endValue, position: position))
            }
            return .success(.numericRange(number, endNumber))
        }

        if let comparison {
            switch comparison {
            case .greaterThan:
                return .success(.greaterThan(number))
            case .lessThan:
                return .success(.lessThan(number))
            case .greaterThanOrEqual:
                return .success(.greaterThanOrEqual(number))
            case .lessThanOrEqual:
                return .success(.lessThanOrEqual(number))
            default:
                break
            }
        }

        // Exact match with small tolerance for frequencies
        return .success(.numericRange(number - 0.0005, number + 0.0005))
    }

    private func buildStatusCondition(
        field: QueryField,
        value: String,
        position: SourcePosition
    ) -> Result<TermCondition, QueryError> {
        let lowered = value.lowercased()

        // Boolean values
        if lowered == "yes" || lowered == "true" || lowered == "1" {
            return .success(.boolean(true))
        }
        if lowered == "no" || lowered == "false" || lowered == "0" {
            return .success(.boolean(false))
        }

        // Service type
        if let service = ServiceType(rawValue: lowered) {
            return .success(.service(service))
        }

        // Try common aliases
        switch lowered {
        case "lotw", "logbookoftheworld":
            return .success(.service(.lotw))
        case "qrz":
            return .success(.service(.qrz))
        case "pota":
            return .success(.service(.pota))
        case "lofi", "ham2k":
            return .success(.service(.lofi))
        case "hamrs":
            return .success(.service(.hamrs))
        default:
            return .failure(QueryError.unexpectedToken(
                expected: "yes/no or service name (lotw, qrz, pota, lofi, hamrs)",
                got: value,
                position: position
            ))
        }
    }

    private func buildSourceCondition(value: String, position: SourcePosition) -> Result<TermCondition, QueryError> {
        let lowered = value.lowercased()

        // Map to service type for source filtering
        switch lowered {
        case "lotw", "logbookoftheworld":
            return .success(.service(.lotw))
        case "qrz":
            return .success(.service(.qrz))
        case "pota":
            return .success(.service(.pota))
        case "lofi", "ham2k":
            return .success(.service(.lofi))
        case "hamrs":
            return .success(.service(.hamrs))
        case "manual", "local":
            return .success(.equals("manual"))
        default:
            return .failure(QueryError.unexpectedToken(
                expected: "source name (lotw, qrz, pota, lofi, hamrs, manual)",
                got: value,
                position: position
            ))
        }
    }

    private func buildBareTermCondition(value: String, endValue: String?) -> TermCondition {
        if let endValue {
            return .range(value, endValue)
        }

        // Handle wildcards
        if value.contains("*") {
            if value.hasPrefix("*") && value.hasSuffix("*") {
                return .contains(String(value.dropFirst().dropLast()))
            } else if value.hasPrefix("*") {
                return .suffix(String(value.dropFirst()))
            } else if value.hasSuffix("*") {
                return .prefix(String(value.dropLast()))
            }
        }

        // For bare terms, use contains to match across callsign/park/sota
        return .contains(value)
    }

    private func parseDateValue(_ value: String) -> DateMatch? {
        let lowered = value.lowercased()

        // Special keywords
        if lowered == "today" {
            return .today
        }
        if lowered == "yesterday" {
            return .yesterday
        }

        // Relative dates (e.g., "7d", "30d", "3m")
        if lowered.hasSuffix("d"), let days = Int(lowered.dropLast()) {
            return .relative(days: days)
        }
        if lowered.hasSuffix("m"), let months = Int(lowered.dropLast()) {
            return .relative(days: months * 30)
        }

        // Year only (e.g., "2024")
        if value.count == 4, let year = Int(value) {
            return .year(year)
        }

        // Year-month (e.g., "2024-01")
        if value.count == 7, value.contains("-") {
            let parts = value.split(separator: "-")
            if parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) {
                return .yearMonth(year, month)
            }
        }

        // Full date (e.g., "2024-01-15")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: value) {
            return .specific(date)
        }

        return nil
    }
}
