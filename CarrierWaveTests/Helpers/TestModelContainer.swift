import SwiftData
import XCTest
@testable import CarrierWave

// MARK: - TestModelContainer

/// Shared test infrastructure for SwiftData tests
enum TestModelContainer {
    /// Creates an in-memory SwiftData container suitable for testing
    /// Includes all models needed for log management tests
    @MainActor
    static func create() throws -> ModelContainer {
        let schema = Schema([
            QSO.self,
            ServicePresence.self,
            UploadDestination.self,
            LoggingSession.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Creates a container and returns both container and main context
    @MainActor
    static func createWithContext() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try create()
        return (container, container.mainContext)
    }
}

/// Extension for cleaner test assertions on QSOs
extension QSO {
    /// Creates a simple test QSO with minimal required fields
    static func testQSO(
        callsign: String = "W1AW",
        band: String = "20m",
        mode: String = "CW",
        frequency: Double? = 14.060,
        timestamp: Date = Date(),
        myCallsign: String = "N0TEST",
        parkReference: String? = nil,
        importSource: ImportSource = .logger
    ) -> QSO {
        QSO(
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: frequency,
            timestamp: timestamp,
            rstSent: "599",
            rstReceived: "599",
            myCallsign: myCallsign,
            parkReference: parkReference,
            importSource: importSource
        )
    }
}

/// Extension for creating test logging sessions
extension LoggingSession {
    /// Creates a simple test session
    static func testSession(
        myCallsign: String = "N0TEST",
        mode: String = "CW",
        frequency: Double? = 14.060,
        activationType: ActivationType = .casual,
        parkReference: String? = nil,
        myGrid: String? = "FN31"
    ) -> LoggingSession {
        LoggingSession(
            myCallsign: myCallsign,
            startedAt: Date(),
            frequency: frequency,
            mode: mode,
            activationType: activationType,
            parkReference: parkReference,
            myGrid: myGrid
        )
    }
}
