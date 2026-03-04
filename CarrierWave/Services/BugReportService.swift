import CarrierWaveData
import Foundation
import UIKit

// MARK: - BugCategory

enum BugCategory: String, CaseIterable {
    case syncIssue = "Sync Issue"
    case uiProblem = "UI Problem"
    case crash = "Crash"
    case other = "Other"
}

// MARK: - BugReportService

@MainActor
final class BugReportService {
    // MARK: Lifecycle

    init(
        qrzClient: QRZClient? = nil,
        lofiClient: LoFiClient? = nil,
        lotwClient: LoTWClient? = nil,
        hamrsClient: HAMRSClient? = nil,
        potaAuth: POTAAuthService? = nil,
        iCloudMonitor: ICloudMonitor? = nil
    ) {
        self.qrzClient = qrzClient
        self.lofiClient = lofiClient
        self.lotwClient = lotwClient
        self.hamrsClient = hamrsClient
        self.potaAuth = potaAuth
        self.iCloudMonitor = iCloudMonitor
    }

    // MARK: Internal

    // MARK: - Device Info

    struct DeviceInfo {
        let appVersion: String
        let buildNumber: String
        let iosVersion: String
        let deviceModel: String
        let debugMode: Bool
    }

    // MARK: - Service Status

    struct ServiceStatus {
        let qrzConfigured: Bool
        let potaConfigured: Bool
        let lofiConfigured: Bool
        let lofiLinked: Bool
        let lofiCallsign: String?
        let lofiLastSyncMillis: Int64
        let lotwConfigured: Bool
        let hamrsConfigured: Bool
        let iCloudStatus: String
    }

    // MARK: - Callsign Info

    struct CallsignInfo {
        let currentCallsign: String?
        let previousCallsigns: [String]
    }

    // MARK: - Report Context

    /// Groups all context data needed to format a bug report
    struct ReportContext {
        let category: BugCategory
        let description: String
        let deviceInfo: DeviceInfo
        let serviceStatus: ServiceStatus
        let callsignInfo: CallsignInfo
        let syncLogs: String
    }

    func collectDeviceInfo(debugMode: Bool) -> DeviceInfo {
        let appVersion =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let iosVersion = UIDevice.current.systemVersion
        let deviceModel = deviceModelName()

        return DeviceInfo(
            appVersion: appVersion,
            buildNumber: buildNumber,
            iosVersion: iosVersion,
            deviceModel: deviceModel,
            debugMode: debugMode
        )
    }

    func collectServiceStatus() -> ServiceStatus {
        let qrzConfigured = qrzClient?.hasApiKey() ?? false
        let potaConfigured = potaAuth?.isAuthenticated ?? false
        let lofiConfigured = lofiClient?.hasCredentials() ?? false
        let lofiLinked = lofiClient?.isLinked ?? false
        let lofiCallsign = lofiClient?.getCallsign()
        let lofiLastSyncMillis = lofiClient?.getLastSyncMillis() ?? 0
        let lotwConfigured = lotwClient?.hasCredentials() ?? false
        let hamrsConfigured = hamrsClient?.hasApiKey() ?? false
        let iCloudStatus = iCloudMonitor?.statusDescription ?? "Unknown"

        return ServiceStatus(
            qrzConfigured: qrzConfigured,
            potaConfigured: potaConfigured,
            lofiConfigured: lofiConfigured,
            lofiLinked: lofiLinked,
            lofiCallsign: lofiCallsign,
            lofiLastSyncMillis: lofiLastSyncMillis,
            lotwConfigured: lotwConfigured,
            hamrsConfigured: hamrsConfigured,
            iCloudStatus: iCloudStatus
        )
    }

    @MainActor
    func collectCallsignInfo() -> CallsignInfo {
        let currentCallsign = CallsignAliasService.shared.getCurrentCallsign()
        let previousCallsigns = CallsignAliasService.shared.getPreviousCallsigns()
        return CallsignInfo(
            currentCallsign: currentCallsign,
            previousCallsigns: previousCallsigns
        )
    }

