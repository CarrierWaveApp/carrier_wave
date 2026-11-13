import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// swiftlint:disable function_body_length type_body_length

// MARK: - FfiReflectorTests

/// Round-trip parity for the reverse reflector: `project(hydrate(ffi)) == ffi`.
/// A field dropped or mis-mapped by `hydrate` shows up as an inequality here, the
/// same guarantee the read-source snapshot tests give in the other direction.
final class FfiReflectorTests: XCTestCase {
    // MARK: Internal

    func testActivityLogRoundTripsAllFields() {
        let ffi = FfiActivityLog(
            id: "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
            name: "Backyard",
            myCallsign: "W6JY",
            createdAt: 1_700_000_000,
            stationProfileId: "a1a2a3a4-b1b2-41c2-91d2-e1e2e3e4e5e6",
            currentGrid: "CM87",
            locationLabel: "Home",
            isActive: true,
            cloudDirtyFlag: true
        )
        XCTAssertEqual(SwiftDataStoreImporter.project(FfiReflector.hydrate(ffi)), ffi)
    }

    func testActivityLogRoundTripsWithNilOptionals() {
        let ffi = FfiActivityLog(
            id: "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
            name: "Portable",
            myCallsign: "W6JY",
            createdAt: 1_700_000_042,
            stationProfileId: nil,
            currentGrid: nil,
            locationLabel: nil,
            isActive: false,
            cloudDirtyFlag: false
        )
        XCTAssertEqual(SwiftDataStoreImporter.project(FfiReflector.hydrate(ffi)), ffi)
    }

    func testQsoRoundTripsAllFields() {
        let ffi = makeQso(allFields: true)
        XCTAssertEqual(SwiftDataStoreImporter.project(FfiReflector.hydrate(ffi)), ffi)
    }

    func testQsoRoundTripsWithNilOptionals() {
        let ffi = makeQso(allFields: false)
        XCTAssertEqual(SwiftDataStoreImporter.project(FfiReflector.hydrate(ffi)), ffi)
    }

    func testLoggingSessionRoundTripsAllFields() {
        let ffi = makeLoggingSession()
        XCTAssertEqual(SwiftDataStoreImporter.project(FfiReflector.hydrate(ffi)), ffi)
    }

    func testServicePresenceRoundTripsScalars() {
        // `qsoId` is nil: the relationship is linked by the context reflector, not
        // the pure hydrator, so the scalar round-trip fixes qsoId at nil.
        for present in [true, false] {
            let ffi = FfiServicePresence(
                id: "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
                serviceTypeRawValue: "qrz",
                isPresent: present,
                needsUpload: present,
                uploadRejected: !present,
                rejectedAtBuild: present ? "2.4.132" : nil,
                isSubmitted: present,
                lastConfirmedAt: present ? 1_700_000_000 : nil,
                parkReference: present ? "US-1234" : nil,
                cloudDirtyFlag: present,
                qsoId: nil
            )
            XCTAssertEqual(SwiftDataStoreImporter.project(FfiReflector.hydrate(ffi)), ffi)
        }
    }

    func testSessionSpotRoundTrips() {
        for allFields in [true, false] {
            let ffi = FfiSessionSpot(
                id: "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
                loggingSessionId: "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
                callsign: "W1AW",
                frequencyKHz: 14_074.0,
                mode: "FT8",
                timestamp: 1_700_000_000,
                source: "pota",
                snr: allFields ? -10 : nil,
                wpm: allFields ? 22 : nil,
                spotter: allFields ? "W6JY" : nil,
                spotterGrid: allFields ? "CM87" : nil,
                parkRef: allFields ? "US-1234" : nil,
                parkName: allFields ? "Test Park" : nil,
                comments: allFields ? "14 dB 22 WPM CQ" : nil,
                region: "North America",
                distanceMeters: allFields ? 1_500.0 : nil,
                bearingDegrees: allFields ? 45.0 : nil,
                cloudDirtyFlag: allFields
            )
            XCTAssertEqual(SwiftDataStoreImporter.project(FfiReflector.hydrate(ffi)), ffi)
        }
    }

