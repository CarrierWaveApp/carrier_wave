import CarrierWaveCore
import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for LoggingSession equipment fields (antenna, key, mic, etc.)
final class LoggingSessionEquipmentTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    @MainActor
    override func setUp() async throws {
        let (container, context) = try TestModelContainer.createWithContext()
        modelContainer = container
        modelContext = context
    }

    @MainActor
    func testInit_WithEquipmentFields() {
        // When
        let session = LoggingSession(
            myCallsign: "N0TEST",
            myRig: "IC-705",
            myAntenna: "EFHW 49:1",
            myKey: "Begali Traveller",
            myMic: "Heil Pro 7",
            extraEquipment: "CW filter, battery pack",
            attendees: "KI7QCF, N0CALL"
        )

        // Then
        XCTAssertEqual(session.myRig, "IC-705")
        XCTAssertEqual(session.myAntenna, "EFHW 49:1")
        XCTAssertEqual(session.myKey, "Begali Traveller")
        XCTAssertEqual(session.myMic, "Heil Pro 7")
        XCTAssertEqual(session.extraEquipment, "CW filter, battery pack")
        XCTAssertEqual(session.attendees, "KI7QCF, N0CALL")
        XCTAssertEqual(session.photoFilenames, [])
    }

    @MainActor
    func testInit_DefaultEquipmentFields() {
        // When
        let session = LoggingSession(myCallsign: "N0TEST")

        // Then
        XCTAssertNil(session.myAntenna)
        XCTAssertNil(session.myKey)
        XCTAssertNil(session.myMic)
        XCTAssertNil(session.extraEquipment)
        XCTAssertNil(session.attendees)
        XCTAssertEqual(session.photoFilenames, [])
    }

    @MainActor
    func testPersistence_EquipmentFields() throws {
        // Given
        let session = LoggingSession(
            myCallsign: "N0TEST",
            myAntenna: "Linked Dipole",
            myKey: "CW Morse Mini",
            myMic: "Heil HM-12",
            extraEquipment: "Tuner",
            attendees: "W1AW"
        )
        session.photoFilenames = ["photo1.jpg", "photo2.jpg"]
        modelContext.insert(session)
        try modelContext.save()

        // When
        let descriptor = FetchDescriptor<LoggingSession>()
        let fetched = try XCTUnwrap(try modelContext.fetch(descriptor).first)

        // Then
        XCTAssertEqual(fetched.myAntenna, "Linked Dipole")
        XCTAssertEqual(fetched.myKey, "CW Morse Mini")
        XCTAssertEqual(fetched.myMic, "Heil HM-12")
        XCTAssertEqual(fetched.extraEquipment, "Tuner")
        XCTAssertEqual(fetched.attendees, "W1AW")
        XCTAssertEqual(fetched.photoFilenames, ["photo1.jpg", "photo2.jpg"])
    }
}
