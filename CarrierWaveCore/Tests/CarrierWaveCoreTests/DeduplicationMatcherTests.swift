//
//  DeduplicationMatcherTests.swift
//  CarrierWaveCoreTests
//

import Foundation
import Testing
@testable import CarrierWaveCore

@Suite("Deduplication Matcher Tests")
struct DeduplicationMatcherTests {
    // MARK: - Test Helpers

    func makeSnapshot(
        id: UUID = UUID(),
        callsign: String = "W1AW",
        timestamp: Date = Date(),
        band: String = "20m",
        mode: String = "SSB",
        parkReference: String? = nil,
        syncedServicesCount: Int = 0,
        rstSent: String? = nil,
        rstReceived: String? = nil
    ) -> QSOSnapshot {
        QSOSnapshot(
            id: id,
            callsign: callsign,
            timestamp: timestamp,
            band: band,
            mode: mode,
            parkReference: parkReference,
            rstSent: rstSent,
            rstReceived: rstReceived,
            syncedServicesCount: syncedServicesCount
        )
    }

    // MARK: - isDuplicate Tests

    @Test("Identical QSOs are duplicates")
    func identicalAreDuplicates() {
        let now = Date()
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now, band: "20m", mode: "SSB")
        let qso2 = makeSnapshot(callsign: "W1AW", timestamp: now, band: "20m", mode: "SSB")

