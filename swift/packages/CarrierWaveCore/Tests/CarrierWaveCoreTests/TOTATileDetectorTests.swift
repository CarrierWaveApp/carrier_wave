//
//  TOTATileDetectorTests.swift
//  CarrierWaveCoreTests
//

import Foundation
import Testing
@testable import CarrierWaveCore

struct TOTATileDetectorTests {
    // MARK: Internal

    @Test("Single-tile track + QSOs → 1 activated, 0 candidates")
    func singleTile() {
        let base = makeDate()
        // ATL-area: 33.79906, -84.13401 → EM73wt
        let track = (0 ..< 5).map { i in
            TilePathSample(
                timestamp: base.addingTimeInterval(Double(i) * 60),
                latitude: 33.79906,
                longitude: -84.13401
            )
        }
        let qsoTimes = [
            base.addingTimeInterval(60),
            base.addingTimeInterval(180),
        ]
        let result = TOTATileDetector.detect(
            track: track,
            qsoTimestamps: qsoTimes,
            activationCoord: (33.79906, -84.13401)
        )
        #expect(result.activated.count == 1)
        #expect(result.candidates.isEmpty)
    }

    @Test("Cross-boundary: QSOs in two tiles → both activated")
    func crossBoundaryBothActivated() {
        let base = makeDate()
        // Two distant points, definitely in different 6-char tiles.
        // Atlanta (~EM73) and Birmingham (~EM63).
        let track = [
            TilePathSample(timestamp: base, latitude: 33.79906, longitude: -84.13401),
            TilePathSample(timestamp: base.addingTimeInterval(3_600), latitude: 33.5186, longitude: -86.8104),
        ]
        let qsoTimes = [
            base.addingTimeInterval(60), // near start (EM73…)
            base.addingTimeInterval(3_540), // near end (EM63…)
        ]
        let result = TOTATileDetector.detect(
            track: track,
            qsoTimestamps: qsoTimes,
            activationCoord: nil
        )
        #expect(result.activated.count >= 2)
    }

    @Test("Track passes through tile but no QSO → candidate, not activated")
    func candidateWithoutQSO() {
        let base = makeDate()
        // Track samples in 3 different tiles; QSOs only at start and end
        let track = [
            TilePathSample(timestamp: base, latitude: 33.79906, longitude: -84.13401),
            TilePathSample(timestamp: base.addingTimeInterval(1_800), latitude: 33.5186, longitude: -86.8104),
            TilePathSample(timestamp: base.addingTimeInterval(3_600), latitude: 33.4484, longitude: -88.0000),
        ]
        // QSO only at start
        let qsoTimes = [base.addingTimeInterval(10)]
        let result = TOTATileDetector.detect(
            track: track,
            qsoTimestamps: qsoTimes,
            activationCoord: nil
        )
        #expect(result.activated.count == 1)
        #expect(!result.candidates.isEmpty)
    }

    @Test("QSO timestamp outside track range is ignored for tile-anchoring")
    func qsoOutsideTrack() {
        let base = makeDate()
        let track = [
            TilePathSample(timestamp: base, latitude: 33.79906, longitude: -84.13401),
            TilePathSample(
                timestamp: base.addingTimeInterval(60),
                latitude: 33.79906,
                longitude: -84.13401
            ),
        ]
        let qsoTimes = [base.addingTimeInterval(-3_600)] // before track started
        let result = TOTATileDetector.detect(
            track: track,
            qsoTimestamps: qsoTimes,
            activationCoord: nil
        )
        // Only track-touched tile, no QSO-anchored
        #expect(result.activated.isEmpty)
        #expect(result.candidates.count == 1)
    }

    @Test("No track but activation coord → 1 activated tile")
    func noTrackButActivationCoord() {
        let result = TOTATileDetector.detect(
            track: [],
            qsoTimestamps: [],
            activationCoord: (33.79906, -84.13401)
        )
        #expect(result.activated.count == 1)
        #expect(result.candidates.isEmpty)
    }

    @Test("No track + no activation coord → empty")
    func emptyInputs() {
        let result = TOTATileDetector.detect(
            track: [],
            qsoTimestamps: [Date()],
            activationCoord: nil
        )
        #expect(result.activated.isEmpty)
        #expect(result.candidates.isEmpty)
    }

    @Test("Activation coord tile always included even when track is elsewhere")
    func activationCoordAlwaysIncluded() {
        let base = makeDate()
        let track = [
            TilePathSample(timestamp: base, latitude: 0, longitude: 0),
            TilePathSample(timestamp: base.addingTimeInterval(60), latitude: 0, longitude: 0),
        ]
        let result = TOTATileDetector.detect(
            track: track,
            qsoTimestamps: [base.addingTimeInterval(30)],
            activationCoord: (33.79906, -84.13401)
        )
        // Should contain both the activation-coord tile (~EM73wt) and the
        // QSO-anchored tile near (0,0) (~JJ00aa).
        #expect(result.activated.count == 2)
    }

    @Test("Interpolation between samples picks midpoint position")
    func interpolationPicksMidpoint() {
        let base = makeDate()
        let track = [
            TilePathSample(timestamp: base, latitude: 33.0, longitude: -84.0),
            TilePathSample(timestamp: base.addingTimeInterval(100), latitude: 34.0, longitude: -84.0),
        ]
        let mid = TOTATileDetector.interpolatedSample(
            in: track,
            at: base.addingTimeInterval(50)
        )
        #expect(mid != nil)
        #expect(abs((mid?.latitude ?? 0) - 33.5) < 0.01)
    }

    // MARK: Private

    private func makeDate() -> Date {
        Date(timeIntervalSince1970: 1_700_000_000)
    }
}
