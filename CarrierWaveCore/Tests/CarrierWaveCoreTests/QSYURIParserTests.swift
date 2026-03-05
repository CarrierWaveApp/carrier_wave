@testable import CarrierWaveCore
import XCTest

final class QSYURIParserTests: XCTestCase {
    // MARK: - Scheme Validation

    func testNonQSYScheme_ReturnsNil() {
        let url = URL(string: "https://example.com/spot?callsign=W1AW&freq=14074000")!
        XCTAssertNil(QSYURIParser.parse(url))
    }

    func testQSYScheme_CaseInsensitive() {
        let url = URL(string: "QSY://spot?callsign=W1AW&freq=14074000")!
        XCTAssertNotNil(QSYURIParser.parse(url))
    }

    func testUnknownAction_ReturnsNil() {
        let url = URL(string: "qsy://foobar?callsign=W1AW")!
        XCTAssertNil(QSYURIParser.parse(url))
    }

    // MARK: - Spot Action

    func testSpot_BasicRequired() {
        let url = URL(string: "qsy://spot?callsign=W1AW&freq=14074000")!
        guard case let .spot(params) = QSYURIParser.parse(url) else {
            XCTFail("Expected spot action")
            return
        }
        XCTAssertEqual(params.callsign, "W1AW")
        XCTAssertEqual(params.frequencyHz, 14_074_000)
        XCTAssertEqual(params.frequencyMHz, 14.074, accuracy: 0.0001)
        XCTAssertNil(params.mode)
    }

    func testSpot_MissingCallsign_ReturnsNil() {
        let url = URL(string: "qsy://spot?freq=14074000")!
        XCTAssertNil(QSYURIParser.parse(url))
    }

    func testSpot_MissingFreq_ReturnsNil() {
        let url = URL(string: "qsy://spot?callsign=W1AW")!
        XCTAssertNil(QSYURIParser.parse(url))
    }

    func testSpot_AllParams() {
        let url = URL(string: "qsy://spot?callsign=W4EF&freq=7074000&mode=FT8&grid=EM73&ref=K-1234&ref_type=pota&tx_power=5&source=sotawatch&comment=CQ")!
        guard case let .spot(params) = QSYURIParser.parse(url) else {
            XCTFail("Expected spot action")
            return
        }
        XCTAssertEqual(params.callsign, "W4EF")
        XCTAssertEqual(params.frequencyHz, 7_074_000)
        XCTAssertEqual(params.mode, "FT8")
        XCTAssertEqual(params.grid, "EM73")
        XCTAssertEqual(params.ref, ["K-1234"])
        XCTAssertEqual(params.refType, ["pota"])
        XCTAssertEqual(params.txPower, 5.0)
        XCTAssertEqual(params.source, "sotawatch")
        XCTAssertEqual(params.comment, "CQ")
    }

    func testSpot_MultipleRefs() {
        let url = URL(string: "qsy://spot?callsign=W4EF&freq=7074000&mode=FT8&ref=K-1234,W6/CT-001&ref_type=pota,sota")!
        guard case let .spot(params) = QSYURIParser.parse(url) else {
            XCTFail("Expected spot action")
            return
        }
        XCTAssertEqual(params.ref, ["K-1234", "W6/CT-001"])
        XCTAssertEqual(params.refType, ["pota", "sota"])
    }

    func testSpot_CallsignUppercased() {
        let url = URL(string: "qsy://spot?callsign=w1aw&freq=14074000")!
        guard case let .spot(params) = QSYURIParser.parse(url) else {
            XCTFail("Expected spot action")
            return
        }
        XCTAssertEqual(params.callsign, "W1AW")
    }

    // MARK: - Tune Action

    func testTune_Basic() {
        let url = URL(string: "qsy://tune?freq=14035000&mode=CW")!
        guard case let .tune(params) = QSYURIParser.parse(url) else {
            XCTFail("Expected tune action")
            return
        }
        XCTAssertEqual(params.frequencyHz, 14_035_000)
        XCTAssertEqual(params.frequencyMHz, 14.035, accuracy: 0.0001)
        XCTAssertEqual(params.mode, "CW")
    }

    func testTune_FreqOnly() {
        let url = URL(string: "qsy://tune?freq=7030000")!
        guard case let .tune(params) = QSYURIParser.parse(url) else {
            XCTFail("Expected tune action")
            return
        }
        XCTAssertEqual(params.frequencyHz, 7_030_000)
        XCTAssertNil(params.mode)
    }

    func testTune_MissingFreq_ReturnsNil() {
        let url = URL(string: "qsy://tune?mode=CW")!
        XCTAssertNil(QSYURIParser.parse(url))
    }

    // MARK: - Lookup Action

    func testLookup_Basic() {
        let url = URL(string: "qsy://lookup?callsign=W1AW")!
        guard case let .lookup(callsign) = QSYURIParser.parse(url) else {
            XCTFail("Expected lookup action")
            return
        }
        XCTAssertEqual(callsign, "W1AW")
    }

    func testLookup_MissingCallsign_ReturnsNil() {
        let url = URL(string: "qsy://lookup")!
        XCTAssertNil(QSYURIParser.parse(url))
    }

