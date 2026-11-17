import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

// MARK: - TestModelContainer

/// Shared test infrastructure for SwiftData tests
enum TestModelContainer {
    // MARK: Internal

    /// Creates an in-memory SwiftData container suitable for testing
    /// Includes all models needed for log management tests
    @MainActor
    static func create() throws -> ModelContainer {
        let schema = Schema(AppSchema.models)
        // Mirror the app (`CarrierWaveApp`): SwiftData must never drive CloudKit.
        // `.automatic` picks up the host's iCloud entitlement and rejects the schema.
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        // Fire-and-forget tasks (network completions, activity reports) can
        // outlive the test that started them. Keep every container alive for
        // the process so a late fetch hits an orphaned store, not a freed one.
        retained.append(container)
        return container
    }

    /// Creates a container and returns both container and main context
    @MainActor
    static func createWithContext() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try create()
        return (container, container.mainContext)
    }

    // MARK: Private

    @MainActor private static var retained: [ModelContainer] = []
}

// MARK: - SessionTestDefaults

/// Turns off the session features that reach the network (conditions fetch,
/// auto/QRT spots, activity reporting) for one test, then restores whatever
/// the simulator's app settings held before.
enum SessionTestDefaults {
    // MARK: Internal

    /// Disable network side effects; call the returned closure in tearDown.
    static func disableNetworkSideEffects() -> () -> Void {
        let defaults = UserDefaults.standard
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        for key in keys {
            defaults.set(false, forKey: key)
        }
        return {
            for (key, value) in saved {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
    }

    // MARK: Private

    private static let keys = [
        "autoRecordConditions",
        "potaAutoSpotEnabled",
        "potaQRTSpotEnabled",
        "shareSessionOnEnd",
        "shareActivitiesEnabled",
    ]
}

// MARK: - QSO + test helpers

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
