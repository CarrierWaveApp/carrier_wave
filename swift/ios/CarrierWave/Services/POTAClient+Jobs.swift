import CarrierWaveData
import Foundation

// MARK: - POTAClient Job Status Methods

extension POTAClient {
    /// Page size requested from `/user/jobs`. Legacy backends ignore the query
    /// and return every job in one array.
    static let jobsPageSize = 100

    /// Upper bound on pages fetched in one call, so a server that keeps
    /// reporting a larger `count` cannot loop forever.
    static let jobsMaxPages = 50

    func fetchJobs() async throws -> [POTAJob] {
        let debugLog = SyncDebugLog.shared
        let fetchStart = Date()
        var jobs: [POTAJob] = []
        var page = 1

        while true {
            let result = try await fetchJobsPage(page: page, size: Self.jobsPageSize)
            jobs.append(contentsOf: result.entries)
            if result.isLegacyArray || result.entries.isEmpty || jobs.count >= result.count {
                break
            }
            page += 1
            if page > Self.jobsMaxPages {
                debugLog.warning(
                    "Stopped paging POTA jobs after \(Self.jobsMaxPages) pages "
                        + "(\(jobs.count) of \(result.count))",
                    service: .pota
                )
                break
            }
        }

        let fetchDurationMs = Int(Date().timeIntervalSince(fetchStart) * 1_000)

        // Log job status breakdown
        let statusCounts = Dictionary(grouping: jobs, by: \.status)
            .mapValues(\.count)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.displayName)=\($0.value)" }
            .joined(separator: ", ")
        let totalQSOs = jobs.reduce(0) { $0 + $1.totalQsos }
        let totalInserted = jobs.reduce(0) { $0 + $1.insertedQsos }
        debugLog.info(
            "Fetched \(jobs.count) POTA jobs in \(page) page(s) (\(fetchDurationMs)ms): "
                + "\(statusCounts). totalQSOs=\(totalQSOs), inserted=\(totalInserted)",
            service: .pota
        )

        return jobs
    }

    /// Fetch one page of `/user/jobs`. `showAll=1` keeps removed jobs in the
    /// paginated response, matching what the legacy array always contained.
    func fetchJobsPage(page: Int, size: Int) async throws -> POTAJobsPage {
        let debugLog = SyncDebugLog.shared
        let fetchStart = Date()
        let token = try await authService.ensureValidToken()

        guard let url = URL(string: "\(baseURL)/user/jobs?showAll=1&page=\(page)&size=\(size)") else {
            debugLog.error("Invalid URL for POTA jobs", service: .pota)
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        debugLog.debug("GET /user/jobs?showAll=1&page=\(page)&size=\(size)", service: .pota)

        let (data, response) = try await URLSession.shared.data(for: request)
        let fetchDurationMs = Int(Date().timeIntervalSince(fetchStart) * 1_000)

        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog.error(
                "Invalid response (not HTTP) (\(fetchDurationMs)ms)", service: .pota
            )
            throw POTAError.fetchFailed("Invalid response")
        }

        debugLog.debug(
            "Jobs response: HTTP \(httpResponse.statusCode), "
                + "\(data.count) bytes (\(fetchDurationMs)ms)",
            service: .pota
        )

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            debugLog.error(
                "Jobs fetch failed: \(httpResponse.statusCode) - \(body)", service: .pota
            )
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let result = try JSONDecoder().decode(POTAJobsPage.self, from: data)
        debugLog.debug(
            "Jobs page \(page): \(result.entries.count) of \(result.count) "
                + "(\(result.isLegacyArray ? "legacy array" : "paginated"))",
            service: .pota
        )
        return result
    }

    /// Fetch detailed information for a specific job including errors and warnings
    func fetchJobDetails(jobId: Int) async throws -> POTAJobDetails {
        let debugLog = SyncDebugLog.shared
        let fetchStart = Date()
        let token = try await authService.ensureValidToken()

        guard let url = URL(string: "\(baseURL)/user/jobs/details/\(jobId)") else {
            debugLog.error("Invalid URL for POTA job details", service: .pota)
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        debugLog.debug("GET /user/jobs/details/\(jobId)", service: .pota)

        let (data, response) = try await URLSession.shared.data(for: request)
        let fetchDurationMs = Int(Date().timeIntervalSince(fetchStart) * 1_000)

        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog.error(
                "Invalid response (not HTTP) (\(fetchDurationMs)ms)", service: .pota
            )
            throw POTAError.fetchFailed("Invalid response")
        }

        debugLog.debug(
            "Job details response: HTTP \(httpResponse.statusCode), "
                + "\(data.count) bytes (\(fetchDurationMs)ms)",
            service: .pota
        )

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            debugLog.error(
                "Job details fetch failed: \(httpResponse.statusCode) - \(body)", service: .pota
            )
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let details = try JSONDecoder().decode(POTAJobDetails.self, from: data)
        logJobDetails(jobId: jobId, details: details, durationMs: fetchDurationMs)
        return details
    }

    /// Find jobs that completed but had zero QSOs inserted (all rejected by POTA).
    /// Only checks jobs from the last 7 days to avoid unbounded detail fetches.
    func suspectJobs(from jobs: [POTAJob]) -> [POTAJob] {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return jobs.filter { job in
            job.status == .completed
                && job.totalQsos > 0
                && job.insertedQsos == 0
                && job.submitted > cutoff
        }
    }

    /// Log detailed job information for debugging, parsing POTA error strings semantically.
    private func logJobDetails(jobId: Int, details: POTAJobDetails, durationMs: Int) {
        let debugLog = SyncDebugLog.shared
        debugLog.info(
            "Job \(jobId) details (\(durationMs)ms): "
                + "\(details.errors.count) errors, \(details.warnings.count) warnings"
                + (details.stationCallsign.map { ", call=\($0)" } ?? ""),
            service: .pota
        )

        if !details.errors.isEmpty {
            logParsedJobMessages(jobId: jobId, messages: details.errors, level: .error)
        }
        if !details.warnings.isEmpty {
            logParsedJobMessages(jobId: jobId, messages: details.warnings, level: .warning)
        }

        if let totals = details.totals {
            for (key, breakdown) in totals {
                let modes = "CW=\(breakdown.cw) DATA=\(breakdown.data) PHONE=\(breakdown.phone)"
                debugLog.debug(
                    "  Job \(jobId) [\(key)]: \(breakdown.activationPark ?? "n/a") "
                        + "\(breakdown.activationDate ?? "n/a") \(modes) T=\(breakdown.total)",
                    service: .pota
                )
            }
        }
    }

    enum JobLogLevel { case error, warning }

    /// Parse and log POTA job messages with semantic grouping.
    /// Groups by message so "Ignoring duplicate QSO" x11 shows once with a count.
    private func logParsedJobMessages(
        jobId: Int, messages: [String], level: JobLogLevel
    ) {
        let debugLog = SyncDebugLog.shared
        let parsed = messages.map { POTAJobErrorParser.parse($0) }

        // Group by message to avoid flooding the log
        var messageCounts: [(String, Int)] = []
        var seen: [String: Int] = [:]
        for msg in parsed {
            if let idx = seen[msg.message] {
                messageCounts[idx].1 += 1
            } else {
                seen[msg.message] = messageCounts.count
                messageCounts.append((msg.message, 1))
            }
        }

        for (message, count) in messageCounts {
            let countStr = count > 1 ? " (×\(count))" : ""
            let text = "  Job \(jobId): \(message)\(countStr)"
            switch level {
            case .error: debugLog.error(text, service: .pota)
            case .warning: debugLog.warning(text, service: .pota)
            }
        }
    }
}
