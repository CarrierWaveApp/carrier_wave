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
}
