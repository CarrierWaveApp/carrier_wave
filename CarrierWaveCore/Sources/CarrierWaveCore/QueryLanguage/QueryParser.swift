import Foundation

/// Parses tokenized query into an AST
public struct QueryParser {
    // MARK: Lifecycle

    public init(_ tokens: [PositionedToken]) {
        self.tokens = tokens
        currentIndex = 0
    }

    // MARK: Public

    /// Convenience: parse a string directly
    public static func parse(_ input: String) -> Result<ParsedQuery, QueryError> {
        var lexer = QueryLexer(input)
        switch lexer.tokenize() {
        case let .success(tokens):
            var parser = QueryParser(tokens)
            return parser.parse()
        case let .failure(error):
            return .failure(error)
        }
    }

    /// Parse the token stream into a query AST
    public mutating func parse() -> Result<ParsedQuery, QueryError> {
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

    // MARK: Internal

    var tokens: [PositionedToken]
    var currentIndex: Int

    var isAtEnd: Bool {
        currentIndex >= tokens.count || tokens[currentIndex].token == .eof
    }

    func peek() -> PositionedToken? {
        guard currentIndex < tokens.count else {
            return nil
        }
        return tokens[currentIndex]
    }

    func peekToken() -> QueryToken? {
        peek()?.token
    }

    @discardableResult
    mutating func advance() -> PositionedToken? {
        guard !isAtEnd else {
            return nil
        }
        let token = tokens[currentIndex]
        currentIndex += 1
        return token
    }

    mutating func parseExpression() -> Result<QueryExpression, QueryError> {
        parseOr()
    }

    mutating func parseOr() -> Result<QueryExpression, QueryError> {
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

    mutating func parseAnd() -> Result<QueryExpression, QueryError> {
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

    mutating func parseUnary() -> Result<QueryExpression, QueryError> {
        if peekToken() == .not {
            _ = advance()
            switch parsePrimary() {
            case let .success(inner):
                return .success(.not(inner))
            case let .failure(error):
                return .failure(error)
            }
        }

        return parsePrimary()
    }

    mutating func parsePrimary() -> Result<QueryExpression, QueryError> {
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
            return .failure(
                QueryError.unexpectedToken(
                    expected: "search term",
                    got: token.rawText,
                    position: token.position
                )
            )
        }
    }

    mutating func parseGroup() -> Result<QueryExpression, QueryError> {
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
}