        #expect(DeduplicationMatcher.isDuplicate(qso1, qso2))
    }

    @Test("Different callsigns are not duplicates")
    func differentCallsignsNotDuplicates() {
        let now = Date()
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now)
        let qso2 = makeSnapshot(callsign: "K3LR", timestamp: now)

        #expect(!DeduplicationMatcher.isDuplicate(qso1, qso2))
    }

    @Test("Callsign comparison is case-insensitive")
    func callsignCaseInsensitive() {
        let now = Date()
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now)
        let qso2 = makeSnapshot(callsign: "w1aw", timestamp: now)

        #expect(DeduplicationMatcher.isDuplicate(qso1, qso2))
    }

    @Test("QSOs outside time window are not duplicates")
    func outsideTimeWindowNotDuplicates() {
        let now = Date()
        let later = now.addingTimeInterval(600) // 10 minutes later
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now)
        let qso2 = makeSnapshot(callsign: "W1AW", timestamp: later)

        // Default 5 minute window
        #expect(!DeduplicationMatcher.isDuplicate(qso1, qso2))
    }

    @Test("QSOs within time window are duplicates")
    func withinTimeWindowAreDuplicates() {
        let now = Date()
        let later = now.addingTimeInterval(120) // 2 minutes later
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now)
        let qso2 = makeSnapshot(callsign: "W1AW", timestamp: later)

        #expect(DeduplicationMatcher.isDuplicate(qso1, qso2))
    }

    @Test("Different bands are not duplicates")
    func differentBandsNotDuplicates() {
        let now = Date()
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now, band: "20m")
        let qso2 = makeSnapshot(callsign: "W1AW", timestamp: now, band: "40m")

        #expect(!DeduplicationMatcher.isDuplicate(qso1, qso2))
    }

    @Test("Empty band matches any band")
    func emptyBandMatchesAny() {
        let now = Date()
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now, band: "20m")
        let qso2 = makeSnapshot(callsign: "W1AW", timestamp: now, band: "")

        #expect(DeduplicationMatcher.isDuplicate(qso1, qso2))
    }

    @Test("Equivalent modes are duplicates")
    func equivalentModesAreDuplicates() {
        let now = Date()
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now, mode: "SSB")
        let qso2 = makeSnapshot(callsign: "W1AW", timestamp: now, mode: "USB")

        #expect(DeduplicationMatcher.isDuplicate(qso1, qso2))
    }

    @Test("Different mode families are not duplicates")
    func differentModeFamiliesNotDuplicates() {
        let now = Date()
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now, mode: "SSB")
        let qso2 = makeSnapshot(callsign: "W1AW", timestamp: now, mode: "CW")

        #expect(!DeduplicationMatcher.isDuplicate(qso1, qso2))
    }

    @Test("Different park references are not duplicates (with park matching)")
    func differentParksNotDuplicates() {
        let now = Date()
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now, parkReference: "US-0001")
        let qso2 = makeSnapshot(callsign: "W1AW", timestamp: now, parkReference: "US-0002")

        #expect(!DeduplicationMatcher.isDuplicate(qso1, qso2))
    }

    @Test("Same park references are duplicates")
    func sameParksAreDuplicates() {
        let now = Date()
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now, parkReference: "US-0001")
        let qso2 = makeSnapshot(callsign: "W1AW", timestamp: now, parkReference: "US-0001")

        #expect(DeduplicationMatcher.isDuplicate(qso1, qso2))
    }

    @Test("Nil parks are duplicates (non-activation)")
    func nilParksAreDuplicates() {
        let now = Date()
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now, parkReference: nil)
        let qso2 = makeSnapshot(callsign: "W1AW", timestamp: now, parkReference: nil)

        #expect(DeduplicationMatcher.isDuplicate(qso1, qso2))
    }

    @Test("Nil park vs non-nil park are not duplicates")
    func nilVsNonNilParkNotDuplicates() {
        let now = Date()
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now, parkReference: nil)
        let qso2 = makeSnapshot(callsign: "W1AW", timestamp: now, parkReference: "US-0001")

        #expect(!DeduplicationMatcher.isDuplicate(qso1, qso2))
    }

    // MARK: - findDuplicateGroups Tests

    @Test("Find duplicate groups")
    func findDuplicateGroups() {
        let now = Date()
        let qso1 = makeSnapshot(
            id: UUID(), callsign: "W1AW", timestamp: now, syncedServicesCount: 2
        )
        let qso2 = makeSnapshot(
            id: UUID(), callsign: "W1AW", timestamp: now.addingTimeInterval(30),
            syncedServicesCount: 1
        )
        let qso3 = makeSnapshot(id: UUID(), callsign: "K3LR", timestamp: now) // Different callsign

        let groups = DeduplicationMatcher.findDuplicateGroups([qso1, qso2, qso3])

        #expect(groups.count == 1)
        #expect(groups[0].winnerId == qso1.id) // Higher sync count wins
        #expect(groups[0].loserIds == [qso2.id])
    }

    @Test("No duplicates returns empty")
    func noDuplicatesReturnsEmpty() {
        let now = Date()
        let qso1 = makeSnapshot(callsign: "W1AW", timestamp: now)
        let qso2 = makeSnapshot(callsign: "K3LR", timestamp: now)
        let qso3 = makeSnapshot(callsign: "VE3ABC", timestamp: now)

        let groups = DeduplicationMatcher.findDuplicateGroups([qso1, qso2, qso3])

        #expect(groups.isEmpty)
    }

    @Test("Multiple duplicate groups found")
    func multipleDuplicateGroups() {
        let now = Date()
        // Group 1: W1AW
        let qso1 = makeSnapshot(id: UUID(), callsign: "W1AW", timestamp: now)
        let qso2 = makeSnapshot(id: UUID(), callsign: "W1AW", timestamp: now.addingTimeInterval(30))
        // Group 2: K3LR
        let qso3 = makeSnapshot(id: UUID(), callsign: "K3LR", timestamp: now)
        let qso4 = makeSnapshot(id: UUID(), callsign: "K3LR", timestamp: now.addingTimeInterval(30))

        let groups = DeduplicationMatcher.findDuplicateGroups([qso1, qso2, qso3, qso4])

        #expect(groups.count == 2)
    }

    // MARK: - selectWinner Tests

    @Test("Winner has most synced services")
    func winnerMostSyncedServices() {
        let now = Date()
        let qso1 = makeSnapshot(syncedServicesCount: 1)
        let qso2 = makeSnapshot(syncedServicesCount: 3)
        let qso3 = makeSnapshot(syncedServicesCount: 2)

        let winner = DeduplicationMatcher.selectWinner(from: [qso1, qso2, qso3])

        #expect(winner.syncedServicesCount == 3)
    }

    @Test("Winner has highest field richness when sync count tied")
    func winnerHighestFieldRichness() {
        let now = Date()
        let qso1 = makeSnapshot(syncedServicesCount: 1, rstSent: nil, rstReceived: nil)
        let qso2 = makeSnapshot(syncedServicesCount: 1, rstSent: "59", rstReceived: "59")

        let winner = DeduplicationMatcher.selectWinner(from: [qso1, qso2])

        #expect(winner.id == qso2.id)
    }

    // MARK: - mergeFields Tests

    @Test("Merge fills nil fields from loser")
    func mergeFillsNilFields() {
        let winner = makeSnapshot(rstSent: nil, rstReceived: "59")
        let loser = makeSnapshot(rstSent: "59", rstReceived: "57")

        let merged = DeduplicationMatcher.mergeFields(winner: winner, loser: loser)

        #expect(merged.rstSent == "59") // Filled from loser
        #expect(merged.rstReceived == "59") // Kept from winner
    }

    @Test("Merge prefers specific mode over generic")
    func mergePreferSpecificMode() {
        let winner = makeSnapshot(mode: "PHONE")
        let loser = makeSnapshot(mode: "SSB")

        let merged = DeduplicationMatcher.mergeFields(winner: winner, loser: loser)

        #expect(merged.mode == "SSB")
    }

    @Test("Merge fills empty band from loser")
    func mergeFillsEmptyBand() {
        let winner = makeSnapshot(band: "")
        let loser = makeSnapshot(band: "20m")

        let merged = DeduplicationMatcher.mergeFields(winner: winner, loser: loser)

        #expect(merged.band == "20m")
    }
}
