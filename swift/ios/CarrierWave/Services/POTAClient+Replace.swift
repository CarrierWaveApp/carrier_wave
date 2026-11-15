import CarrierWaveCwFfi
import CarrierWaveData
import UIKit

// MARK: - POTAUploadReplacePlan

/// Whether the log uploaded for one activation can still be replaced on POTA,
/// and which jobs have to be removed first. POTA lets the uploader delete a log
/// for 24 hours after uploading it; the rule itself lives in cw-core
/// (`pota_log_replace_plan`) so every platform decides the same way.
struct POTAUploadReplacePlan: Equatable {
    // MARK: Lifecycle

    init(jobs: [POTAJob], now: Date = Date()) {
        let windows = jobs.map { job in
            FfiPotaJobWindow(
                jobId: Int64(job.jobId),
                status: Int64(job.status.rawValue),
                selfDeleteSecondsRemaining: job.selfDeleteSecondsRemaining(at: now)
            )
        }
        let plan = potaLogReplacePlan(jobs: windows, elapsedSeconds: 0)
        removeJobIds = plan.removeJobIds.map(Int.init)
        secondsLeft = plan.secondsLeft
        isWindowExpired = plan.blocker == .windowExpired
    }

    // MARK: Internal

    /// Jobs to remove before uploading the corrected log. Empty when blocked.
    let removeJobIds: [Int]
    /// Seconds until the first of those jobs can no longer be removed.
    let secondsLeft: TimeInterval
    /// True when an uploaded log exists but its 24-hour window has closed.
    let isWindowExpired: Bool

    var canReplace: Bool {
        !removeJobIds.isEmpty
    }

    /// "5h 12m", "42m", or "under a minute".
    var timeLeftText: String {
        Self.timeLeftText(secondsLeft)
    }

    static func timeLeftText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes < 1 {
            return "under a minute"
        }
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

// MARK: - POTAClient Log Removal

extension POTAClient {
    /// Delete one upload job from POTA. Only works for the uploader, within 24
    /// hours of the upload; POTA rejects the request otherwise.
    func removeJob(jobId: Int) async throws {
        let debugLog = SyncDebugLog.shared
        let start = Date()
        let token = try await authService.ensureValidToken()
        let path = potaRemoveJobPath(jobId: Int64(jobId))

        guard let url = URL(string: "\(baseURL)\(path)") else {
            debugLog.error("Invalid URL for POTA job removal", service: .pota)
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        debugLog.info("POST \(path)", service: .pota)

        let (data, response) = try await URLSession.shared.data(for: request)
        let durationMs = Int(Date().timeIntervalSince(start) * 1_000)

        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog.error("Invalid response (not HTTP) (\(durationMs)ms)", service: .pota)
            throw POTAError.fetchFailed("Invalid response")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            debugLog.error(
                "Job \(jobId) removal failed: \(httpResponse.statusCode) - \(body)",
                service: .pota
            )
            throw POTAError.fetchFailed(
                "POTA would not delete upload #\(jobId) (HTTP \(httpResponse.statusCode))"
            )
        }

        debugLog.info(
            "Removed POTA job \(jobId): HTTP \(httpResponse.statusCode) (\(durationMs)ms)",
            service: .pota
        )
    }

    /// Remove every job the plan names. Throws on the first failure, leaving
    /// later jobs in place, so the caller never re-uploads over a log that is
    /// still on POTA.
    func removeJobs(in plan: POTAUploadReplacePlan) async throws {
        for jobId in plan.removeJobIds {
            try await removeJob(jobId: jobId)
        }
    }
}
