import Foundation

// MARK: - SettingsSyncRegistry

/// Explicit allowlist of settings that sync via iCloud Key-Value Store.
///
/// Design decisions:
/// - **Allowlist, not denylist**: Only explicitly registered keys sync.
/// - **`v1.` cloud key prefix**: Allows future schema migration.
/// - Debug/developer flags and tour/onboarding state do NOT sync.
enum SettingsSyncRegistry {
    // MARK: Internal

    static let allSettings: [SyncableSetting] = identity
        + loggerDefaults
        + potaSettings
        + appearance
        + tabConfig
        + equipmentLists
        + stationProfiles
        + activityLogSettings
        + keyboardConfig
        + dashboardMetrics
        + miscSettings

    // MARK: Private

    // MARK: - Identity & Profile

    private static let identity: [SyncableSetting] = [
        .init("loggerDefaultCallsign", type: .string),
        .init("loggerDefaultGrid", type: .string),
        .init("userLicenseClass", type: .string),
    ]

    // MARK: - Logger Defaults

    private static let loggerDefaults: [SyncableSetting] = [
        .init("loggerDefaultMode", type: .string),
        .init("loggerDefaultActivationType", type: .string),
        .init("loggerDefaultParkReference", type: .string),
        .init("loggerDefaultPower", type: .string),
        .init("loggerDefaultRadio", type: .string),
        .init("loggerDefaultAntenna", type: .string),
        .init("loggerDefaultKey", type: .string),
        .init("loggerDefaultMic", type: .string),
        .init("loggerShowActivityPanel", type: .bool),
        .init("loggerShowLicenseWarnings", type: .bool),
        .init("loggerKeepScreenOn", type: .bool),
        .init("loggerAutoModeSwitch", type: .bool),
        .init("loggerKeepLookupAfterLog", type: .bool),
        .init("loggerShowTheirGrid", type: .bool),
        .init("loggerShowTheirPark", type: .bool),
        .init("loggerShowOperator", type: .bool),
    ]

    // MARK: - POTA Settings

    private static let potaSettings: [SyncableSetting] = [
        .init("potaAutoSpotEnabled", type: .bool),
        .init("potaQSYSpotEnabled", type: .bool),
        .init("potaQRTSpotEnabled", type: .bool),
        .init("potaRoveQRTMessage", type: .string),
        .init("autoRecordConditions", type: .bool),
        .init("solarPollingEnabled", type: .bool),
        .init("shareCardIncludeEquipment", type: .bool),
        .init("statisticianMode", type: .bool),
        .init("potaUploadPromptDisabled", type: .bool),
        .init("qrqCrewAutoSpot", type: .bool),
    ]

    // MARK: - Appearance

    private static let appearance: [SyncableSetting] = [
        .init("appearanceMode", type: .string),
        .init("useMetricUnits", type: .bool),
        .init("callsignNotesDisplayMode", type: .string),
    ]

    // MARK: - Tab Configuration

    private static let tabConfig: [SyncableSetting] = [
        .init("tabOrder", type: .data),
        .init("hiddenTabs", type: .data),
    ]

    // MARK: - Equipment Lists

    private static let equipmentLists: [SyncableSetting] = [
        .init("userAntennaList", type: .stringArray),
        .init("userKeyList", type: .stringArray),
        .init("userMicList", type: .stringArray),
        .init("userRadioList", type: .stringArray),
    ]

    // MARK: - Station Profiles

    private static let stationProfiles: [SyncableSetting] = [
        .init("stationProfiles", type: .data),
    ]

    // MARK: - Activity Log Settings

    private static let activityLogSettings: [SyncableSetting] = [
        .init("huntedSpotBehavior", type: .string),
        .init("activityLogDailyGoalEnabled", type: .bool),
        .init("activityLogDailyGoal", type: .int),
        .init("spotMaxAgeMinutes", type: .int),
        .init("spotRegionFilter", type: .string),
    ]

    // MARK: - Keyboard & Command Row

    private static let keyboardConfig: [SyncableSetting] = [
        .init("keyboardRowShowNumbers", type: .bool),
        .init("keyboardRowSymbols", type: .string),
        .init("commandRowEnabled", type: .bool),
        .init("commandRowCommands", type: .string),
    ]

    // MARK: - Dashboard Metrics

    private static let dashboardMetrics: [SyncableSetting] = [
        .init("dashboardMetric1", type: .string),
        .init("dashboardMetric2", type: .string),
    ]

    // MARK: - Misc

    private static let miscSettings: [SyncableSetting] = [
        .init("activitiesServerEnabled", type: .bool),
        .init("webSDRAdvancedMode", type: .bool),
    ]
}
