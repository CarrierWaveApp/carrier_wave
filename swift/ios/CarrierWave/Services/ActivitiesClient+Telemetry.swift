import CarrierWaveCore
import CryptoKit
import Foundation
import OSLog

// MARK: - Upload Error Telemetry

extension ActivitiesClient {
    /// Report aggregated, anonymized upload error telemetry to the activities server.
    /// Only sends error categories and counts — no callsigns, QSO data, or raw messages.
    func reportUploadErrors(_ diagnostics: [UploadErrorDiagnostic]) async {
        guard !diagnostics.isEmpty else {
            return
        }

        // Rate limit: at most once per 5 minutes
        let now = Date()
        if let lastReport = Self.lastTelemetryReport,
           now.timeIntervalSince(lastReport) < Self.telemetryMinInterval
        {
            return
        }

        guard let authToken = await ensureAuthToken() else {
            return
        }

        let telemetryItems = diagnostics.map { diagnostic in
            UploadErrorTelemetryItem(
                service: diagnostic.service.rawValue,
                category: diagnostic.category.rawValue,
                messageHash: Self.hashMessage(diagnostic.message),
                affectedCount: diagnostic.affectedCount,
                isTransient: diagnostic.category.isTransient,
                appVersion: Self.appVersion,
                osVersion: Self.osVersion
            )
        }

        let body = UploadErrorTelemetryRequest(errors: telemetryItems)

        do {
            let url = try buildURL(baseURL, path: "/v1/telemetry/upload-errors")
            var request = try buildRequest(url: url, method: "POST", authToken: authToken)
            request.httpBody = try JSONEncoder.activitiesEncoder.encode(body)

            let (_, response) = try await performRequest(request)

            // Accept any 2xx response; don't throw on server errors for telemetry
            if let httpResponse = response as? HTTPURLResponse,
               (200 ... 299).contains(httpResponse.statusCode)
            {
                Self.lastTelemetryReport = now
            }
        } catch {
            // Telemetry is best-effort — silently ignore failures
            Self.logger.debug("Upload error telemetry failed: \(error.localizedDescription)")
        }
    }

    // MARK: Private

    private static var lastTelemetryReport: Date?

    /// Minimum interval between telemetry reports (5 minutes)
    private static let telemetryMinInterval: TimeInterval = 300

    private static let appVersion: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

    private static let osVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }()

    /// Hash error message for privacy — only send the hash, never the raw message.
    private static func hashMessage(_ message: String) -> String {
        let data = Data(message.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - UploadErrorTelemetryRequest

struct UploadErrorTelemetryRequest: Encodable {
    let errors: [UploadErrorTelemetryItem]
}

// MARK: - UploadErrorTelemetryItem

struct UploadErrorTelemetryItem: Encodable {
    enum CodingKeys: String, CodingKey {
        case service
        case category
        case messageHash = "message_hash"
        case affectedCount = "affected_count"
        case isTransient = "is_transient"
        case appVersion = "app_version"
        case osVersion = "os_version"
    }

    let service: String
    let category: String
    let messageHash: String
    let affectedCount: Int
    let isTransient: Bool
    let appVersion: String
    let osVersion: String
}
