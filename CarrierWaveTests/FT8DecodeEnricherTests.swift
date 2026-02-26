import CarrierWaveCore
import XCTest
@testable import CarrierWave

final class FT8DecodeEnricherTests: XCTestCase {
    @MainActor
    func testEnrichCQDecode_PopulatesEntityAndDistance() {
        let enricher = FT8DecodeEnricher(
            myCallsign: "K1ABC",
            myGrid: "FN31",
            currentBand: "20m"
        )
        let decode = FT8DecodeResult(
            message: .cq(call: "W1AW", grid: "FN31", modifier: nil),
            snr: -12,
            deltaTime: 0.1,
            frequency: 1_500,
            rawText: "CQ W1AW FN31"
        )
        let results = enricher.enrich([decode])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].section, .callingCQ)
        XCTAssertEqual(results[0].dxccEntity, "United States")
        XCTAssertNotNil(results[0].distanceMiles)
    }

    @MainActor
    func testEnrichDirectedMessage_MarksDirectedAtMe() {
        let enricher = FT8DecodeEnricher(
            myCallsign: "K1ABC",
            myGrid: "FN31",
            currentBand: "20m"
        )
        let decode = FT8DecodeResult(
            message: .signalReport(from: "JA1XYZ", to: "K1ABC", dB: -15),
            snr: -15,
            deltaTime: 0.0,
            frequency: 800,
            rawText: "K1ABC JA1XYZ -15"
        )
        let results = enricher.enrich([decode])
        XCTAssertTrue(results[0].isDirectedAtMe)
        XCTAssertEqual(results[0].section, .directedAtYou)
    }

    @MainActor
    func testEnrichDupe_MarksDuplicateSession() {
        let enricher = FT8DecodeEnricher(
            myCallsign: "K1ABC",
            myGrid: "FN31",
            currentBand: "20m"
        )
        enricher.markWorkedThisSession("W1AW")
        let decode = FT8DecodeResult(
            message: .cq(call: "W1AW", grid: "FN31", modifier: nil),
            snr: -12,
            deltaTime: 0.1,
            frequency: 1_500,
            rawText: "CQ W1AW FN31"
        )
        let results = enricher.enrich([decode])
        XCTAssertTrue(results[0].isDupe)
    }

    @MainActor
    func testEnrichNewDXCC_WhenEntityNotInWorkedSet() {
        let enricher = FT8DecodeEnricher(
            myCallsign: "K1ABC",
            myGrid: "FN31",
            currentBand: "20m"
        )
        enricher.loadWorkedHistory(
            dxccEntities: ["United States"],
            grids: [],
            callBandCombos: []
        )
        let decode = FT8DecodeResult(
            message: .cq(call: "JA1XYZ", grid: "PM95", modifier: nil),
            snr: -10,
            deltaTime: 0.0,
            frequency: 1_000,
            rawText: "CQ JA1XYZ PM95"
        )
        let results = enricher.enrich([decode])
        XCTAssertTrue(results[0].isNewDXCC) // Japan not in worked set
    }

    @MainActor
    func testEnrichNotNewDXCC_WhenEntityAlreadyWorked() {
        let enricher = FT8DecodeEnricher(
            myCallsign: "K1ABC",
            myGrid: "FN31",
            currentBand: "20m"
        )
        enricher.loadWorkedHistory(
            dxccEntities: ["United States"],
            grids: [],
            callBandCombos: []
        )
        let decode = FT8DecodeResult(
            message: .cq(call: "W1AW", grid: "FN31", modifier: nil),
            snr: -12,
            deltaTime: 0.1,
            frequency: 1_500,
            rawText: "CQ W1AW FN31"
        )
        let results = enricher.enrich([decode])
        XCTAssertFalse(results[0].isNewDXCC)
    }

    @MainActor
    func testEnrichNonCQ_ClassifiesAsAllActivity() {
        let enricher = FT8DecodeEnricher(
            myCallsign: "K1ABC",
            myGrid: "FN31",
            currentBand: "20m"
        )
        let decode = FT8DecodeResult(
            message: .rogerReport(from: "W3LPL", to: "K1TTT", dB: -5),
            snr: -5,
            deltaTime: 0.0,
            frequency: 1_200,
            rawText: "K1TTT W3LPL R-05"
        )
        let results = enricher.enrich([decode])
        XCTAssertEqual(results[0].section, .allActivity)
        XCTAssertFalse(results[0].isDirectedAtMe)
    }

    @MainActor
    func testUnknownEntityReturnsNil() {
        let enricher = FT8DecodeEnricher(
            myCallsign: "K1ABC",
            myGrid: "FN31",
            currentBand: "20m"
        )
        // Free text doesn't have a callsign
        let decode = FT8DecodeResult(
            message: .freeText("HELLO WORLD"),
            snr: -20,
            deltaTime: 0.0,
            frequency: 1_000,
            rawText: "HELLO WORLD"
        )
        let results = enricher.enrich([decode])
        XCTAssertNil(results[0].dxccEntity)
        XCTAssertNil(results[0].distanceMiles)
    }
}
