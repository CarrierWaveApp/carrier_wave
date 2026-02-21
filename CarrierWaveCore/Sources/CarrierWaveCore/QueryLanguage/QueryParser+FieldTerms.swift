import Foundation

// MARK: - QueryParser Field Term Parsing

extension QueryParser {
    mutating func parseFieldTerm(_ field: QueryField, position: SourcePosition) -> Result<
        QueryExpression, QueryError
    > {
        advance() // consume field token

        // Check for comparison operator
        var comparison: QueryToken?
        if let token = peekToken() {
            switch token {
            case .greaterThan,
                 .lessThan,
                 .greaterThanOrEqual,
                 .lessThanOrEqual:
                comparison = token
                advance()
            default:
                break
            }
        }

        // Get value
        guard let valueToken = peek(), case let .value(value) = valueToken.token else {
            return .failure(
                QueryError.unexpectedToken(
                    expected: "value",
                    got: peek()?.rawText ?? "end of input",
                    position: peek()?.position ?? position
                )
            )
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
            return .success(
                .term(QueryTerm(field: field, condition: condition, position: position))
            )
        case let .failure(error):
            return .failure(error)
        }
    }

    mutating func parseBareTerm(_ value: String, position: SourcePosition) -> Result<
        QueryExpression, QueryError
    > {
        // Check for range
        var endValue: String?
        if peekToken() == .range {
            advance()
            if let endToken = peek(), case let .value(end) = endToken.token {
                advance()
                endValue = end
            }
        }

        // Bare terms without wildcards or ranges are implicit callsign prefix searches
        if endValue == nil, !value.contains("*") {
            let uppercased = value.uppercased()
            return .success(
                .term(
                    QueryTerm(field: .callsign, condition: .prefix(uppercased), position: position)
                )
            )
        }

        // Wildcards and ranges use multi-field bare term matching
        let condition = buildBareTermCondition(value: value, endValue: endValue)
        return .success(.term(QueryTerm(field: nil, condition: condition, position: position)))
    }
}