    func testActivationMetadataRoundTrips() {
        for allFields in [true, false] {
            // 1_699_920_000 is an exact UTC midnight (multiple of 86_400), so the
            // model initializer's start-of-day normalisation is a no-op.
            let ffi = FfiActivationMetadata(
                parkReference: "US-1234",
                date: 1_699_920_000,
                title: allFields ? "Summit Run" : nil,
                watts: allFields ? 5 : nil,
                weather: allFields ? "Sunny" : nil,
                solarConditions: allFields ? "Good" : nil,
                averageWpm: allFields ? 22 : nil,
                solarKIndex: allFields ? 2.0 : nil,
                solarFlux: allFields ? 120.5 : nil,
                solarSunspots: allFields ? 45 : nil,
                solarPropagationRating: allFields ? "Good" : nil,
                solarAIndex: allFields ? 5 : nil,
                solarBandConditions: allFields ? "{\"20m\":\"Good\"}" : nil,
                solarTimestamp: allFields ? 1_699_920_000 : nil,
                weatherTemperatureF: allFields ? 72.0 : nil,
                weatherTemperatureC: allFields ? 22.2 : nil,
                weatherHumidity: allFields ? 55 : nil,
                weatherWindSpeed: allFields ? 5.0 : nil,
                weatherWindDirection: allFields ? "NW" : nil,
                weatherDescription: allFields ? "Clear" : nil,
                weatherTimestamp: allFields ? 1_699_920_000 : nil,
                cloudDirtyFlag: allFields
            )
            XCTAssertEqual(SwiftDataStoreImporter.project(FfiReflector.hydrate(ffi)), ffi)
        }
    }

