//
//  BandScopeLogicTests.swift
//  CarrierWaveTests
//
//  Pure-logic coverage for the Band Scope v2 spot browser: pileup
//  clustering + gap math, busted-copy detection, Heard aggregation and
//  time buckets, anchor trust decay, freshness fade, and tier assignment.
//

import XCTest
@testable import CarrierWave

@MainActor
final class BandScopeLogicTests: XCTestCase {
    // MARK: Internal

    // MARK: - Clustering (§10)

    func testChainedClusteringGroupsWithinWidth() {
        // 14040.0 / 14040.4 / 14040.8 chain into ONE cluster (each link
        // ≤ 0.45 kHz) even though the ends are 0.8 apart.
        let spots = [
            spot(id: "a", callsign: "W1A", freqKHz: 14_040.0),
            spot(id: "b", callsign: "W2B", freqKHz: 14_040.4),
            spot(id: "c", callsign: "W3C", freqKHz: 14_040.8),
            spot(id: "d", callsign: "W4D", freqKHz: 14_042.0),
        ]
        let clusters = ScopeClustering.clusters(of: spots)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters[0].spots.count, 3)
        XCTAssertEqual(clusters[1].spots.count, 1)
        XCTAssertTrue(clusters[0].isPileup)
    }

    func testClustersSortAscendingByFrequency() {
        let spots = [
            spot(id: "hi", callsign: "W1A", freqKHz: 14_055.0),
            spot(id: "lo", callsign: "W2B", freqKHz: 14_020.0),
        ]
        let clusters = ScopeClustering.clusters(of: spots)
        XCTAssertEqual(clusters.map(\.id), ["lo", "hi"])
    }

    // MARK: - Gaps (§4)

    func testGapComputedBetweenClusterEdges() {
        let spots = [
            spot(id: "a", callsign: "W1A", freqKHz: 14_040.0),
            spot(id: "b", callsign: "W2B", freqKHz: 14_040.3),
            spot(id: "c", callsign: "W3C", freqKHz: 14_042.3),
        ]
        let clusters = ScopeClustering.clusters(of: spots)
        let gaps = ScopeClustering.gaps(between: clusters)
        XCTAssertEqual(gaps.count, 1)
        // Last of previous (14040.3) to first of next (14042.3).
        XCTAssertEqual(gaps[0].gapKHz, 2.0, accuracy: 0.001)
        XCTAssertEqual(gaps[0].midpointKHz, 14_041.3, accuracy: 0.001)
        XCTAssertTrue(gaps[0].isQSYAffordance)
    }

    func testSmallGapIsNotAnAffordance() {
        let spots = [
            spot(id: "a", callsign: "W1A", freqKHz: 14_040.0),
            spot(id: "b", callsign: "W2B", freqKHz: 14_040.6),
        ]
        let clusters = ScopeClustering.clusters(of: spots)
        let gaps = ScopeClustering.gaps(between: clusters)
        XCTAssertEqual(gaps.count, 1)
        XCTAssertFalse(gaps[0].isQSYAffordance)
    }

    // MARK: - Busted-copy detection (§10)

    func testEditDistanceOne() {
        XCTAssertTrue(ScopeClustering.isEditDistanceOne("N5RAD", "I5RAD"))
        XCTAssertTrue(ScopeClustering.isEditDistanceOne("W6JY", "W6JYA"))
        XCTAssertFalse(ScopeClustering.isEditDistanceOne("W6JY", "W6JY"))
        XCTAssertFalse(ScopeClustering.isEditDistanceOne("N5RAD", "I5RAT"))
        XCTAssertFalse(ScopeClustering.isEditDistanceOne("K1A", "W9ZZZ"))
    }

    func testSkimmerCopyIsTheSuspect() {
        let human = spot(
            id: "pota-1", callsign: "N5RAD", freqKHz: 14_040.0, source: .pota
        )
        let skimmer = spot(
            id: "rbn-1", callsign: "I5RAD", freqKHz: 14_040.2, source: .rbn
        )
        let clusters = ScopeClustering.clusters(of: [human, skimmer])
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(
            ScopeClustering.bustedSuspectIDs(in: clusters[0]), ["rbn-1"]
        )
    }

    func testHumanPairIsNotFlagged() {
        let clusters = ScopeClustering.clusters(of: [
            spot(id: "a", callsign: "N5RAD", freqKHz: 14_040.0, source: .pota),
            spot(id: "b", callsign: "I5RAD", freqKHz: 14_040.2, source: .pota),
        ])
        XCTAssertTrue(ScopeClustering.bustedSuspectIDs(in: clusters[0]).isEmpty)
    }

    // MARK: - Heard aggregation (§13)

    func testPerStationCollapseLatestWins() {
        let now = Date()
        let stations = HeardAggregation.stations(from: [
            spot(id: "old", callsign: "W1AW", freqKHz: 14_040.0, timestamp: now - 600),
            spot(id: "new", callsign: "W1AW", freqKHz: 7_040.0, timestamp: now - 10),
            spot(id: "x", callsign: "K6XYZ", freqKHz: 21_030.0, timestamp: now - 300),
        ])
        XCTAssertEqual(stations.count, 2)
        XCTAssertEqual(stations[0].callsign, "W1AW")
        XCTAssertEqual(stations[0].latest.id, "new")
        XCTAssertEqual(stations[0].heardCount, 2)
        // Strictly reverse-chronological — never priority-ranked.
        XCTAssertEqual(stations[1].callsign, "K6XYZ")
    }

    func testBustedCopiesFullyDedupedInHeard() {
        let stations = HeardAggregation.stations(
            from: [
                spot(id: "good", callsign: "N5RAD", freqKHz: 14_040.0, source: .pota),
                spot(id: "bad", callsign: "I5RAD", freqKHz: 14_040.2, source: .rbn),
            ],
            excluding: ["bad"]
        )
        XCTAssertEqual(stations.map(\.callsign), ["N5RAD"])
    }

    func testTimeBuckets() {
        let now = Date()
        XCTAssertEqual(HeardBucket.bucket(for: now - 30, now: now), .justNow)
        XCTAssertEqual(HeardBucket.bucket(for: now - 300, now: now), .recent)
        XCTAssertEqual(HeardBucket.bucket(for: now - 2_000, now: now), .earlier)
    }

    // MARK: - Anchor trust decay (§6)

    func testAnchorTrustCurve() {
        let setAt = Date()
        let anchor = BandScopeAnchor(frequencyKHz: 14_062.5, band: "20m", setAt: setAt)
        XCTAssertEqual(anchor.trust(at: setAt + 60), 1.0)
        // Midway through the fade window: halfway between 1.0 and 0.3.
        let mid = setAt + 300
        XCTAssertEqual(anchor.trust(at: mid), 0.65, accuracy: 0.001)
        XCTAssertEqual(anchor.trust(at: setAt + 700), 0.3)
        XCTAssertFalse(anchor.isExpired(at: setAt + 700))
        XCTAssertTrue(anchor.isExpired(at: setAt + 901))
    }

    func testAnchorStoreClearsOnBandMismatchAndExpiry() {
        let store = AnchorStore()
        store.declare(frequencyKHz: 14_062.5, band: "20m")
        XCTAssertNotNil(store.activeAnchor(band: "20m"))
        XCTAssertNil(store.activeAnchor(band: "40m"))
        let later = Date() + BandScopeTunables.anchorAutoClearSeconds + 1
        XCTAssertNil(store.activeAnchor(band: "20m", now: later))
    }

    // MARK: - Freshness fade (§7)

    func testFreshnessFadeEndpointsAndFloor() {
        XCTAssertEqual(FreshnessFade.opacity(ageSeconds: 0), 1.0)
        XCTAssertEqual(FreshnessFade.opacity(ageSeconds: 120), 1.0)
        // Midpoint of the fade window.
        XCTAssertEqual(FreshnessFade.opacity(ageSeconds: 960), 0.7, accuracy: 0.001)
        XCTAssertEqual(FreshnessFade.opacity(ageSeconds: 1_800), 0.4)
        XCTAssertEqual(FreshnessFade.opacity(ageSeconds: 90_000), 0.4)
    }

    // MARK: - Tier assignment (§2)

    func testTierPrecedence() {
        var needed = spot(id: "a", callsign: "JA1ABC", freqKHz: 14_040.0, source: .rbn)
        needed.matchedNeeds = [
            MatchedNeed(
                category: .dxccEntity(entity: "JA"), label: "NEW DXCC", priority: .high
            ),
        ]
        XCTAssertEqual(needed.tier(for: .everything), .needed)

        let human = spot(id: "b", callsign: "W1AW", freqKHz: 14_041.0, source: .pota)
        XCTAssertEqual(human.tier(for: .everything), .pota)

        let skimmer = spot(id: "c", callsign: "K6XYZ", freqKHz: 14_042.0, source: .rbn)
        XCTAssertEqual(skimmer.tier(for: .everything), .rbn)
    }

    func testProfileSelectsNeedCategories() {
        var spot = spot(id: "a", callsign: "JA1ABC", freqKHz: 14_040.0, source: .pota)
        spot.matchedNeeds = [
            MatchedNeed(
                category: .dxccEntity(entity: "JA"), label: "NEW DXCC", priority: .high
            ),
        ]
        // The Parks profile tracks park goals only — a DXCC need must not
        // light amber there (§16: one config, one answer).
        XCTAssertEqual(spot.tier(for: .parks), .pota)
        XCTAssertEqual(spot.tier(for: .dxcc), .needed)
        XCTAssertNil(spot.goalChip(for: .parks))
        XCTAssertEqual(spot.goalChip(for: .dxcc)?.label, "NEW DXCC")
    }

    // MARK: Private

    // MARK: - Helpers

    private func spot(
        id: String,
        callsign: String,
        freqKHz: Double,
        source: SpotSource = .rbn,
        timestamp: Date = Date()
    ) -> EnrichedSpot {
        EnrichedSpot(
            spot: UnifiedSpot(
                id: id,
                callsign: callsign,
                frequencyKHz: freqKHz,
                mode: "CW",
                timestamp: timestamp,
                source: source,
                snr: source == .rbn ? 20 : nil,
                wpm: source == .rbn ? 22 : nil,
                spotter: nil,
                spotterGrid: nil,
                callsignGrid: nil,
                parkRef: nil,
                parkName: nil,
                comments: nil,
                summitCode: nil,
                summitName: nil,
                summitPoints: nil,
                wwffRef: nil,
                wwffName: nil,
                locationDesc: nil,
                stateAbbr: nil
            ),
            distanceMeters: nil,
            bearingDegrees: nil,
            region: .other
        )
    }
}
