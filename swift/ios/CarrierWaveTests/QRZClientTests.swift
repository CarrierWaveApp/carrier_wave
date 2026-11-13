import CarrierWaveData
import XCTest
@testable import CarrierWave

@MainActor
final class QRZClientTests: XCTestCase {
    func testParseLoginResponse() {
        let response = "RESULT=OK&KEY=abc123&COUNT=1"

        let result = QRZClient.parseResponse(response)

        XCTAssertEqual(result["RESULT"], "OK")
        XCTAssertEqual(result["KEY"], "abc123")
    }

    func testParseErrorResponse() {
        let response = "RESULT=FAIL&REASON=Invalid credentials"

        let result = QRZClient.parseResponse(response)

        XCTAssertEqual(result["RESULT"], "FAIL")
        XCTAssertEqual(result["REASON"], "Invalid credentials")
    }

    func testParseStatusResponse() {
        let response = "RESULT=OK&CALLSIGN=W1ABC&COUNT=1234&CONFIRMED=567"

        let result = QRZClient.parseResponse(response)

        XCTAssertEqual(result["RESULT"], "OK")
        XCTAssertEqual(result["CALLSIGN"], "W1ABC")
        XCTAssertEqual(result["COUNT"], "1234")
    }

    // MARK: - CAR-243: QRZ COMMENT field gated on notesUserAuthored

    /// User-authored notes flow into the QRZ ADIF COMMENT field.
    func testGenerateADIFIncludesCommentWhenUserAuthored() {
        let client = QRZClient()
        let qso = QSO(
            callsign: "W1AW",
            band: "20m",
            mode: "CW",
            timestamp: Date(),
            myCallsign: "N0TEST",
            notes: "Great QSO at the park",
            notesUserAuthored: true,
            importSource: .logger
        )

        let adif = client.generateADIF(for: qso)

        XCTAssertTrue(
            adif.lowercased().contains("<comment:"),
            "User-authored notes must produce a COMMENT field. ADIF: \(adif)"
        )
        XCTAssertTrue(adif.contains("Great QSO at the park"))
    }

    /// Notes that arrived externally (sync/import) are not pushed to QRZ.
    func testGenerateADIFOmitsCommentWhenNotUserAuthored() {
        let client = QRZClient()
        let qso = QSO(
            callsign: "W1AW",
            band: "20m",
            mode: "CW",
            timestamp: Date(),
            myCallsign: "N0TEST",
            notes: "OP: Alice", // simulating auto-fill from external source
            notesUserAuthored: false,
            importSource: .lofi
        )

        let adif = client.generateADIF(for: qso)

        XCTAssertFalse(
            adif.lowercased().contains("<comment:"),
            "External-source notes must NOT produce a COMMENT field. ADIF: \(adif)"
        )
        XCTAssertFalse(adif.contains("OP: Alice"))
    }

    /// stripCommentField removes a `<comment:N>VALUE` block from an ADIF record.
    func testStripCommentFieldRemovesCommentBlock() {
        let input = "<call:4>W1AW <band:3>20m <mode:2>CW <comment:9>OP: Alice <eor>"

        let stripped = QRZClient.stripCommentField(from: input)

        XCTAssertFalse(stripped.lowercased().contains("<comment:"))
        XCTAssertFalse(stripped.contains("OP: Alice"))
        XCTAssertTrue(stripped.contains("<call:4>W1AW"))
        XCTAssertTrue(stripped.contains("<band:3>20m"))
        XCTAssertTrue(stripped.contains("<eor>"))
    }

    /// stripCommentField leaves records without a COMMENT field untouched.
    func testStripCommentFieldNoOpWhenAbsent() {
        let input = "<call:4>W1AW <band:3>20m <mode:2>CW <eor>"

        let stripped = QRZClient.stripCommentField(from: input)

        XCTAssertEqual(stripped, input)
    }

    /// Case-insensitive on the tag name.
    func testStripCommentFieldCaseInsensitive() {
        let input = "<CALL:4>W1AW <COMMENT:9>OP: Alice <EOR>"

        let stripped = QRZClient.stripCommentField(from: input)

        XCTAssertFalse(stripped.uppercased().contains("<COMMENT:"))
        XCTAssertFalse(stripped.contains("OP: Alice"))
    }
}