    @MainActor
    func testReflectActivityLogInsertsThenUpdatesInPlace() throws {
        let container = try ModelContainer(
            for: Schema([ActivityLog.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let id = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"

        let inserted = try FfiReflector.reflect(
            FfiActivityLog(
                id: id, name: "First", myCallsign: "W6JY", createdAt: 1_700_000_000,
                stationProfileId: nil, currentGrid: "CM87", locationLabel: nil,
                isActive: true, cloudDirtyFlag: false
            ),
            into: context, mirror: nil
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ActivityLog>()), 1)
        XCTAssertEqual(inserted.name, "First")

        // Same id → in-place update (same object, no duplicate row).
        let reflected = try FfiReflector.reflect(
            FfiActivityLog(
                id: id, name: "Renamed", myCallsign: "W6JY", createdAt: 1_700_000_000,
                stationProfileId: nil, currentGrid: "DM04", locationLabel: "Road",
                isActive: false, cloudDirtyFlag: true
            ),
            into: context, mirror: nil
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ActivityLog>()), 1)
        XCTAssertTrue(reflected === inserted)
        XCTAssertEqual(reflected.name, "Renamed")
        XCTAssertEqual(reflected.currentGrid, "DM04")
        XCTAssertFalse(reflected.isActive)
        XCTAssertTrue(reflected.cloudDirtyFlag)
    }

    @MainActor
    func testReflectQsoLinksPresenceAndSurvivesInPlaceUpdate() throws {
        let container = try ModelContainer(
            for: Schema([QSO.self, ServicePresence.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        var qsoCount = FetchDescriptor<QSO>()
        qsoCount.fetchLimit = 100

        let qso = try FfiReflector.reflect(makeQso(allFields: true), into: context, mirror: nil)
        let presence = try FfiReflector.reflect(
            FfiServicePresence(
                id: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
                serviceTypeRawValue: "qrz", isPresent: false, needsUpload: true,
                uploadRejected: false, rejectedAtBuild: nil, isSubmitted: false,
                lastConfirmedAt: nil, parkReference: nil, cloudDirtyFlag: true,
                qsoId: "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"
            ),
            into: context, mirror: nil, linkedTo: qso
        )
        XCTAssertTrue(presence.qso === qso) // relationship linked

        // Same-id in-place update keeps identity, count, and the presence link.
        let reflected = try FfiReflector.reflect(makeQso(allFields: false), into: context, mirror: nil)
        XCTAssertTrue(reflected === qso)
        XCTAssertEqual(try context.fetchCount(qsoCount), 1)
        XCTAssertTrue(presence.qso === reflected)
    }

    @MainActor
    func testReflectLoggingSessionInsertsThenUpdatesInPlace() throws {
        let container = try ModelContainer(
            for: Schema([LoggingSession.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        var ffi = makeLoggingSession()
        let inserted = try FfiReflector.reflect(ffi, into: context, mirror: nil)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggingSession>()), 1)
        XCTAssertEqual(inserted.qsoCount, 42)
        XCTAssertEqual(inserted.statusRawValue, "completed")

        // Same id → in-place update: a held `activeSession` reference survives.
        ffi.qsoCount = 43
        ffi.statusRawValue = "paused"
        ffi.endedAt = nil
        let reflected = try FfiReflector.reflect(ffi, into: context, mirror: nil)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggingSession>()), 1)
        XCTAssertTrue(reflected === inserted)
        XCTAssertEqual(reflected.qsoCount, 43)
        XCTAssertEqual(reflected.statusRawValue, "paused")
        XCTAssertNil(reflected.endedAt)
    }

    @MainActor
    func testReflectSessionSpotInsertsThenUpdatesInPlace() throws {
        let container = try ModelContainer(
            for: Schema([SessionSpot.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let id = "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"

        var ffi = FfiSessionSpot(
            id: id,
            loggingSessionId: "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
            callsign: "W1AW", frequencyKHz: 14_074.0, mode: "FT8",
            timestamp: 1_700_000_000, source: "pota", snr: nil, wpm: nil,
            spotter: nil, spotterGrid: nil, parkRef: nil, parkName: nil,
            comments: nil, region: "North America", distanceMeters: nil,
            bearingDegrees: nil, cloudDirtyFlag: false
        )
        let inserted = try FfiReflector.reflect(ffi, into: context, mirror: nil)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionSpot>()), 1)

        ffi.frequencyKHz = 14_040.0
        ffi.comments = "QRT"
        let reflected = try FfiReflector.reflect(ffi, into: context, mirror: nil)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionSpot>()), 1)
        XCTAssertTrue(reflected === inserted)
        XCTAssertEqual(reflected.frequencyKHz, 14_040.0)
        XCTAssertEqual(reflected.comments, "QRT")
    }

    func testRoveStopsRoundTripThroughTableProjection() {
        let session = LoggingSession(myCallsign: "W6JY")
        session.isRove = true
        session.cloudDirtyFlag = false
        let stops = [
            RoveStop(
                parkReference: "US-1111",
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                endedAt: Date(timeIntervalSince1970: 1_700_003_600),
                myGrid: "CM87",
                qsoCount: 12,
                notes: "first stop"
            ),
            RoveStop(
                parkReference: "US-2222",
                startedAt: Date(timeIntervalSince1970: 1_700_003_600),
                endedAt: nil,
                myGrid: nil,
                qsoCount: 0,
                notes: nil
            ),
        ]
        session.roveStops = stops

        let rows = SwiftDataStoreImporter.projectRoveStops(session)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].loggingSessionId, SwiftDataStoreImporter.uuid(session.id))
        XCTAssertNil(rows[1].endedAt)

        let hydrated = FfiReflector.hydrateRoveStops(rows)
        XCTAssertEqual(hydrated.map(\.id), stops.map(\.id))
        XCTAssertEqual(hydrated.map(\.parkReference), stops.map(\.parkReference))
        XCTAssertEqual(hydrated.map(\.startedAt), stops.map(\.startedAt))
        XCTAssertEqual(hydrated.map(\.endedAt), stops.map(\.endedAt))
        XCTAssertEqual(hydrated.map(\.myGrid), stops.map(\.myGrid))
        XCTAssertEqual(hydrated.map(\.qsoCount), stops.map(\.qsoCount))
        XCTAssertEqual(hydrated.map(\.notes), stops.map(\.notes))
    }

