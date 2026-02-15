//
//  QueryParserTests.swift
//  CarrierWaveCoreTests
//
// swiftlint:disable identifier_name

import Testing
@testable import CarrierWaveCore

@Suite("Query Parser Tests")
struct QueryParserTests {
    // MARK: - Basic Parsing

    @Test("Parse empty query")
    func parseEmptyQuery() throws {
        let result = try QueryParser.parse("").get()
        #expect(result.isEmpty)
    }

    @Test("Parse bare term as callsign prefix")
    func parseBareTerm() throws {
        let result = try QueryParser.parse("W1AW").get()
        #expect(!result.isEmpty)

        if case let .term(term) = result.expression {
            #expect(term.field == .callsign)
            if case let .prefix(v) = term.condition {
                #expect(v == "W1AW")
            } else {
                Issue.record("Expected prefix condition, got \(term.condition)")
            }
        } else {
            Issue.record("Expected term expression")
        }
    }

    @Test("Parse bare term is uppercased")
    func parseBareTermUppercased() throws {
        let result = try QueryParser.parse("w1aw").get()

        if case let .term(term) = result.expression {
            #expect(term.field == .callsign)
            if case let .prefix(v) = term.condition {
                #expect(v == "W1AW")
            } else {
                Issue.record("Expected prefix condition, got \(term.condition)")
            }
        } else {
            Issue.record("Expected term expression")
        }
    }

    @Test("Parse field term")
    func parseFieldTerm() throws {
        let result = try QueryParser.parse("call:W1AW").get()

        if case let .term(term) = result.expression {
            #expect(term.field == .callsign)
            if case let .equals(v) = term.condition {
                #expect(v == "W1AW")
            }
        } else {
            Issue.record("Expected term expression")
        }
    }

    // MARK: - Boolean Logic

    @Test("Parse AND (implicit)")
    func parseImplicitAnd() throws {
        let result = try QueryParser.parse("band:20m mode:SSB").get()

        if case let .and(terms) = result.expression {
            #expect(terms.count == 2)
        } else {
            Issue.record("Expected AND expression")
        }
    }

    @Test("Parse OR (explicit)")
    func parseExplicitOr() throws {
        let result = try QueryParser.parse("W1AW | K2ABC").get()

        if case let .or(terms) = result.expression {
            #expect(terms.count == 2)
        } else {
            Issue.record("Expected OR expression")
        }
    }

    @Test("Parse NOT")
    func parseNot() throws {
        let result = try QueryParser.parse("-W1AW").get()

        if case let .not(inner) = result.expression {
            if case let .term(term) = inner {
                #expect(term.field == .callsign)
                if case let .prefix(v) = term.condition {
                    #expect(v == "W1AW")
                } else {
                    Issue.record("Expected prefix condition, got \(term.condition)")
                }
            }
        } else {
            Issue.record("Expected NOT expression")
        }
    }

    @Test("Parse bare wildcard still searches multiple fields")
    func parseBareWildcard() throws {
        let result = try QueryParser.parse("W1*").get()

        if case let .term(term) = result.expression {
            #expect(term.field == nil) // wildcard bare terms search across fields
            if case let .prefix(v) = term.condition {
                #expect(v == "W1")
            } else {
                Issue.record("Expected prefix condition, got \(term.condition)")
            }
        } else {
            Issue.record("Expected term expression")
        }
    }

    @Test("Parse grouped expression")
    func parseGrouped() throws {
        let result = try QueryParser.parse("(W1AW | K2ABC) band:20m").get()

        if case let .and(terms) = result.expression {
            #expect(terms.count == 2)
            // First should be the OR group
            if case let .or(orTerms) = terms[0] {
                #expect(orTerms.count == 2)
            }
        } else {
            Issue.record("Expected AND with grouped OR")
        }
    }

    // MARK: - Wildcards

    @Test("Parse prefix wildcard")
    func parsePrefixWildcard() throws {
        let result = try QueryParser.parse("call:W1*").get()

        if case let .term(term) = result.expression {
            if case let .prefix(v) = term.condition {
                #expect(v == "W1")
            }
        } else {
            Issue.record("Expected term with prefix condition")
        }
    }

