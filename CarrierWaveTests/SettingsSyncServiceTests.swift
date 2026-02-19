import XCTest
@testable import CarrierWave

// MARK: - SettingsSyncServiceTests

@MainActor
final class SettingsSyncServiceTests: XCTestCase {
    // MARK: - Registry Tests

    func testRegistryContainsExpectedKeys() {
        let allKeys = SettingsSyncRegistry.allSettings.map(\.localKey)

        // Spot-check key categories
        XCTAssertTrue(allKeys.contains("loggerDefaultCallsign"))
        XCTAssertTrue(allKeys.contains("appearanceMode"))
        XCTAssertTrue(allKeys.contains("potaAutoSpotEnabled"))
        XCTAssertTrue(allKeys.contains("tabOrder"))
        XCTAssertTrue(allKeys.contains("userAntennaList"))
        XCTAssertTrue(allKeys.contains("stationProfiles"))
        XCTAssertTrue(allKeys.contains("dashboardMetric1"))
        XCTAssertTrue(allKeys.contains("commandRowEnabled"))
    }

    func testRegistryExcludesDebugFlags() {
        let allKeys = Set(SettingsSyncRegistry.allSettings.map(\.localKey))

        XCTAssertFalse(allKeys.contains("debugMode"))
        XCTAssertFalse(allKeys.contains("readOnlyMode"))
        XCTAssertFalse(allKeys.contains("bypassPOTAMaintenance"))
    }

    func testRegistryExcludesTourState() {
        let allKeys = Set(SettingsSyncRegistry.allSettings.map(\.localKey))

        XCTAssertFalse(allKeys.contains("tour.hasCompletedIntroTour"))
        XCTAssertFalse(allKeys.contains("tour.hasCompletedOnboarding"))
        XCTAssertFalse(allKeys.contains("tour.lastTourVersion"))
        XCTAssertFalse(allKeys.contains("tour.seenMiniTours"))
    }

    func testCloudKeyPrefixing() {
        for setting in SettingsSyncRegistry.allSettings {
            XCTAssertTrue(
                setting.cloudKey.hasPrefix("v1."),
                "Cloud key '\(setting.cloudKey)' should have v1. prefix"
            )
            XCTAssertEqual(
                setting.cloudKey,
                "v1.\(setting.localKey)",
                "Cloud key should be v1. + local key"
            )
        }
    }

    func testNoLocalKeyDuplicates() {
        let allKeys = SettingsSyncRegistry.allSettings.map(\.localKey)
        let uniqueKeys = Set(allKeys)
        XCTAssertEqual(
            allKeys.count,
            uniqueKeys.count,
            "Registry should not contain duplicate local keys"
        )
    }

    // MARK: - Type Encoding Tests

    func testAllSettingsHaveValidTypes() {
        for setting in SettingsSyncRegistry.allSettings {
            switch setting.type {
            case .bool,
                 .int,
                 .double,
                 .string,
                 .data,
                 .stringArray:
                break // All valid
            }
        }
    }

    func testEquipmentListsAreStringArrayType() {
        let equipmentKeys = ["userAntennaList", "userKeyList", "userMicList", "userRadioList"]
        for key in equipmentKeys {
            let setting = SettingsSyncRegistry.allSettings.first { $0.localKey == key }
            XCTAssertNotNil(setting, "Equipment key '\(key)' should be registered")
            if case .stringArray = setting?.type {} else {
                XCTFail("Equipment key '\(key)' should be .stringArray type")
            }
        }
    }

    func testDataTypeUsedForJSONBlobs() {
        let dataKeys = ["tabOrder", "hiddenTabs", "stationProfiles"]
        for key in dataKeys {
            let setting = SettingsSyncRegistry.allSettings.first { $0.localKey == key }
            XCTAssertNotNil(setting, "Data key '\(key)' should be registered")
            if case .data = setting?.type {} else {
                XCTFail("Data key '\(key)' should be .data type")
            }
        }
    }

    // MARK: - Size Budget Tests

    func testRegistryWithinKVSLimits() {
        // iCloud KVS limit: 1024 keys
        XCTAssertLessThan(
            SettingsSyncRegistry.allSettings.count,
            1_024,
            "Registry should stay well under 1024 key limit"
        )

        // Practical check: we expect ~50 keys
        XCTAssertLessThan(
            SettingsSyncRegistry.allSettings.count,
            100,
            "Registry should be around 50 keys, not growing unbounded"
        )
    }
}