    func collectSyncLogs() -> String {
        let entries = Array(SyncDebugLog.shared.logEntries.prefix(50))
        guard !entries.isEmpty else {
            return "No sync logs available"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return entries.map { entry in
            let timestamp = dateFormatter.string(from: entry.timestamp)
            let service = entry.service?.displayName ?? "General"
            return "[\(timestamp)] [\(entry.level.rawValue)] [\(service)] \(entry.message)"
        }.joined(separator: "\n")
    }

    func formatReport(_ context: ReportContext) -> String {
        let currentCallsignDisplay = context.callsignInfo.currentCallsign ?? "Not configured"
        let previousCallsignsDisplay =
            context.callsignInfo.previousCallsigns.isEmpty
                ? "None"
                : context.callsignInfo.previousCallsigns.joined(separator: ", ")

        return """
        BUG REPORT
        ==========

        Category: \(context.category.rawValue)

        Description:
        \(context.description)

        DEVICE INFO
        -----------
        App Version: \(context.deviceInfo.appVersion)
        Build Number: \(context.deviceInfo.buildNumber)
        iOS Version: \(context.deviceInfo.iosVersion)
        Device: \(context.deviceInfo.deviceModel)
        Debug Mode: \(context.deviceInfo.debugMode ? "Enabled" : "Disabled")

        CALLSIGN INFO
        -------------
        Current Callsign: \(currentCallsignDisplay)
        Previous Callsigns: \(previousCallsignsDisplay)

        SERVICE STATUS
        --------------
        QRZ: \(context.serviceStatus.qrzConfigured ? "Configured" : "Not configured")
        POTA: \(context.serviceStatus.potaConfigured ? "Configured" : "Not configured")
        LoFi: \(context.serviceStatus.lofiConfigured ? "Configured" : "Not configured")
        LoTW: \(context.serviceStatus.lotwConfigured ? "Configured" : "Not configured")
        HAMRS: \(context.serviceStatus.hamrsConfigured ? "Configured" : "Not configured")
        iCloud: \(context.serviceStatus.iCloudStatus)

        LOFI DETAILS
        ------------
        Linked: \(context.serviceStatus.lofiLinked ? "Yes" : "No")
        Callsign: \(context.serviceStatus.lofiCallsign ?? "Not set")
        Last Sync: \(formatLoFiLastSync(context.serviceStatus.lofiLastSyncMillis))

        RECENT SYNC LOGS
        ----------------
        \(context.syncLogs)
        """
    }

    // MARK: Private

    private let qrzClient: QRZClient?
    private let lofiClient: LoFiClient?
    private let lotwClient: LoTWClient?
    private let hamrsClient: HAMRSClient?
    private let potaAuth: POTAAuthService?
    private let iCloudMonitor: ICloudMonitor?

    private func deviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "Unknown"
            }
        }
        return mapDeviceIdentifier(identifier)
    }

    private func formatLoFiLastSync(_ millis: Int64) -> String {
        guard millis > 0 else {
            return "Never synced (0)"
        }
        let date = Date(timeIntervalSince1970: Double(millis) / 1_000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return "\(formatter.string(from: date)) (millis: \(millis))"
    }

    private func mapDeviceIdentifier(_ identifier: String) -> String {
        // Common iPhone mappings
        let mappings: [String: String] = [
            // iPhone 15 series
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            // iPhone 14 series
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            // iPhone 13 series
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            // iPhone 12 series
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            // iPhone 11 series
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            // iPhone SE
            "iPhone14,6": "iPhone SE (3rd generation)",
            "iPhone12,8": "iPhone SE (2nd generation)",
            // iPad Pro
            "iPad13,4": "iPad Pro 11-inch (3rd generation)",
            "iPad13,5": "iPad Pro 11-inch (3rd generation)",
            "iPad13,6": "iPad Pro 11-inch (3rd generation)",
            "iPad13,7": "iPad Pro 11-inch (3rd generation)",
            "iPad13,8": "iPad Pro 12.9-inch (5th generation)",
            "iPad13,9": "iPad Pro 12.9-inch (5th generation)",
            "iPad13,10": "iPad Pro 12.9-inch (5th generation)",
            "iPad13,11": "iPad Pro 12.9-inch (5th generation)",
            // Simulator
            "x86_64": "Simulator",
            "arm64": "Simulator",
        ]

        return mappings[identifier] ?? identifier
    }
}
