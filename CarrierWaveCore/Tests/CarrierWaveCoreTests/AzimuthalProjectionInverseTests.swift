//
//  AzimuthalProjectionInverseTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("Azimuthal Projection Inverse Tests")
struct AzimuthalProjectionInverseTests {
    // MARK: Internal

    // MARK: - Round-Trip Tests

    @Test("Center point round-trips exactly")
    func centerRoundTrip() throws {
        let proj = AzimuthalProjection(centerLatDeg: 47.6, centerLonDeg: -122.3)
        let result = proj.inverseProject(nx: 0, ny: 0)
        #expect(result != nil)
        #expect(try abs(#require(result?.latDeg) - 47.6) < 1e-10)
        #expect(try abs(#require(result?.lonDeg) - -122.3) < 1e-10)
    }

    @Test("Forward then inverse round-trip for known locations")
    func forwardInverseRoundTrip() {
        let proj = AzimuthalProjection(centerLatDeg: 47.6, centerLonDeg: -122.3)

        let testCases: [LocationCase] = [
            .init(lat: 48.15, lon: -122.68, name: "FN31 - NE USA area"),
            .init(lat: 52.52, lon: 13.41, name: "JO22 - Berlin"),
            .init(lat: 35.68, lon: 139.69, name: "Tokyo"),
            .init(lat: -33.87, lon: 151.21, name: "Sydney"),
            .init(lat: 0.0, lon: 0.0, name: "Null Island"),
            .init(lat: -45.0, lon: 170.0, name: "New Zealand"),
        ]

        for tc in testCases {
            guard let fwd = proj.project(latDeg: tc.lat, lonDeg: tc.lon) else {
                Issue.record("Forward projection failed for \(tc.name)")
                continue
            }
            guard let inv = proj.inverseProject(nx: fwd.x, ny: fwd.y) else {
                Issue.record("Inverse projection failed for \(tc.name)")
                continue
            }
            #expect(
                abs(inv.latDeg - tc.lat) < 0.01,
                "Latitude mismatch for \(tc.name): got \(inv.latDeg), expected \(tc.lat)"
            )
            var lonDiff = abs(inv.lonDeg - tc.lon)
            if lonDiff > 180 {
                lonDiff = 360 - lonDiff
            }
            #expect(
                lonDiff < 0.01,
                "Longitude mismatch for \(tc.name): got \(inv.lonDeg), expected \(tc.lon)"
            )
        }
    }

    // MARK: - Edge Cases

    @Test("Points outside unit circle return nil")
    func outsideUnitCircle() {
        let proj = AzimuthalProjection(centerLatDeg: 47.6, centerLonDeg: -122.3)
        // Beyond antipodal distance (nx² + ny² > 1)
        #expect(proj.inverseProject(nx: 1.1, ny: 0) == nil)
        #expect(proj.inverseProject(nx: 0, ny: 1.1) == nil)
        #expect(proj.inverseProject(nx: 0.8, ny: 0.8) == nil) // sqrt(1.28) > 1
    }

    @Test("Near-antipodal points still project")
    func nearAntipodal() {
        let proj = AzimuthalProjection(centerLatDeg: 47.6, centerLonDeg: -122.3)
        // Just inside the boundary (radius ≈ 0.99)
        let result = proj.inverseProject(nx: 0.0, ny: -0.99)
        #expect(result != nil)
    }

    // MARK: - Various Center Points

    @Test("Equator center round-trip")
    func equatorCenter() {
        let proj = AzimuthalProjection(centerLatDeg: 0.0, centerLonDeg: 0.0)
        guard let fwd = proj.project(latDeg: 45.0, lonDeg: 90.0) else {
            Issue.record("Forward projection failed")
            return
        }
        guard let inv = proj.inverseProject(nx: fwd.x, ny: fwd.y) else {
            Issue.record("Inverse projection failed")
            return
        }
        #expect(abs(inv.latDeg - 45.0) < 0.01)
        #expect(abs(inv.lonDeg - 90.0) < 0.01)
    }

    @Test("North pole center round-trip")
    func northPoleCenter() {
        let proj = AzimuthalProjection(centerLatDeg: 90.0, centerLonDeg: 0.0)
        guard let fwd = proj.project(latDeg: 45.0, lonDeg: -90.0) else {
            Issue.record("Forward projection failed")
            return
        }
        guard let inv = proj.inverseProject(nx: fwd.x, ny: fwd.y) else {
            Issue.record("Inverse projection failed")
            return
        }
        #expect(abs(inv.latDeg - 45.0) < 0.01)
        var lonDiff = abs(inv.lonDeg - -90.0)
        if lonDiff > 180 {
            lonDiff = 360 - lonDiff
        }
        #expect(lonDiff < 0.01)
    }

    @Test("South pole center round-trip")
    func southPoleCenter() {
        let proj = AzimuthalProjection(centerLatDeg: -90.0, centerLonDeg: 0.0)
        guard let fwd = proj.project(latDeg: -45.0, lonDeg: 120.0) else {
            Issue.record("Forward projection failed")
            return
        }
        guard let inv = proj.inverseProject(nx: fwd.x, ny: fwd.y) else {
            Issue.record("Inverse projection failed")
            return
        }
        #expect(abs(inv.latDeg - -45.0) < 0.01)
        var lonDiff = abs(inv.lonDeg - 120.0)
        if lonDiff > 180 {
            lonDiff = 360 - lonDiff
        }
        #expect(lonDiff < 0.01)
    }

    // MARK: Private

    private struct LocationCase {
        let lat: Double
        let lon: Double
        let name: String
    }
}
