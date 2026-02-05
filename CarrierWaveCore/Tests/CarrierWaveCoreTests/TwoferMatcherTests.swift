//
//  TwoferMatcherTests.swift
//  CarrierWaveCoreTests
//

import Foundation
import Testing
@testable import CarrierWaveCore

@Suite("Two-fer Matcher Tests")
struct TwoferMatcherTests {
    // MARK: - Test Helpers

    func makeSnapshot(
        id: UUID = UUID(),
        callsign: String = "W1AW",
        timestamp: Date = Date(),
        band: String = "20m",
        mode: String = "SSB",
        parkReference: String? = nil
    ) -> QSOSnapshot {
        QSOSnapshot(
            id: id,
            callsign: callsign,
            timestamp: timestamp,
            band: band,
            mode: mode,
            parkReference: parkReference
        )
    }

    // MARK: - findDuplicatesFor Tests

    @Test("Single park duplicate of two-fer found")
    func singleParkDuplicateFound() {
        let now = Date()
        let multiParkId = UUID()
        let singleParkId = UUID()

        let multiPark = makeSnapshot(
            id: multiParkId,
            callsign: "W1AW",
            timestamp: now,
            parkReference: "US-1044, US-3791"
        )
        let singlePark = makeSnapshot(
            id: singleParkId,
            callsign: "W1AW",
            timestamp: now.addingTimeInterval(30),
            parkReference: "US-1044"
        )

        let duplicates = TwoferMatcher.findDuplicatesFor(
            multiParkSnapshot: multiPark,
            in: [multiPark, singlePark]
        )

        #expect(duplicates == [singleParkId])
    }

    @Test("Different callsign not matched")
    func differentCallsignNotMatched() {
        let now = Date()
        let multiPark = makeSnapshot(
            callsign: "W1AW",
            timestamp: now,
            parkReference: "US-1044, US-3791"
        )
        let singlePark = makeSnapshot(
            callsign: "K3LR",
            timestamp: now,
            parkReference: "US-1044"
        )

        let duplicates = TwoferMatcher.findDuplicatesFor(
            multiParkSnapshot: multiPark,
            in: [multiPark, singlePark]
        )

        #expect(duplicates.isEmpty)
    }

    @Test("Park not in multi-park not matched")
    func differentParkNotMatched() {
        let now = Date()
        let multiPark = makeSnapshot(
            callsign: "W1AW",
            timestamp: now,
            parkReference: "US-1044, US-3791"
        )
        let singlePark = makeSnapshot(
            callsign: "W1AW",
            timestamp: now,
            parkReference: "US-9999"
        )

        let duplicates = TwoferMatcher.findDuplicatesFor(
            multiParkSnapshot: multiPark,
            in: [multiPark, singlePark]
        )

        #expect(duplicates.isEmpty)
    }

    @Test("Outside time window not matched")
    func outsideTimeWindowNotMatched() {
        let now = Date()
        let multiPark = makeSnapshot(
            callsign: "W1AW",
            timestamp: now,
            parkReference: "US-1044, US-3791"
        )
        let singlePark = makeSnapshot(
            callsign: "W1AW",
            timestamp: now.addingTimeInterval(120), // 2 minutes (beyond 60s window)
            parkReference: "US-1044"
        )

        let duplicates = TwoferMatcher.findDuplicatesFor(
            multiParkSnapshot: multiPark,
            in: [multiPark, singlePark]
        )

        #expect(duplicates.isEmpty)
    }

    @Test("Different band not matched")
    func differentBandNotMatched() {
        let now = Date()
        let multiPark = makeSnapshot(
            callsign: "W1AW",
            timestamp: now,
            band: "20m",
            parkReference: "US-1044, US-3791"
        )
        let singlePark = makeSnapshot(
            callsign: "W1AW",
            timestamp: now,
            band: "40m",
            parkReference: "US-1044"
        )

        let duplicates = TwoferMatcher.findDuplicatesFor(
            multiParkSnapshot: multiPark,
            in: [multiPark, singlePark]
        )

        #expect(duplicates.isEmpty)
    }

