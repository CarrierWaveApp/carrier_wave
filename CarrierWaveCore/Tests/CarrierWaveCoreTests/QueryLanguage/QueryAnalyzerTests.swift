//
//  QueryAnalyzerTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("Query Analyzer Tests")
struct QueryAnalyzerTests {
    // MARK: - Basic Analysis

    @Test("Empty query is fast")
    func emptyQueryFast() throws {
        let query = try QueryParser.parse("").get()
        let analysis = QueryAnalyzer.analyze(query, qsoCount: 10_000)

        #expect(analysis.estimatedCost == .indexed)
        #expect(analysis.warnings.isEmpty)
    }

    @Test("Indexed field is fast")
    func indexedFieldFast() throws {
        let query = try QueryParser.parse("call:W1AW").get()
        let analysis = QueryAnalyzer.analyze(query, qsoCount: 10_000)

        #expect(analysis.usesIndex)
        #expect(analysis.estimatedCost == .indexed)
    }

    @Test("Non-indexed field warns on large dataset")
    func nonIndexedFieldWarns() throws {
        let query = try QueryParser.parse("notes:test").get()
        let analysis = QueryAnalyzer.analyze(query, qsoCount: 5_000)

        #expect(!analysis.usesIndex)
        #expect(analysis.shouldWarn)
    }

    // MARK: - Wildcard Analysis

    @Test("Leading wildcard warns")
    func leadingWildcardWarns() throws {
        let query = try QueryParser.parse("call:*AW").get()
        let analysis = QueryAnalyzer.analyze(query, qsoCount: 1_000)

        let hasWildcardWarning = analysis.warnings.contains {
            $0.message.contains("Wildcard at start")
        }
        #expect(hasWildcardWarning)
    }

    @Test("Trailing wildcard is fine")
    func trailingWildcardOk() throws {
        let query = try QueryParser.parse("call:W1*").get()
        let analysis = QueryAnalyzer.analyze(query, qsoCount: 1_000)

        let hasWildcardWarning = analysis.warnings.contains {
            $0.message.contains("Wildcard at start")
        }
        #expect(!hasWildcardWarning)
    }

    // MARK: - Negation Analysis

    @Test("Negation-only query warns")
    func negationOnlyWarns() throws {
        let query = try QueryParser.parse("-W1AW").get()
        let analysis = QueryAnalyzer.analyze(query, qsoCount: 5_000)

        let hasNegationWarning = analysis.warnings.contains {
            $0.message.contains("Exclusion-only")
        }
        #expect(hasNegationWarning)
    }

    @Test("Negation with positive term is fine")
    func negationWithPositiveOk() throws {
        let query = try QueryParser.parse("band:20m -W1AW").get()
        let analysis = QueryAnalyzer.analyze(query, qsoCount: 5_000)

        let hasNegationWarning = analysis.warnings.contains {
            $0.message.contains("Exclusion-only")
        }
        #expect(!hasNegationWarning)
    }

    // MARK: - Date Bound Analysis

    @Test("Large dataset without date warns")
    func largeDataseDateWarns() throws {
        let query = try QueryParser.parse("band:20m").get()
        let analysis = QueryAnalyzer.analyze(query, qsoCount: 15_000)

        let hasHint = analysis.warnings.contains {
            $0.severity == .hint && $0.message.contains("QSOs")
        }
        #expect(hasHint)
    }

    @Test("Large dataset with date bound is fine")
    func largeDateBoundOk() throws {
        let query = try QueryParser.parse("band:20m after:30d").get()
        let analysis = QueryAnalyzer.analyze(query, qsoCount: 15_000)

        let hasHint = analysis.warnings.contains {
            $0.severity == .hint && $0.suggestion?.contains("after") == true
        }
        #expect(!hasHint)
    }

    // MARK: - Query Cost

    @Test("Indexed query cost")
    func indexedQueryCost() throws {
        let query = try QueryParser.parse("call:W1AW band:20m").get()
        let analysis = QueryAnalyzer.analyze(query, qsoCount: 10_000)

        #expect(analysis.estimatedCost == .indexed)
    }

    @Test("Full scan query cost")
    func fullScanQueryCost() throws {
        let query = try QueryParser.parse("notes:test").get()
        let analysis = QueryAnalyzer.analyze(query, qsoCount: 5_000)

        #expect(analysis.estimatedCost == .fullScan)
    }

    // MARK: - Warning Severity

    @Test("High severity requires confirmation")
    func highSeverityConfirmation() throws {
        let query = try QueryParser.parse("-W1AW").get()
        let analysis = QueryAnalyzer.analyze(query, qsoCount: 5_000)

        #expect(analysis.requiresConfirmation)
    }

    @Test("Low severity does not require confirmation")
    func lowSeverityNoConfirmation() throws {
        let query = try QueryParser.parse("call:W1AW").get()
        let analysis = QueryAnalyzer.analyze(query, qsoCount: 100)

        #expect(!analysis.requiresConfirmation)
    }
}