    @MainActor
    func testReflectActivationMetadataUpsertsByParkAndDate() throws {
        let container = try ModelContainer(
            for: Schema([ActivationMetadata.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        var ffi = FfiActivationMetadata(
            parkReference: "US-1234", date: 1_699_920_000, title: nil,
            watts: nil, weather: nil, solarConditions: nil, averageWpm: nil,
            solarKIndex: nil, solarFlux: nil, solarSunspots: nil,
            solarPropagationRating: nil, solarAIndex: nil, solarBandConditions: nil,
            solarTimestamp: nil, weatherTemperatureF: nil, weatherTemperatureC: nil,
            weatherHumidity: nil, weatherWindSpeed: nil, weatherWindDirection: nil,
            weatherDescription: nil, weatherTimestamp: nil, cloudDirtyFlag: false
        )
        let inserted = try FfiReflector.reflect(ffi, into: context, mirror: nil)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ActivationMetadata>()), 1)
        XCTAssertNil(inserted.averageWPM)

        // Same (park, date) → in-place update (the record has no id column).
        ffi.averageWpm = 22
        ffi.weather = "Sunny"
        let reflected = try FfiReflector.reflect(ffi, into: context, mirror: nil)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ActivationMetadata>()), 1)
        XCTAssertTrue(reflected === inserted)
        XCTAssertEqual(reflected.averageWPM, 22)
        XCTAssertEqual(reflected.weather, "Sunny")

