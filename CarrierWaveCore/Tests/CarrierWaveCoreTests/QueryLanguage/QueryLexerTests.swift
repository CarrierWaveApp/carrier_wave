//
//  QueryLexerTests.swift
//  CarrierWaveCoreTests
//
import Testing
@testable import CarrierWaveCore

@Suite("Query Lexer Tests")
struct QueryLexerTests {
    // MARK: - Basic Tokenization

    @Test("Tokenize simple value")
    func tokenizeSimpleValue() throws {
        var lexer = QueryLexer("W1AW")
        let result = try lexer.tokenize().get()

        #expect(result.count == 2) // value + eof
        if case let .value(v) = result[0].token {
            #expect(v == "W1AW")
        } else {
            Issue.record("Expected value token")
        }
    }

    @Test("Tokenize field:value")
    func tokenizeFieldValue() throws {
        var lexer = QueryLexer("call:W1AW")
        let result = try lexer.tokenize().get()

        #expect(result.count == 3) // field + value + eof
        if case let .field(field) = result[0].token {
            #expect(field == .callsign)
        } else {
            Issue.record("Expected field token")
        }
        if case let .value(v) = result[1].token {
            #expect(v == "W1AW")
        } else {
            Issue.record("Expected value token")
        }
    }

    @Test("Tokenize multiple terms")
    func tokenizeMultipleTerms() throws {
        var lexer = QueryLexer("band:20m mode:SSB")
        let result = try lexer.tokenize().get()

        #expect(result.count == 5) // field + value + field + value + eof
    }

    // MARK: - Operators

    @Test("Tokenize OR operator")
    func tokenizeOrOperator() throws {
        var lexer = QueryLexer("W1AW | K2ABC")
        let result = try lexer.tokenize().get()

        #expect(result.contains { $0.token == .or })
    }

    @Test("Tokenize NOT operator")
    func tokenizeNotOperator() throws {
        var lexer = QueryLexer("-W1AW")
        let result = try lexer.tokenize().get()

        #expect(result[0].token == .not)
    }

    @Test("Tokenize parentheses")
    func tokenizeParentheses() throws {
        var lexer = QueryLexer("(W1AW | K2ABC)")
        let result = try lexer.tokenize().get()

        #expect(result[0].token == .openParen)
        #expect(result[4].token == .closeParen)
    }

    @Test("Tokenize comparison operators")
    func tokenizeComparisonOperators() throws {
        var lexer = QueryLexer("freq:>14.000")
        let result = try lexer.tokenize().get()

        #expect(result.contains { $0.token == .greaterThan })
    }

    // MARK: - Ranges

    @Test("Tokenize range")
    func tokenizeRange() throws {
        var lexer = QueryLexer("date:2024-01..2024-12")
        let result = try lexer.tokenize().get()

        #expect(result.contains { $0.token == .range })
    }

    // MARK: - Quoted Strings

    @Test("Tokenize quoted string")
    func tokenizeQuotedString() throws {
        var lexer = QueryLexer("notes:\"hello world\"")
        let result = try lexer.tokenize().get()

        if case let .value(v) = result[1].token {
            #expect(v == "hello world")
        } else {
            Issue.record("Expected value token with quoted content")
        }
    }

    @Test("Unterminated quoted string fails")
    func unterminatedQuotedString() {
        var lexer = QueryLexer("notes:\"hello")
        let result = lexer.tokenize()

        if case .failure = result {
            // Expected
        } else {
            Issue.record("Expected failure for unterminated string")
        }
    }

    // MARK: - Field Aliases

    @Test("Field aliases work")
    func fieldAliases() throws {
        // "call" and "callsign" should both work
        var lexer1 = QueryLexer("call:W1AW")
        var lexer2 = QueryLexer("callsign:W1AW")

        let result1 = try lexer1.tokenize().get()
        let result2 = try lexer2.tokenize().get()

        if case let .field(f1) = result1[0].token, case let .field(f2) = result2[0].token {
            #expect(f1 == f2)
            #expect(f1 == .callsign)
        } else {
            Issue.record("Expected field tokens")
        }
    }

    @Test("Unknown field fails with suggestion")
    func unknownFieldSuggestion() {
        var lexer = QueryLexer("cal:W1AW") // typo for "call"
        let result = lexer.tokenize()

        if case let .failure(error) = result {
            if case let .unknownField(_, suggestion, _) = error {
                #expect(suggestion == "call")
            } else {
                Issue.record("Expected unknownField error")
            }
        } else {
            Issue.record("Expected failure for unknown field")
        }
    }
}