    @Test("Empty band matches any")
    func emptyBandMatches() {
        let now = Date()
        let multiPark = makeSnapshot(
            callsign: "W1AW",
            timestamp: now,
            band: "20m",
            parkReference: "US-1044, US-3791"
        )
        let singlePark = makeSnapshot(
            id: UUID(),
            callsign: "W1AW",
            timestamp: now,
            band: "",
            parkReference: "US-1044"
        )

        let duplicates = TwoferMatcher.findDuplicatesFor(
            multiParkSnapshot: multiPark,
            in: [multiPark, singlePark]
        )

        #expect(duplicates.count == 1)
    }

    @Test("Different mode family not matched")
    func differentModeFamilyNotMatched() {
        let now = Date()
        let multiPark = makeSnapshot(
            callsign: "W1AW",
            timestamp: now,
            mode: "SSB",
            parkReference: "US-1044, US-3791"
        )
        let singlePark = makeSnapshot(
            callsign: "W1AW",
            timestamp: now,
            mode: "CW",
            parkReference: "US-1044"
        )

        let duplicates = TwoferMatcher.findDuplicatesFor(
            multiParkSnapshot: multiPark,
            in: [multiPark, singlePark]
        )

        #expect(duplicates.isEmpty)
    }

    @Test("Equivalent modes matched")
    func equivalentModesMatched() {
        let now = Date()
        let multiParkId = UUID()
        let singleParkId = UUID()

        let multiPark = makeSnapshot(
            id: multiParkId,
            callsign: "W1AW",
            timestamp: now,
            mode: "SSB",
            parkReference: "US-1044, US-3791"
        )
        let singlePark = makeSnapshot(
            id: singleParkId,
            callsign: "W1AW",
            timestamp: now,
            mode: "USB", // Equivalent to SSB
            parkReference: "US-1044"
        )

        let duplicates = TwoferMatcher.findDuplicatesFor(
            multiParkSnapshot: multiPark,
            in: [multiPark, singlePark]
        )

        #expect(duplicates == [singleParkId])
    }

    // MARK: - findTwoferDuplicateGroups Tests

    @Test("Find two-fer duplicate groups")
    func findTwoferDuplicateGroups() {
        let now = Date()
        let multiParkId = UUID()
        let singlePark1Id = UUID()
        let singlePark2Id = UUID()

        let multiPark = makeSnapshot(
            id: multiParkId,
            callsign: "W1AW",
            timestamp: now,
            parkReference: "US-1044, US-3791"
        )
        let singlePark1 = makeSnapshot(
            id: singlePark1Id,
            callsign: "W1AW",
            timestamp: now.addingTimeInterval(10),
            parkReference: "US-1044"
        )
        let singlePark2 = makeSnapshot(
            id: singlePark2Id,
            callsign: "W1AW",
            timestamp: now.addingTimeInterval(20),
            parkReference: "US-3791"
        )
        let unrelated = makeSnapshot(
            callsign: "K3LR",
            timestamp: now,
            parkReference: "K-0001"
        )

        let groups = TwoferMatcher.findTwoferDuplicateGroups([
            multiPark, singlePark1, singlePark2, unrelated,
        ])

        #expect(groups.count == 1)
        #expect(groups[0].winnerId == multiParkId)
        #expect(Set(groups[0].loserIds) == Set([singlePark1Id, singlePark2Id]))
    }

    @Test("No two-fer duplicates returns empty")
    func noTwoferDuplicatesReturnsEmpty() {
        let now = Date()
        let qso1 = makeSnapshot(
            callsign: "W1AW",
            timestamp: now,
            parkReference: "US-1044" // Single park
        )
        let qso2 = makeSnapshot(
            callsign: "K3LR",
            timestamp: now,
            parkReference: "K-0001"
        )

        let groups = TwoferMatcher.findTwoferDuplicateGroups([qso1, qso2])

        #expect(groups.isEmpty)
    }

    @Test("Multi-park with no single-park duplicates returns empty")
    func multiParkNoDuplicatesReturnsEmpty() {
        let now = Date()
        let multiPark = makeSnapshot(
            callsign: "W1AW",
            timestamp: now,
            parkReference: "US-1044, US-3791"
        )
        let unrelatedSingle = makeSnapshot(
            callsign: "K3LR", // Different callsign
            timestamp: now,
            parkReference: "US-1044"
        )

        let groups = TwoferMatcher.findTwoferDuplicateGroups([multiPark, unrelatedSingle])

        #expect(groups.isEmpty)
    }
}