        // Different date → a second row (distinct activation day).
        ffi.date = 1_700_006_400
        _ = try FfiReflector.reflect(ffi, into: context, mirror: nil)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ActivationMetadata>()), 2)
    }

    // MARK: Private

    /// `freqKhz` is a clean multiple of 1000 so the MHz round-trip (÷1000 ×1000) is
    /// exact under IEEE-754; `presence` is always `[]` (projected separately).
    private func makeQso(allFields: Bool) -> FfiQso {
        FfiQso(
            id: "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
            callsign: "W1AW",
            band: "20m",
            mode: "FT8",
            freqKhz: allFields ? 14_000.0 : nil,
            qsoDate: 1_700_000_000,
            myGrid: allFields ? "CM87" : nil,
            theirGrid: allFields ? "FN31" : nil,
            rstSent: allFields ? "599" : nil,
            rstRcvd: allFields ? "599" : nil,
            myCallsign: "W6JY",
            park: allFields ? "US-1234" : nil,
            theirPark: allFields ? "US-5678" : nil,
            notes: allFields ? "nice sig | SOTA" : nil,
            notesUserAuthored: allFields,
            spotCommentsData: nil,
            callsignChangeNote: allFields ? "was W1XYZ" : nil,
            originalCallsign: allFields ? "W1XYZ" : nil,
            importSourceRawValue: "logger",
            importedAt: 1_700_000_005,
            modifiedAt: allFields ? 1_700_000_010 : nil,
            rawAdif: allFields ? "<call:4>W1AW" : nil,
            name: allFields ? "Hiram" : nil,
            qth: allFields ? "Newington" : nil,
            state: allFields ? "CT" : nil,
            country: allFields ? "United States" : nil,
            power: allFields ? 5 : nil,
            myRig: allFields ? "KX2" : nil,
            stationProfileName: allFields ? "Portable" : nil,
            sotaRef: allFields ? "W1/HA-001" : nil,
            wwffRef: allFields ? "KFF-1234" : nil,
            aoaCode: allFields ? "AOA-1" : nil,
            qrzLogId: allFields ? "12345" : nil,
            qrzConfirmed: allFields,
            lotwConfirmedDate: allFields ? 1_700_000_020 : nil,
            lotwConfirmed: allFields,
            dxcc: allFields ? 291 : nil,
            theirLicenseClass: allFields ? "Extra" : nil,
            contestName: allFields ? "CQWW" : nil,
            contestSerialSent: allFields ? 42 : nil,
            contestSerialReceived: allFields ? 7 : nil,
            contestExchangeSent: allFields ? "03" : nil,
            contestExchangeReceived: allFields ? "05" : nil,
            isHidden: allFields,
            isActivityLogQso: allFields,
            stationCallsign: allFields ? "W6JY/P" : nil,
            loggingSessionId: allFields ? "3f2504e0-4f89-41d3-9a0c-0305e82c3301" : nil,
            dirty: allFields,
            satName: nil,
            propMode: nil,
            presence: []
        )
    }

    /// A LoggingSession with every column populated (blobs, JSON arrays, contest,
    /// conditions, TOTA) to catch any dropped field in the 75-column hydrator.
    private func makeLoggingSession() -> FfiLoggingSession {
        FfiLoggingSession(
            id: "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
            myCallsign: "W6JY",
            startedAt: 1_700_000_000,
            endedAt: 1_700_003_600,
            frequency: 14.074,
            mode: "FT8",
            activationTypeRawValue: "pota",
            programsRawValue: "[\"pota\",\"wwff\"]",
            statusRawValue: "completed",
            parkReference: "US-1234",
            sotaReference: "W6/CT-001",
            missionReference: "M-1",
            wwffReference: "KFF-1234",
            myGrid: "CM87",
            power: 5,
            myRig: "KX2",
            notes: "great day",
            qsoComment: "SOTA chaser",
            customTitle: "Backyard Bash",
            qsoCount: 42,
            spotCommentsData: Data([1, 2, 3]),
            isRove: true,
            roveStopsData: Data([4, 5, 6]),
            myAntenna: "EFHW",
            myKey: "N0SA",
            myMic: "SM58",
            extraEquipment: "battery",
            attendees: "W1AW",
            photoFilenames: "[\"a.jpg\",\"b.jpg\"]",
            radioItemId: "a1a2a3a4-b1b2-41c2-91d2-e1e2e3e4e5e6",
            stationCallsign: "W6JY/P",
            operatorCallsignsRawValue: "[\"W6JY\"]",
            solarKIndex: 2.0,
            solarFlux: 120.5,
            solarSunspots: 45,
            solarPropagationRating: "Good",
            solarAIndex: 5,
            solarBandConditions: "{\"20m\":\"Good\"}",
            solarTimestamp: 1_700_000_100,
            solarConditions: "Good",
            weatherTemperatureF: 72.0,
            weatherTemperatureC: 22.2,
            weatherHumidity: 55,
            weatherWindSpeed: 5.0,
            weatherWindDirection: "NW",
            weatherDescription: "Clear",
            weatherTimestamp: 1_700_000_200,
            weather: "Sunny",
            cloudDirtyFlag: true,
            contestId: "cqww",
            contestCategory: "SOAB-HP",
            contestOverlayCategory: "YL",
            contestPower: "HIGH",
            contestBands: "ALL",
            contestOperator: "W6JY",
            activationLatitude: 37.8044,
            activationLongitude: -122.2712,
            activationDistanceMiles: 3.2,
            activationElevationGainFeet: 500.0,
            ruckWeightPounds: 25.0,
            qrpActivation: true,
            withPets: true,
            withKids: false,
            winlinkSent: true,
            aprsSent: false,
            varacSent: true,
            adaptiveSport: false,
            trackPointsData: Data([7, 8, 9]),
            totaCategoryRawValue: "mobile",
            personalEffortFactor: 3,
            firstActivationOfTileEver: true,
            winterActivationOverride: 1,
            tilesActivatedData: Data([10, 11]),
            totaT3CandidatesData: Data([12, 13]),
            totaT3SnapshotAt: 1_700_000_300,
            totaOfficialPoints: 12.5
        )
    }
}
