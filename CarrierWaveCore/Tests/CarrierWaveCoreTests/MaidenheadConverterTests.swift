//
//  MaidenheadConverterTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

// MARK: - MaidenheadConverterTests

@Suite("Maidenhead Converter Tests")
struct MaidenheadConverterTests {
    @Test("Convert 4-char grid to coordinate")
    func convert4CharGrid() {
        // FN31 center should be lat=41.5, lon=-73.0
        let coord = MaidenheadConverter.coordinate(from: "FN31")
        #expect(coord != nil)
        #expect(coord?.latitude == 41.5)
        #expect(coord?.longitude == -73.0)
    }

    @Test("Convert 6-char grid to coordinate")
    func convert6CharGrid() throws {
        // FN31PR is more precise - subsquare adds offset
        let coord = MaidenheadConverter.coordinate(from: "FN31PR")
        #expect(coord != nil)
        // Should be within FN31 bounds but more precise
        #expect(try #require(coord?.latitude) > 41 && coord!.latitude < 42)
        #expect(try #require(coord?.longitude) > -74 && coord!.longitude < -72)
    }

    @Test("Case insensitive")
    func caseInsensitive() {
        let upper = MaidenheadConverter.coordinate(from: "FN31PR")
        let lower = MaidenheadConverter.coordinate(from: "fn31pr")
        let mixed = MaidenheadConverter.coordinate(from: "Fn31Pr")

        #expect(upper != nil)
        #expect(lower != nil)
        #expect(mixed != nil)
        #expect(upper?.latitude == lower!.latitude)
        #expect(upper?.longitude == lower!.longitude)
        #expect(upper?.latitude == mixed!.latitude)
    }

    @Test("Invalid grids return nil")
    func invalidGridsReturnNil() {
        #expect(MaidenheadConverter.coordinate(from: "") == nil)
        #expect(MaidenheadConverter.coordinate(from: "A") == nil)
        #expect(MaidenheadConverter.coordinate(from: "FN3") == nil)
        #expect(MaidenheadConverter.coordinate(from: "ZZ99") == nil) // Z > R
        // Note: 5-char grids return center of 4-char grid (graceful degradation)
    }

    @Test("isValid helper works")
    func isValidHelperWorks() {
        #expect(MaidenheadConverter.isValid("FN31"))
        #expect(MaidenheadConverter.isValid("FN31PR"))
        #expect(!MaidenheadConverter.isValid(""))
        #expect(!MaidenheadConverter.isValid("ZZ99"))
    }

    @Test("Known grid square locations")
    func knownGridSquareLocations() {
        // CN87 is Seattle area - center at lat=47.5, lon=-123.0
        let seattle = MaidenheadConverter.coordinate(from: "CN87")
        #expect(seattle != nil)
        #expect(seattle?.latitude == 47.5)
        #expect(seattle?.longitude == -123.0)

        // JO22 is Netherlands/Germany area - center at lat=52.5, lon=5.0
        let amsterdam = MaidenheadConverter.coordinate(from: "JO22")
        #expect(amsterdam != nil)
        #expect(amsterdam?.latitude == 52.5)
        #expect(amsterdam?.longitude == 5.0)
    }

    // MARK: - grid(from:) Tests

    @Test("Convert coordinate to 6-char grid")
    func coordinateToGrid() {
        // Seattle area: CN87
        let grid = MaidenheadConverter.grid(
            from: Coordinate(latitude: 47.5, longitude: -123.0)
        )
        #expect(grid.count == 6)
        #expect(grid.hasPrefix("CN87"))
    }

    @Test("Convert coordinate to grid — known locations")
    func coordinateToGridKnownLocations() {
        // Amsterdam: JO22
        let amsterdam = MaidenheadConverter.grid(
            from: Coordinate(latitude: 52.5, longitude: 5.0)
        )
        #expect(amsterdam.hasPrefix("JO22"))

        // FN31 center
        let fn31 = MaidenheadConverter.grid(
            from: Coordinate(latitude: 41.5, longitude: -73.0)
        )
        #expect(fn31.hasPrefix("FN31"))
    }

    @Test(
        "Round-trip: grid → coordinate → grid returns same 6-char grid",
        arguments: ["CN87vq", "FN31pr", "JO22of", "EM73sb", "IO91wm", "AA00aa", "RR99xx"]
    )
    func roundTrip6Char(grid: String) {
        guard let coord = MaidenheadConverter.coordinate(from: grid) else {
            Issue.record("Failed to convert grid \(grid) to coordinate")
            return
        }
        let result = MaidenheadConverter.grid(from: coord)
        #expect(result.uppercased() == grid.uppercased())
    }

    @Test("Grid from edge coordinates")
    func gridFromEdgeCoordinates() {
        // South pole
        let southPole = MaidenheadConverter.grid(
            from: Coordinate(latitude: -89.9, longitude: 0.0)
        )
        #expect(southPole.count == 6)
        #expect(southPole.hasPrefix("JA"))

        // North pole
        let northPole = MaidenheadConverter.grid(
            from: Coordinate(latitude: 89.9, longitude: 0.0)
        )
        #expect(northPole.count == 6)
        #expect(northPole.hasPrefix("JR"))
    }
}

// MARK: - MaidenheadConverterDistanceTests

@Suite("MaidenheadConverter Distance Tests")
struct MaidenheadConverterDistanceTests {
    @Test("Distance FN31 to FN42 is approximately 150 km")
    func distanceFN31toFN42() throws {
        let dist = MaidenheadConverter.distanceKm(from: "FN31", to: "FN42")
        #expect(dist != nil)
        #expect(try #require(dist) > 100 && dist! < 200)
    }

    @Test("Distance FN31 to PM95 is approximately 10900 km (US to Japan)")
    func distanceFN31toPM95() throws {
        let dist = MaidenheadConverter.distanceKm(from: "FN31", to: "PM95")
        #expect(dist != nil)
        #expect(try #require(dist) > 10_000 && dist! < 12_000)
    }

    @Test("Distance with invalid grid returns nil")
    func distanceInvalidGrid() {
        let dist = MaidenheadConverter.distanceKm(from: "FN31", to: "ZZ99")
        #expect(dist == nil)
    }

    @Test("Bearing FN31 to PM95 is roughly northwest (280-340 degrees)")
    func bearingToJapan() throws {
        let brg = MaidenheadConverter.bearing(from: "FN31", to: "PM95")
        #expect(brg != nil)
        #expect(try #require(brg) > 280 && brg! < 340)
    }

    @Test("Distance in miles converts correctly")
    func distanceMiles() throws {
        let km = MaidenheadConverter.distanceKm(from: "FN31", to: "FN42")
        let mi = MaidenheadConverter.distanceMiles(from: "FN31", to: "FN42")
        #expect(km != nil && mi != nil)
        let ratio = try #require(mi) / km!
        #expect(ratio > 0.62 && ratio < 0.63)
    }
}
