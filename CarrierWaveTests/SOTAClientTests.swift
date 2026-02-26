import XCTest
@testable import CarrierWave

// MARK: - SOTAClientTests

@MainActor
final class SOTAClientTests: XCTestCase {
    // MARK: - SOTASpot JSON decoding

    func testDecodeSingleSpot() throws {
        let json = """
        {
            "id": 257063,
            "userID": 1058,
            "timeStamp": "2026-02-26T17:51:41",
            "comments": "Last shot at 20m",
            "callsign": "SMS",
            "associationCode": "W5N",
            "summitCode": "SE-029",
            "activatorCallsign": "KE5AKL",
            "activatorName": "Mike",
            "frequency": "14.061",
            "mode": "CW",
            "summitDetails": "Pajarito Peak, 2756m, 8 points",
            "highlightColor": null
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let spot = try JSONDecoder().decode(SOTASpot.self, from: data)

        XCTAssertEqual(spot.id, 257_063)
        XCTAssertEqual(spot.userID, 1_058)
        XCTAssertEqual(spot.activatorCallsign, "KE5AKL")
        XCTAssertEqual(spot.activatorName, "Mike")
        XCTAssertEqual(spot.spotterCallsign, "SMS")
        XCTAssertEqual(spot.associationCode, "W5N")
        XCTAssertEqual(spot.summitCode, "SE-029")
        XCTAssertEqual(spot.summitDetails, "Pajarito Peak, 2756m, 8 points")
        XCTAssertEqual(spot.frequency, "14.061")
        XCTAssertEqual(spot.mode, "CW")
        XCTAssertEqual(spot.comments, "Last shot at 20m")
        XCTAssertNil(spot.highlightColor)
        XCTAssertEqual(spot.timeStamp, "2026-02-26T17:51:41")
    }

    func testDecodeSpotArray() throws {
        let json = """
        [
            {
                "id": 257063,
                "userID": 1058,
                "timeStamp": "2026-02-26T17:51:41",
                "comments": "Last shot at 20m",
                "callsign": "SMS",
                "associationCode": "W5N",
                "summitCode": "SE-029",
                "activatorCallsign": "KE5AKL",
                "activatorName": "Mike",
                "frequency": "14.061",
                "mode": "CW",
                "summitDetails": "Pajarito Peak, 2756m, 8 points",
                "highlightColor": null
            },
            {
                "id": 257062,
                "userID": 4367,
                "timeStamp": "2026-02-26T17:46:54",
                "comments": "s2s",
                "callsign": "K6EL",
                "associationCode": "W6",
                "summitCode": "NC-298",
                "activatorCallsign": "K6EL",
                "activatorName": "Elliott",
                "frequency": "1.8",
                "mode": "FM",
                "summitDetails": "Vollmer Peak, 581m, 1 points",
                "highlightColor": null
            }
        ]
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let spots = try JSONDecoder().decode([SOTASpot].self, from: data)

        XCTAssertEqual(spots.count, 2)
        XCTAssertEqual(spots[0].id, 257_063)
        XCTAssertEqual(spots[1].id, 257_062)
        XCTAssertEqual(spots[1].activatorCallsign, "K6EL")
        XCTAssertEqual(spots[1].mode, "FM")
    }

    func testDecodeSpotWithNilComments() throws {
        let json = """
        {
            "id": 100,
            "userID": 1,
            "timeStamp": "2026-01-01T12:00:00",
            "comments": null,
            "callsign": "W1AW",
            "associationCode": "W1",
            "summitCode": "CT-001",
            "activatorCallsign": "W1AW",
            "activatorName": "Test",
            "frequency": "7.032",
            "mode": "CW",
            "summitDetails": "Test Summit, 100m, 1 points",
            "highlightColor": null
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let spot = try JSONDecoder().decode(SOTASpot.self, from: data)

        XCTAssertNil(spot.comments)
        XCTAssertNil(spot.highlightColor)
    }

    func testFrequencyParsing() throws {
        let json = """
        {
            "id": 1,
            "userID": 1,
            "timeStamp": "2026-01-01T12:00:00",
            "comments": null,
            "callsign": "W1AW",
            "associationCode": "W4C",
            "summitCode": "CM-001",
            "activatorCallsign": "W4FOO",
            "activatorName": "Foo",
            "frequency": "14.062",
            "mode": "CW",
            "summitDetails": "Mount Test, 1000m, 4 points",
            "highlightColor": null
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let spot = try JSONDecoder().decode(SOTASpot.self, from: data)

        XCTAssertEqual(spot.frequencyMHz, 14.062, accuracy: 0.001)
        XCTAssertEqual(spot.frequencyKHz, 14_062.0, accuracy: 1.0)
    }

    func testTimestampParsing() throws {
        let json = """
        {
            "id": 1,
            "userID": 1,
            "timeStamp": "2026-02-26T17:51:41",
            "comments": null,
            "callsign": "W1AW",
            "associationCode": "W5N",
            "summitCode": "SE-029",
            "activatorCallsign": "KE5AKL",
            "activatorName": "Mike",
            "frequency": "14.061",
            "mode": "CW",
            "summitDetails": "Pajarito Peak, 2756m, 8 points",
            "highlightColor": null
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let spot = try JSONDecoder().decode(SOTASpot.self, from: data)

        let parsed = try XCTUnwrap(spot.parsedTimestamp)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: parsed)

        XCTAssertEqual(components.year, 2_026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 26)
        XCTAssertEqual(components.hour, 17)
        XCTAssertEqual(components.minute, 51)
    }

    func testFullSummitReference() throws {
        let json = """
        {
            "id": 1,
            "userID": 1,
            "timeStamp": "2026-01-01T12:00:00",
            "comments": null,
            "callsign": "W1AW",
            "associationCode": "W4C",
            "summitCode": "CM-001",
            "activatorCallsign": "W4FOO",
            "activatorName": "Foo",
            "frequency": "14.062",
            "mode": "CW",
            "summitDetails": "Mount Test, 1000m, 4 points",
            "highlightColor": null
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let spot = try JSONDecoder().decode(SOTASpot.self, from: data)

        XCTAssertEqual(spot.fullSummitReference, "W4C/CM-001")
    }

    func testInvalidFrequencyReturnsNil() throws {
        let json = """
        {
            "id": 1,
            "userID": 1,
            "timeStamp": "2026-01-01T12:00:00",
            "comments": null,
            "callsign": "W1AW",
            "associationCode": "W1",
            "summitCode": "CT-001",
            "activatorCallsign": "W1AW",
            "activatorName": "Test",
            "frequency": "N/A",
            "mode": "CW",
            "summitDetails": "Test Summit, 100m, 1 points",
            "highlightColor": null
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let spot = try JSONDecoder().decode(SOTASpot.self, from: data)

        XCTAssertNil(spot.frequencyMHz)
        XCTAssertNil(spot.frequencyKHz)
    }
}
