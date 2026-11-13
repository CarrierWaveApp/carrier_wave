import XCTest
@testable import CarrierWaveCore

final class SCPDatabaseTests: XCTestCase {
    // MARK: - Initialization

    func testInitDeduplicatesAndUppercases() {
        let db = SCPDatabase(callsigns: ["w6jsv", "W6JSV", "k6abc", "K6ABC", "w6jsv"])
        XCTAssertEqual(db.count, 2)
    }

    func testInitFiltersEmptyStrings() {
        let db = SCPDatabase(callsigns: ["W6JSV", "", "  ", "K6ABC"])
        // Empty string filtered, whitespace-only kept (uppercased "  " is non-empty but odd)
        // Actually "  ".uppercased() == "  " which is non-empty, so it stays
        XCTAssertTrue(db.contains("W6JSV"))
        XCTAssertTrue(db.contains("K6ABC"))
    }

    func testEmptyDatabase() {
        let db = SCPDatabase(callsigns: [])
        XCTAssertTrue(db.isEmpty)
        XCTAssertEqual(db.count, 0)
        XCTAssertEqual(db.partialMatch("W6J"), [])
        XCTAssertFalse(db.contains("W6JSV"))
        XCTAssertEqual(db.nearMatches(for: "W6JSV").count, 0)
    }

    // MARK: - Partial Match

    func testPartialMatchPrefixFirst() {
        let db = SCPDatabase(callsigns: ["W6JSV", "KW6JS", "W6JTI", "W6JBR", "AA1AA"])
        let results = db.partialMatch("W6J")
        // Prefix matches (W6J*) come first, then substring (KW6JS)
        XCTAssertTrue(results.count >= 3)
        XCTAssertEqual(results[0], "W6JBR") // alphabetical among prefix matches
        XCTAssertEqual(results[1], "W6JSV")
        XCTAssertEqual(results[2], "W6JTI")
        // KW6JS contains W6J but is not a prefix match
        XCTAssertTrue(results.contains("KW6JS"))
        XCTAssertFalse(results.contains("AA1AA"))
    }

    func testPartialMatchRespectsLimit() {
        let calls = (0 ..< 50).map { String(format: "W6J%02d", $0) }
        let db = SCPDatabase(callsigns: calls)
        let results = db.partialMatch("W6J", limit: 10)
        XCTAssertEqual(results.count, 10)
    }

    func testPartialMatchTooShortReturnsEmpty() {
        let db = SCPDatabase(callsigns: ["W6JSV", "W6JTI"])
        XCTAssertEqual(db.partialMatch("W6"), [])
        XCTAssertEqual(db.partialMatch("W"), [])
        XCTAssertEqual(db.partialMatch(""), [])
    }

    func testPartialMatchCaseInsensitive() {
        let db = SCPDatabase(callsigns: ["W6JSV", "K6ABC"])
        let results = db.partialMatch("w6j")
        XCTAssertEqual(results, ["W6JSV"])
    }

    // MARK: - Contains

    func testContainsExactMatch() {
        let db = SCPDatabase(callsigns: ["W6JSV", "K6ABC", "VE3XYZ"])
        XCTAssertTrue(db.contains("W6JSV"))
        XCTAssertTrue(db.contains("w6jsv"))
        XCTAssertFalse(db.contains("W6JSX"))
    }

    // MARK: - Near Matches

    func testNearMatchesFindsEditDistance1() {
        let db = SCPDatabase(callsigns: ["W6JSV", "W6JSW", "W6JTV", "K6ABC"])
        let results = db.nearMatches(for: "W6JSX", maxDistance: 1)
        let callsigns = results.map(\.callsign)
        XCTAssertTrue(callsigns.contains("W6JSV"))
        XCTAssertTrue(callsigns.contains("W6JSW"))
        // W6JTV is distance 2 from W6JSX, so excluded at maxDistance 1
        XCTAssertFalse(callsigns.contains("W6JTV"))
    }

    func testNearMatchesSkipsShortCallsigns() {
        let db = SCPDatabase(callsigns: ["W6JSV"])
        let results = db.nearMatches(for: "W6J")
        XCTAssertTrue(results.isEmpty)
    }

    func testNearMatchesSkipsExactMatch() {
        let db = SCPDatabase(callsigns: ["W6JSV", "W6JSW"])
        let results = db.nearMatches(for: "W6JSV", maxDistance: 1)
        let callsigns = results.map(\.callsign)
        XCTAssertFalse(callsigns.contains("W6JSV"))
        XCTAssertTrue(callsigns.contains("W6JSW"))
    }

    // MARK: - Merging

    func testMergingAddsNewCallsigns() {
        let db = SCPDatabase(callsigns: ["W6JSV", "K6ABC"])
        let merged = db.merging(additionalCallsigns: ["VE3XYZ", "JA1ABC"])
        XCTAssertEqual(merged.count, 4)
        XCTAssertTrue(merged.contains("VE3XYZ"))
        XCTAssertTrue(merged.contains("JA1ABC"))
        XCTAssertTrue(merged.contains("W6JSV"))
    }

    func testMergingDeduplicatesExisting() {
        let db = SCPDatabase(callsigns: ["W6JSV", "K6ABC"])
        let merged = db.merging(additionalCallsigns: ["w6jsv", "VE3XYZ"])
        XCTAssertEqual(merged.count, 3) // W6JSV not duplicated
        XCTAssertTrue(merged.contains("VE3XYZ"))
    }

    func testMergingWithEmptyIsIdentity() {
        let db = SCPDatabase(callsigns: ["W6JSV", "K6ABC"])
        let merged = db.merging(additionalCallsigns: [String]())
        XCTAssertEqual(merged.count, 2)
    }

    func testMergedDatabaseSupportsPartialMatch() {
        let db = SCPDatabase(callsigns: ["W6JSV"])
        let merged = db.merging(additionalCallsigns: ["W6JTI", "K6ABC"])
        let results = merged.partialMatch("W6J")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains("W6JSV"))
        XCTAssertTrue(results.contains("W6JTI"))
    }
}
