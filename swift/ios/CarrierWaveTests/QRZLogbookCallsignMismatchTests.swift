import XCTest
@testable import CarrierWave

/// The QRZ settings notice for operators whose callsign has no connected QRZ
/// logbook key. Pins the pure `QRZClient.logbookMismatch(currentCallsign:mappings:)`
/// rule the notice and the Logbook Services row are driven by.
@MainActor
final class QRZLogbookCallsignMismatchTests: XCTestCase {
    // MARK: Internal

    func testNoMismatchWhenCurrentCallsignHasPrimaryKey() {
        let mappings = [mapping("W1NEW", primary: true)]
        XCTAssertNil(QRZClient.logbookMismatch(currentCallsign: "W1NEW", mappings: mappings))
    }

    func testNoMismatchWhenCurrentCallsignHasSecondaryKey() {
        let mappings = [mapping("W1OLD", primary: true), mapping("W1NEW", primary: false)]
        XCTAssertNil(QRZClient.logbookMismatch(currentCallsign: "W1NEW", mappings: mappings))
    }

    func testMismatchNamesPrimaryLogbookCallsign() {
        let mappings = [mapping("K2AAA", primary: false), mapping("W1OLD", primary: true)]
        let mismatch = QRZClient.logbookMismatch(currentCallsign: "W1NEW", mappings: mappings)
        XCTAssertEqual(
            mismatch,
            QRZLogbookCallsignMismatch(currentCallsign: "W1NEW", logbookCallsign: "W1OLD")
        )
    }

    func testMismatchFallsBackToFirstMappingWithoutPrimary() {
        let mappings = [mapping("K2AAA", primary: false), mapping("W1OLD", primary: false)]
        let mismatch = QRZClient.logbookMismatch(currentCallsign: "W1NEW", mappings: mappings)
        XCTAssertEqual(mismatch?.logbookCallsign, "K2AAA")
    }

    func testCurrentCallsignIsNormalizedBeforeComparing() {
        let mappings = [mapping("W1NEW", primary: true)]
        XCTAssertNil(QRZClient.logbookMismatch(currentCallsign: " w1new\n", mappings: mappings))

        let mismatch = QRZClient.logbookMismatch(currentCallsign: "w1old", mappings: mappings)
        XCTAssertEqual(mismatch?.currentCallsign, "W1OLD")
    }

    func testPortableSuffixMatchesBaseCallsignKey() {
        let mappings = [mapping("W1NEW", primary: true)]
        XCTAssertNil(QRZClient.logbookMismatch(currentCallsign: "W1NEW/P", mappings: mappings))
        XCTAssertNil(QRZClient.logbookMismatch(currentCallsign: "W1NEW/M", mappings: mappings))
    }

    func testNoMismatchWithoutCallsignOrWithoutKeys() {
        let mappings = [mapping("W1OLD", primary: true)]
        XCTAssertNil(QRZClient.logbookMismatch(currentCallsign: nil, mappings: mappings))
        XCTAssertNil(QRZClient.logbookMismatch(currentCallsign: "", mappings: mappings))
        XCTAssertNil(QRZClient.logbookMismatch(currentCallsign: "   ", mappings: mappings))
        XCTAssertNil(QRZClient.logbookMismatch(currentCallsign: "W1NEW", mappings: []))
    }

    // MARK: Private

    private func mapping(_ callsign: String, primary: Bool) -> QRZCallsignMapping {
        QRZCallsignMapping(callsign: callsign, apiKey: "key-\(callsign)", bookId: nil, isPrimary: primary)
    }
}
