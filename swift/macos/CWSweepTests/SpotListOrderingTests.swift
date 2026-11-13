import CarrierWaveCore
import Foundation
import Testing
@testable import CWSweep

// MARK: - Helpers

private func makeSpot(_ callsign: String, id: Int, minutesAgo: Double, frequency: Double = 14_030.0) -> EnrichedSpot {
    let rbn = RBNSpot(
        id: id,
        callsign: callsign,
        frequency: frequency,
        mode: "CW",
        timestamp: Date().addingTimeInterval(-minutesAgo * 60),
        snr: 20,
        wpm: 20,
        spotter: "VE7CC",
        spotterGrid: "CN89"
    )
    return EnrichedSpot(spot: UnifiedSpot.from(rbn: rbn), distanceMeters: nil, bearingDegrees: nil, region: .neUS)
}

private let callsignSort = [KeyPathComparator(\EnrichedSpot.sortCallsign)]

// MARK: - SpotListOrdering Tests

@Test func selfSpotDetectionIgnoresCaseAndPortableSuffix() {
    let spot = makeSpot("k6abc/p", id: 1, minutesAgo: 1)
    #expect(SpotListOrdering.isSelfSpot(spot, userCallsign: "K6ABC"))
    #expect(SpotListOrdering.isSelfSpot(spot, userCallsign: " k6abc "))
    #expect(!SpotListOrdering.isSelfSpot(spot, userCallsign: "K6ABD"))
}

@Test func emptyCallsignNeverMatches() {
    let spot = makeSpot("K6ABC", id: 1, minutesAgo: 1)
    #expect(!SpotListOrdering.isSelfSpot(spot, userCallsign: ""))
    #expect(!SpotListOrdering.isSelfSpot(spot, userCallsign: "   "))
}

@Test func defaultSortDetection() {
    #expect(SpotListOrdering.isDefaultSort(SpotListOrdering.defaultSortOrder))
    #expect(SpotListOrdering.isDefaultSort([KeyPathComparator(\EnrichedSpot.sortTimestamp, order: .reverse)]))
    #expect(!SpotListOrdering.isDefaultSort([KeyPathComparator(\EnrichedSpot.sortTimestamp, order: .forward)]))
    #expect(!SpotListOrdering.isDefaultSort(callsignSort))
    #expect(!SpotListOrdering.isDefaultSort([]))
}

@Test func pinsSelfSpotsToTopUnderDefaultSortPreservingRelativeOrder() {
    // Newest-first, as the list would already be sorted.
    let spots = [
        makeSpot("W1AW", id: 1, minutesAgo: 1),
        makeSpot("K6ABC", id: 2, minutesAgo: 2, frequency: 14_030.0),
        makeSpot("DL1ABC", id: 3, minutesAgo: 3),
        makeSpot("K6ABC/P", id: 4, minutesAgo: 4, frequency: 7_030.0),
        makeSpot("JA1ABC", id: 5, minutesAgo: 5),
    ]
    let pinned = SpotListOrdering.pinningSelfSpots(
        spots,
        userCallsign: "K6ABC",
        sortOrder: SpotListOrdering.defaultSortOrder
    )
    #expect(pinned.map(\.spot.callsign) == ["K6ABC", "K6ABC/P", "W1AW", "DL1ABC", "JA1ABC"])
    #expect(pinned.count == spots.count)
}

@Test func doesNotPinWhenUserChoseAnotherSort() {
    let spots = [
        makeSpot("W1AW", id: 1, minutesAgo: 1),
        makeSpot("K6ABC", id: 2, minutesAgo: 2),
    ]
    let result = SpotListOrdering.pinningSelfSpots(spots, userCallsign: "K6ABC", sortOrder: callsignSort)
    #expect(result.map(\.spot.callsign) == ["W1AW", "K6ABC"])
}

@Test func doesNotPinWithoutConfiguredCallsign() {
    let spots = [
        makeSpot("W1AW", id: 1, minutesAgo: 1),
        makeSpot("K6ABC", id: 2, minutesAgo: 2),
    ]
    let result = SpotListOrdering.pinningSelfSpots(
        spots,
        userCallsign: "",
        sortOrder: SpotListOrdering.defaultSortOrder
    )
    #expect(result.map(\.spot.callsign) == ["W1AW", "K6ABC"])
}

@Test func pinningIsNoOpWhenNoSelfSpotPresent() {
    let spots = [
        makeSpot("W1AW", id: 1, minutesAgo: 1),
        makeSpot("DL1ABC", id: 2, minutesAgo: 2),
    ]
    let result = SpotListOrdering.pinningSelfSpots(
        spots,
        userCallsign: "K6ABC",
        sortOrder: SpotListOrdering.defaultSortOrder
    )
    #expect(result.map(\.spot.callsign) == ["W1AW", "DL1ABC"])
}