    func testLookup_Uppercases() {
        let url = URL(string: "qsy://lookup?callsign=ja1abc")!
        guard case let .lookup(callsign) = QSYURIParser.parse(url) else {
            XCTFail("Expected lookup action")
            return
        }
        XCTAssertEqual(callsign, "JA1ABC")
    }

    // MARK: - Import Action

    func testImport_Basic() {
        let url = URL(string: "qsy://import?url=https%3A%2F%2Fpota.app%2Fexport%2Flog.adi")!
        guard case let .importLog(importURL, format) = QSYURIParser.parse(url) else {
            XCTFail("Expected import action")
            return
        }
        XCTAssertEqual(importURL.absoluteString, "https://pota.app/export/log.adi")
        XCTAssertEqual(format, "adif")
    }

    func testImport_WithFormat() {
        let url = URL(string: "qsy://import?url=https%3A%2F%2Fexample.com%2Flog.csv&format=csv")!
        guard case let .importLog(_, format) = QSYURIParser.parse(url) else {
            XCTFail("Expected import action")
            return
        }
        XCTAssertEqual(format, "csv")
    }

    func testImport_MissingURL_ReturnsNil() {
        let url = URL(string: "qsy://import")!
        XCTAssertNil(QSYURIParser.parse(url))
    }

    // MARK: - Log Action

    func testLog_RequiredParams() {
        let url = URL(string: "qsy://log?callsign=K3LR&freq=14000000&mode=CW")!
        guard case let .log(params) = QSYURIParser.parse(url) else {
            XCTFail("Expected log action")
            return
        }
        XCTAssertEqual(params.callsign, "K3LR")
        XCTAssertEqual(params.frequencyHz, 14_000_000)
        XCTAssertEqual(params.mode, "CW")
    }

    func testLog_MissingMode_ReturnsNil() {
        let url = URL(string: "qsy://log?callsign=K3LR&freq=14000000")!
        XCTAssertNil(QSYURIParser.parse(url))
    }

    func testLog_AllParams() {
        let url = URL(string: "qsy://log?callsign=K3LR&freq=14000000&mode=CW&rst_sent=599&rst_rcvd=599&contest=CQ-WPX-CW&stx=001&srx=123&time=20260305T1430Z&grid=FN20&my_grid=EM73&ref=K-5678&ref_type=pota&tx_power=100&op=W1AW&station=W1AW&source=contestlogger&comment=Good%20signal")!
        guard case let .log(params) = QSYURIParser.parse(url) else {
            XCTFail("Expected log action")
            return
        }
        XCTAssertEqual(params.rstSent, "599")
        XCTAssertEqual(params.rstReceived, "599")
        XCTAssertEqual(params.contest, "CQ-WPX-CW")
        XCTAssertEqual(params.stx, "001")
        XCTAssertEqual(params.srx, "123")
        XCTAssertEqual(params.grid, "FN20")
        XCTAssertEqual(params.myGrid, "EM73")
        XCTAssertEqual(params.ref, ["K-5678"])
        XCTAssertEqual(params.refType, ["pota"])
        XCTAssertEqual(params.txPower, 100.0)
        XCTAssertEqual(params.op, "W1AW")
        XCTAssertEqual(params.station, "W1AW")
        XCTAssertEqual(params.source, "contestlogger")
        XCTAssertEqual(params.comment, "Good signal")
        XCTAssertNotNil(params.time)
    }

    // MARK: - Time Parsing

    func testTime_WithoutSeconds() {
        let url = URL(string: "qsy://log?callsign=W1AW&freq=14074000&mode=FT8&time=20260305T1430Z")!
        guard case let .log(params) = QSYURIParser.parse(url) else {
            XCTFail("Expected log action")
            return
        }
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: params.time!
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 5)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 30)
    }

    func testTime_WithSeconds() {
        let url = URL(string: "qsy://log?callsign=W1AW&freq=14074000&mode=FT8&time=20260305T143045Z")!
        guard case let .log(params) = QSYURIParser.parse(url) else {
            XCTFail("Expected log action")
            return
        }
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: params.time!
        )
        XCTAssertEqual(components.second, 45)
    }

    // MARK: - Spec Examples

    func testSpecExample_DXClusterSpot() {
        let url = URL(string: "qsy://spot?callsign=JA1ABC&freq=21074000&mode=FT8&grid=PM95&source=dxcluster")!
        guard case let .spot(params) = QSYURIParser.parse(url) else {
            XCTFail("Expected spot action")
            return
        }
        XCTAssertEqual(params.callsign, "JA1ABC")
        XCTAssertEqual(params.frequencyHz, 21_074_000)
        XCTAssertEqual(params.mode, "FT8")
        XCTAssertEqual(params.grid, "PM95")
        XCTAssertEqual(params.source, "dxcluster")
    }

    func testSpecExample_POTAActivation() {
        let url = URL(string: "qsy://spot?callsign=W4EF&freq=7074000&mode=FT8&ref=K-1234&ref_type=pota&source=pota")!
        guard case let .spot(params) = QSYURIParser.parse(url) else {
            XCTFail("Expected spot action")
            return
        }
        XCTAssertEqual(params.ref, ["K-1234"])
        XCTAssertEqual(params.refType, ["pota"])
    }
}
