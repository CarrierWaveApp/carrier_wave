import CarrierWaveCore
import Foundation

// MARK: - ContestExchangeParseResult

/// Result of parsing contest exchange tokens against a definition.
public struct ContestExchangeParseResult: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        fields: [String: String] = [:],
        serialReceived: Int? = nil,
        unmatchedTokens: [String] = []
    ) {
        self.fields = fields
        self.serialReceived = serialReceived
        self.unmatchedTokens = unmatchedTokens
    }

    // MARK: Public

    /// Received-field values keyed by `ContestExchangeField.name`.
    public var fields: [String: String]
    public var serialReceived: Int?
    public var unmatchedTokens: [String]
}

// MARK: - ContestExchangeParser

/// Classifies tokens from a contest exchange against the received-field
/// definitions. Facade over `cw_domain::contest::exchange_parser`.
public enum ContestExchangeParser {
    /// Parse space-separated tokens against a contest's received-field list.
    public static func parse(
        tokens: [String],
        definition: ContestDefinition
    ) -> ContestExchangeParseResult {
        guard let result = try? contestParseExchange(
            tokens: tokens,
            definitionJson: definition.rawJson
        ) else {
            return ContestExchangeParseResult(unmatchedTokens: tokens)
        }
        return ContestExchangeParseResult(
            fields: result.fields,
            serialReceived: result.serialReceived.map(Int.init),
            unmatchedTokens: result.unmatchedTokens
        )
    }
}