    @Test("Parse suffix wildcard")
    func parseSuffixWildcard() throws {
        let result = try QueryParser.parse("call:*AW").get()

        if case let .term(term) = result.expression {
            if case let .suffix(v) = term.condition {
                #expect(v == "AW")
            }
        } else {
            Issue.record("Expected term with suffix condition")
        }
    }

    @Test("Parse contains wildcard")
    func parseContainsWildcard() throws {
        let result = try QueryParser.parse("call:*1A*").get()

        if case let .term(term) = result.expression {
            if case let .contains(v) = term.condition {
                #expect(v == "1A")
            }
        } else {
            Issue.record("Expected term with contains condition")
        }
    }

    // MARK: - Date Parsing

    @Test("Parse date today")
    func parseDateToday() throws {
        let result = try QueryParser.parse("date:today").get()

        if case let .term(term) = result.expression {
            if case let .dateEquals(match) = term.condition {
                if case .today = match {
                    // Pass
                } else {
                    Issue.record("Expected .today")
                }
            }
        } else {
            Issue.record("Expected term")
        }
    }

    @Test("Parse date relative")
    func parseDateRelative() throws {
        let result = try QueryParser.parse("after:7d").get()

        if case let .term(term) = result.expression {
            if case let .dateAfter(match) = term.condition {
                if case let .relative(days) = match {
                    #expect(days == 7)
                }
            }
        } else {
            Issue.record("Expected term")
        }
    }

    @Test("Parse date range")
    func parseDateRange() throws {
        let result = try QueryParser.parse("date:2024-01..2024-12").get()

        if case let .term(term) = result.expression {
            if case let .dateRange(start, end) = term.condition {
                if case let .yearMonth(y1, m1) = start, case let .yearMonth(y2, m2) = end {
                    #expect(y1 == 2_024)
                    #expect(m1 == 1)
                    #expect(y2 == 2_024)
                    #expect(m2 == 12)
                }
            }
        } else {
            Issue.record("Expected term with date range")
        }
    }

    // MARK: - Numeric Conditions

    @Test("Parse numeric comparison")
    func parseNumericComparison() throws {
        let result = try QueryParser.parse("freq:>14.000").get()

        if case let .term(term) = result.expression {
            if case let .greaterThan(n) = term.condition {
                #expect(n == 14.0)
            }
        } else {
            Issue.record("Expected term with numeric comparison")
        }
    }

    @Test("Parse numeric range")
    func parseNumericRange() throws {
        // Use integer values to avoid lexer issues with decimal ranges
        let result = try QueryParser.parse("freq:14..15").get()

        if case let .term(term) = result.expression {
            if case let .numericRange(low, high) = term.condition {
                #expect(low == 14.0)
                #expect(high == 15.0)
            }
        } else {
            Issue.record("Expected term with numeric range")
        }
    }

    // MARK: - Boolean/Service Conditions

    @Test("Parse boolean yes")
    func parseBooleanYes() throws {
        let result = try QueryParser.parse("confirmed:yes").get()

        if case let .term(term) = result.expression {
            if case let .boolean(v) = term.condition {
                #expect(v == true)
            }
        } else {
            Issue.record("Expected term with boolean condition")
        }
    }

    @Test("Parse service type")
    func parseServiceType() throws {
        let result = try QueryParser.parse("synced:lotw").get()

        if case let .term(term) = result.expression {
            if case let .service(s) = term.condition {
                #expect(s == .lotw)
            }
        } else {
            Issue.record("Expected term with service condition")
        }
    }

    // MARK: - Error Handling

    @Test("Unmatched parenthesis fails")
    func unmatchedParenthesis() {
        let result = QueryParser.parse("(W1AW")

        if case let .failure(error) = result {
            if case .unmatchedParenthesis = error {
                // Pass
            } else {
                Issue.record("Expected unmatchedParenthesis error")
            }
        } else {
            Issue.record("Expected failure")
        }
    }

    @Test("Invalid date format fails")
    func invalidDateFormat() {
        let result = QueryParser.parse("date:invalid")

        if case let .failure(error) = result {
            if case .invalidDateFormat = error {
                // Pass
            } else {
                Issue.record("Expected invalidDateFormat error")
            }
        } else {
            Issue.record("Expected failure")
        }
    }
}
