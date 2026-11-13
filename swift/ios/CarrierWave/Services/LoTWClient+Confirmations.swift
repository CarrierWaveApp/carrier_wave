import CarrierWaveData
import Foundation

// MARK: - LoTWClient QSL Confirmation Fetching

@MainActor
extension LoTWClient {
    /// Fetch QSOs that were QSL-confirmed since the given date.
    /// Uses qso_qsl=yes + qso_qslsince to catch confirmations that arrived
    /// after the QSO was already downloaded via qso_qsorxsince.
    func fetchNewConfirmations(
        forCallsigns callsigns: [String] = [], qslSince: Date
    ) async throws -> LoTWResponse {
        let credentials = try getCredentials()
        let debugLog = SyncDebugLog.shared
        debugLog.info(
            "Fetching LoTW confirmations since \(formatDate(qslSince))",
            service: .lotw
        )

        if callsigns.isEmpty {
            return try await fetchConfirmationsForCallsign(
                nil, credentials: credentials, qslSince: qslSince
            )
        }

        var allQSOs: [LoTWFetchedQSO] = []
        var latestQSL: Date?
        var latestQSORx: Date?

        for callsign in callsigns {
            let response = try await fetchConfirmationsForCallsign(
                callsign, credentials: credentials, qslSince: qslSince
            )
            allQSOs.append(contentsOf: response.qsos)
            if let qsl = response.lastQSL, latestQSL == nil || qsl > latestQSL! {
                latestQSL = qsl
            }
            if let rx = response.lastQSORx, latestQSORx == nil || rx > latestQSORx! {
                latestQSORx = rx
            }
            if callsign != callsigns.last {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }

        debugLog.info(
            "Fetched \(allQSOs.count) confirmed QSOs from LoTW", service: .lotw
        )
        return LoTWResponse(
            qsos: allQSOs, lastQSL: latestQSL,
            lastQSORx: latestQSORx, recordCount: allQSOs.count
        )
    }

    /// Fetch confirmed QSOs for a single callsign using qso_qsl=yes + qso_qslsince
    private func fetchConfirmationsForCallsign(
        _ callsign: String?,
        credentials: (username: String, password: String),
        qslSince: Date
    ) async throws -> LoTWResponse {
        var components = URLComponents(string: baseURL)!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "login", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password),
            URLQueryItem(name: "qso_query", value: "1"),
            URLQueryItem(name: "qso_qsl", value: "yes"),
            URLQueryItem(name: "qso_qslsince", value: dateFormatter.string(from: qslSince)),
            URLQueryItem(name: "qso_mydetail", value: "yes"),
            URLQueryItem(name: "qso_qsldetail", value: "yes"),
            URLQueryItem(name: "qso_withown", value: "yes"),
        ]

        if let callsign, !callsign.isEmpty {
            queryItems.append(URLQueryItem(name: "qso_owncall", value: callsign))
        }

        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await dataWithRetry(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            if statusCode == 403 || statusCode == 503 {
                throw LoTWError.serviceError("HTTP \(statusCode) - rate limited")
            } else if statusCode != 200 {
                throw LoTWError.serviceError("HTTP \(statusCode)")
            }
        }

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw LoTWError.invalidResponse("Cannot decode response as UTF-8")
        }

        guard responseString.contains("<EOH>") || responseString.contains("<eoh>") else {
            if isAuthenticationError(responseString) {
                throw LoTWError.authenticationFailed
            }
            throw LoTWError.serviceError(String(responseString.prefix(200)))
        }

        return parseADIFResponse(responseString)
    }
}
