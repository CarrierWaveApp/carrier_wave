import Foundation

// MARK: - DeviceMetadata

/// Device and app metadata included with MetricKit payloads for server-side grouping.
/// Nonisolated so Codable witnesses can run off the main actor (PerfUploader is an actor).
nonisolated struct DeviceMetadata: Codable {
    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case locale
    }

    let appVersion: String
    let buildNumber: String
    let deviceModel: String
    let osVersion: String
    let locale: String

    static func current() -> DeviceMetadata {
        let info = Bundle.main.infoDictionary
        let version = ProcessInfo.processInfo.operatingSystemVersion

        return DeviceMetadata(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: info?["CFBundleVersion"] as? String ?? "unknown",
            deviceModel: rawDeviceModel(),
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            locale: Locale.current.identifier
        )
    }

    // MARK: Private

    /// Raw hardware identifier (e.g. "iPhone18,1") via utsname.
    private static func rawDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(
                to: CChar.self,
                capacity: 1
            ) { String(cString: $0) }
        }
    }
}
