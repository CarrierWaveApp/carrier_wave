import XCTest
@testable import CarrierWave

/// Tests for RoveStop Codable round-trip and LoggingSession rove accessors
final class RoveStopTests: XCTestCase {
    // MARK: - Codable Round-Trip

    @MainActor
    func testEncodeDecode_preservesAllFields() throws {
        // Given
        let stop = RoveStop(
            parkReference: "US-1234",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_003_600),
            myGrid: "FN31pr",
            qsoCount: 12,
            notes: "First stop"
        )

        // When
        let data = try JSONEncoder().encode([stop])
        let decoded = try JSONDecoder().decode([RoveStop].self, from: data)

        // Then
        XCTAssertEqual(decoded.count, 1)
        let result = decoded[0]
        XCTAssertEqual(result.id, stop.id)
        XCTAssertEqual(result.parkReference, "US-1234")
        XCTAssertEqual(result.startedAt, stop.startedAt)
        XCTAssertEqual(result.endedAt, stop.endedAt)
        XCTAssertEqual(result.myGrid, "FN31pr")
        XCTAssertEqual(result.qsoCount, 12)
        XCTAssertEqual(result.notes, "First stop")
    }

    @MainActor
    func testEncodeDecode_nilOptionals() throws {
        // Given
        let stop = RoveStop(
            parkReference: "K-0001",
            startedAt: Date()
        )

        // When
        let data = try JSONEncoder().encode([stop])
        let decoded = try JSONDecoder().decode([RoveStop].self, from: data)

        // Then
        let result = decoded[0]
        XCTAssertNil(result.endedAt)
        XCTAssertNil(result.myGrid)
        XCTAssertEqual(result.qsoCount, 0)
        XCTAssertNil(result.notes)
    }

    @MainActor
    func testEncodeDecode_preservesArrayOrder() throws {
        // Given
        let stops = [
            RoveStop(parkReference: "US-0001", startedAt: Date()),
            RoveStop(parkReference: "US-0002", startedAt: Date()),
            RoveStop(parkReference: "US-0003", startedAt: Date()),
        ]

        // When
        let data = try JSONEncoder().encode(stops)
        let decoded = try JSONDecoder().decode([RoveStop].self, from: data)

        // Then
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].parkReference, "US-0001")
        XCTAssertEqual(decoded[1].parkReference, "US-0002")
        XCTAssertEqual(decoded[2].parkReference, "US-0003")
    }

    @MainActor
    func testIsActive_noEndedAt_returnsTrue() {
        let stop = RoveStop(parkReference: "US-1234", startedAt: Date())
        XCTAssertTrue(stop.isActive)
    }

    @MainActor
    func testIsActive_withEndedAt_returnsFalse() {
        let stop = RoveStop(
            parkReference: "US-1234",
            startedAt: Date(),
            endedAt: Date()
        )
        XCTAssertFalse(stop.isActive)
    }

    @MainActor
    func testFormattedDuration_minutesOnly() {
        let start = Date()
        let stop = RoveStop(
            parkReference: "US-1234",
            startedAt: start,
            endedAt: start.addingTimeInterval(45 * 60)
        )
        XCTAssertEqual(stop.formattedDuration, "45m")
    }

    @MainActor
    func testFormattedDuration_hoursAndMinutes() {
        let start = Date()
        let stop = RoveStop(
            parkReference: "US-1234",
            startedAt: start,
            endedAt: start.addingTimeInterval(75 * 60)
        )
        XCTAssertEqual(stop.formattedDuration, "1h 15m")
    }
}
