import CarrierWaveCore
import Foundation
import Testing
@testable import CWSweep

// MARK: - UnifiedSpot Tests

@Test func unifiedSpotFromRBN() {
    let rbn = RBNSpot(
        id: 1,
        callsign: "W1AW",
        frequency: 14_030.0,
        mode: "CW",
        timestamp: Date(),
        snr: 25,
        wpm: 18,
        spotter: "VE7CC",
        spotterGrid: "CN89"
    )
    let unified = UnifiedSpot.from(rbn: rbn)
    #expect(unified.callsign == "W1AW")
    #expect(unified.source == .rbn)
    #expect(unified.frequencyKHz == 14_030.0)
    #expect(unified.snr == 25)
    #expect(unified.wpm == 18)
    #expect(unified.band == "20m")
    #expect(unified.id.hasPrefix("rbn-"))
}

@Test func unifiedSpotDedupKey() {
    let rbn = RBNSpot(
        id: 1,
        callsign: "w1aw",
        frequency: 14_030.0,
        mode: "CW",
        timestamp: Date(),
        snr: 25,
        wpm: 18,
        spotter: "VE7CC",
        spotterGrid: nil
    )
    let unified = UnifiedSpot.from(rbn: rbn)
    #expect(unified.dedupKey == "W1AW-20m")
}

@Test func unifiedSpotIsSelfSpot() {
    let rbn = RBNSpot(
        id: 1,
        callsign: "W1AW/P",
        frequency: 14_030.0,
        mode: "CW",
        timestamp: Date(),
        snr: 25,
        wpm: nil,
        spotter: "N1MM",
        spotterGrid: nil
    )
    let unified = UnifiedSpot.from(rbn: rbn)
    #expect(unified.isSelfSpot(userCallsign: "W1AW") == true)
    #expect(unified.isSelfSpot(userCallsign: "W2AW") == false)
}

@Test func unifiedSpotTimeAgo() {
    let spot = UnifiedSpot(
        id: "test",
        callsign: "W1AW",
        frequencyKHz: 14_030,
        mode: "CW",
        timestamp: Date().addingTimeInterval(-90),
        source: .rbn,
        snr: nil,
        wpm: nil,
        spotter: nil,
        spotterGrid: nil,
        parkRef: nil,
        parkName: nil,
        comments: nil,
        locationDesc: nil
    )
    #expect(spot.timeAgo == "1m ago")
}

// MARK: - SpotRegion Tests

@Test func spotRegionFromGrid() {
    // FN42 is in northeastern US
    let region = SpotRegion.from(grid: "FN42")
    #expect(region == .neUS || region.group == .us)
}

@Test func spotRegionFromNilGrid() {
    #expect(SpotRegion.from(grid: nil) == .other)
}

@Test func spotRegionFromShortGrid() {
    #expect(SpotRegion.from(grid: "A") == .other)
}

@Test func spotRegionGroupMapping() {
    #expect(SpotRegion.neUS.group == .us)
    #expect(SpotRegion.seUS.group == .us)
    #expect(SpotRegion.mwUS.group == .us)
    #expect(SpotRegion.swUS.group == .us)
    #expect(SpotRegion.nwUS.group == .us)
    #expect(SpotRegion.canada.group == .canada)
    #expect(SpotRegion.europe.group == .europe)
    #expect(SpotRegion.asia.group == .asia)
}

// MARK: - POTASpot Tests

@Test func potaSpotParseState() {
    #expect(POTASpot.parseState(from: "US-CO") == "CO")
    #expect(POTASpot.parseState(from: "US-CA") == "CA")
    #expect(POTASpot.parseState(from: nil) == nil)
    #expect(POTASpot.parseState(from: "VE-ON") == nil) // Non-US
}

// MARK: - SpotSource Tests

@Test func spotSourceDisplayNames() {
    #expect(SpotSource.rbn.displayName == "RBN")
    #expect(SpotSource.pota.displayName == "POTA")
    #expect(SpotSource.sota.displayName == "SOTA")
    #expect(SpotSource.wwff.displayName == "WWFF")
    #expect(SpotSource.cluster.displayName == "Cluster")
}

@Test func spotSourceAllCases() {
    #expect(SpotSource.allCases.count == 5)
}

// MARK: - EnrichedSpot Tests

@Test func enrichedSpotDistance() throws {
    let spot = UnifiedSpot(
        id: "test",
        callsign: "W1AW",
        frequencyKHz: 14_030,
        mode: "CW",
        timestamp: Date(),
        source: .rbn,
        snr: nil,
        wpm: nil,
        spotter: nil,
        spotterGrid: nil,
        parkRef: nil,
        parkName: nil,
        comments: nil,
        locationDesc: nil
    )
    let enriched = EnrichedSpot(spot: spot, distanceMeters: 1_609.344, bearingDegrees: nil, region: .neUS)
    #expect(enriched.distanceMiles == 1.0)
    #expect(try #require(enriched.distanceKm) - 1.609 < 0.001)
}

@Test func enrichedSpotFormattedDistanceMetric() {
    // Force metric for deterministic test
    UserDefaults.standard.set(true, forKey: "useMetricUnits")
    defer { UserDefaults.standard.removeObject(forKey: "useMetricUnits") }

    let spot = UnifiedSpot(
        id: "test",
        callsign: "W1AW",
        frequencyKHz: 14_030,
        mode: "CW",
        timestamp: Date(),
        source: .rbn,
        snr: nil,
        wpm: nil,
        spotter: nil,
        spotterGrid: nil,
        parkRef: nil,
        parkName: nil,
        comments: nil,
        locationDesc: nil
    )

    let nearby = EnrichedSpot(spot: spot, distanceMeters: 50_000, bearingDegrees: nil, region: .neUS)
    #expect(nearby.formattedDistance() == "50 km")

    let far = EnrichedSpot(spot: spot, distanceMeters: 5_000_000, bearingDegrees: nil, region: .europe)
    #expect(far.formattedDistance() == "5000 km")

    let noDistance = EnrichedSpot(spot: spot, distanceMeters: nil, bearingDegrees: nil, region: .other)
    #expect(noDistance.formattedDistance() == nil)
}

@Test func enrichedSpotFormattedDistanceImperial() {
    // Force imperial for deterministic test
    UserDefaults.standard.set(false, forKey: "useMetricUnits")
    defer { UserDefaults.standard.removeObject(forKey: "useMetricUnits") }

    let spot = UnifiedSpot(
        id: "test",
        callsign: "W1AW",
        frequencyKHz: 14_030,
        mode: "CW",
        timestamp: Date(),
        source: .rbn,
        snr: nil,
        wpm: nil,
        spotter: nil,
        spotterGrid: nil,
        parkRef: nil,
        parkName: nil,
        comments: nil,
        locationDesc: nil
    )

    let nearby = EnrichedSpot(spot: spot, distanceMeters: 50_000, bearingDegrees: nil, region: .neUS)
    #expect(nearby.formattedDistance() == "31 mi")

    let far = EnrichedSpot(spot: spot, distanceMeters: 5_000_000, bearingDegrees: nil, region: .europe)
    #expect(far.formattedDistance() == "3107 mi")
}
