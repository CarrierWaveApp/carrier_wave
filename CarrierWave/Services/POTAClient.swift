// POTA (Parks on the Air) ADIF export and upload functionality.
//
// Groups QSOs by UTC date and park reference, generating separate
// ADIF files suitable for upload to pota.app.

import CarrierWaveData
import Foundation
import SwiftData

// MARK: - POTAError

enum POTAError: Error, LocalizedError {
    case notAuthenticated
    case uploadFailed(String)
    case fetchFailed(String)
    case invalidParkReference
    case networkError(Error)
    case maintenanceWindow

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Not authenticated with POTA"
        case let .uploadFailed(reason):
            "POTA upload failed: \(reason)"
        case let .fetchFailed(reason):
            "POTA fetch failed: \(reason)"
        case .invalidParkReference:
            "Invalid park reference format"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case .maintenanceWindow:
            "POTA is in maintenance (0000-0400 UTC)"
        }
    }
}

// MARK: - POTAActivationsResponse

struct POTAActivationsResponse: Decodable, @unchecked Sendable {
    let count: Int
    let activations: [POTARemoteActivation]
}

// MARK: - POTARemoteActivation

struct POTARemoteActivation: Decodable, @unchecked Sendable {
    enum CodingKeys: String, CodingKey {
        case callsign
        case date
        case reference
        case name
        case total
        case cw
        case data
        case phone
        case parktypeDesc
        case locationDesc
        case firstQso = "firstQSO"
        case lastQso = "lastQSO"
    }

    let callsign: String
    let date: String
    let reference: String
    let name: String?
    let parktypeDesc: String?
    let locationDesc: String?
    let firstQso: String?
    let lastQso: String?
    let total: Int
    let cw: Int
    let data: Int
    let phone: Int
}

// MARK: - POTALogbookResponse

struct POTALogbookResponse: Decodable, @unchecked Sendable {
    let count: Int
    let entries: [POTARemoteQSO]
}

// MARK: - POTARemoteQSO

struct POTARemoteQSO: Decodable, @unchecked Sendable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        qsoId = try container.decode(Int64.self, forKey: .qsoId)
        qsoDateTime = try container.decode(String.self, forKey: .qsoDateTime)
        stationCallsign = try container.decode(String.self, forKey: .stationCallsign)
        operatorCallsign = try container.decodeIfPresent(String.self, forKey: .operatorCallsign)
        workedCallsign = try container.decode(String.self, forKey: .workedCallsign)
        band = try container.decodeIfPresent(String.self, forKey: .band)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        mySig = try container.decodeIfPresent(String.self, forKey: .mySig)
        mySigInfo = try container.decodeIfPresent(String.self, forKey: .mySigInfo)
        reference = try container.decodeIfPresent(String.self, forKey: .reference)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        locationDesc = try container.decodeIfPresent(String.self, forKey: .locationDesc)
        sig = try container.decodeIfPresent(String.self, forKey: .sig)
        rstSent = Self.decodeStringOrInt(container: container, key: .rstSent)
        rstRcvd = Self.decodeStringOrInt(container: container, key: .rstRcvd)
        sigInfo = Self.decodeStringOrInt(container: container, key: .sigInfo)
        p2pMatch = Self.decodeStringOrInt(container: container, key: .p2pMatch)
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case qsoId
        case band
        case mode
        case reference
        case name
        case sig
        case qsoDateTime
        case stationCallsign = "station_callsign"
        case operatorCallsign = "operator_callsign"
        case workedCallsign = "worked_callsign"
        case rstSent = "rst_sent"
        case rstRcvd = "rst_rcvd"
        case mySig = "my_sig"
        case mySigInfo = "my_sig_info"
        case locationDesc
        case sigInfo = "sig_info"
        case p2pMatch
    }

    let qsoId: Int64
    let qsoDateTime: String
    let stationCallsign: String
    let operatorCallsign: String?
    let workedCallsign: String
    let band: String?
    let mode: String?
    let rstSent: String?
    let rstRcvd: String?
    let mySig: String?
    let mySigInfo: String?
    let reference: String?
    let name: String?
    let locationDesc: String?
    let sig: String?
    let sigInfo: String?
    let p2pMatch: String?

    // MARK: Private

    private static func decodeStringOrInt(
        container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

// MARK: - POTAFetchedQSO

struct POTAFetchedQSO {
    let callsign: String
    let band: String
    let mode: String
    let timestamp: Date
    let rstSent: String?
    let rstReceived: String?
    let myCallsign: String
    let parkReference: String?
    let myState: String?
    let potaQsoId: Int64
}

// MARK: - POTAUploadResult

struct POTAUploadResult {
    let success: Bool
    let qsosAccepted: Int
    let message: String?
}

// MARK: - POTAClient

@MainActor
final class POTAClient {
    // MARK: Lifecycle

    init(authService: POTAAuthService) {
        self.authService = authService
    }

    // MARK: Internal

    let baseURL = "https://api.pota.app"
    let authService: POTAAuthService

    // Maintenance window methods in POTAClient+Maintenance.swift

    /// Get all unique park references from QSOs (excludes nil and empty)
    static func groupQSOsByPark(_ qsos: [QSO]) -> [String: [QSO]] {
        Dictionary(grouping: qsos.filter { $0.parkReference?.isEmpty == false }) {
            $0.parkReference!
        }
    }

    /// Split comma-separated park references (e.g., "US-1044, US-3791" -> ["US-1044", "US-3791"])
    /// Handles two-fer, three-fer, etc. activations where multiple parks are activated simultaneously.
    /// Delegates to CarrierWaveCore's ParkReference for the actual implementation.
    nonisolated static func splitParkReferences(_ parkRef: String) -> [String] {
        ParkReference.split(parkRef)
    }

    /// Check if park reference contains multiple parks (two-fer, three-fer, etc.)
    /// Delegates to CarrierWaveCore's ParkReference for the actual implementation.
    nonisolated static func isMultiPark(_ parkRef: String) -> Bool {
        ParkReference.isMultiPark(parkRef)
    }

    func uploadActivation(parkReference: String, qsos: [QSO]) async throws -> POTAUploadResult {
        let debugLog = SyncDebugLog.shared

        guard validateParkReference(parkReference) else {
            debugLog.error(
                "Invalid park reference format: '\(parkReference)' (expected format like K-1234)",
                service: .pota
            )
            throw POTAError.invalidParkReference
        }

        let normalizedParkRef = parkReference.uppercased()
        let token = try await authService.ensureValidToken()

        // Filter to QSOs that contain this park (supports multi-park/two-fer references
        // like "US-1044, US-3791" when uploading to just "US-1044")
        let parkQSOs = qsos.filter {
            guard let ref = $0.parkReference else {
                return false
            }
            return ParkReference.hasOverlap(ref, normalizedParkRef)
        }
        guard !parkQSOs.isEmpty else {
            debugLog.info("No QSOs to upload for park \(normalizedParkRef)", service: .pota)
            return POTAUploadResult(
                success: true, qsosAccepted: 0, message: "No QSOs for this park"
            )
        }

        guard
            let requestData = buildUploadRequest(
                parkReference: normalizedParkRef, qsos: parkQSOs, token: token
            )
        else {
            throw POTAError.uploadFailed("Failed to build request")
        }

        debugLog.info(
            "Uploading \(parkQSOs.count) QSOs to park \(normalizedParkRef)", service: .pota
        )
        debugLog.debug(
            "POST /adif - location=\(requestData.location), ref=\(normalizedParkRef), file=\(requestData.filename)",
            service: .pota
        )

        let (data, response) = try await URLSession.shared.data(for: requestData.request)

        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog.error("Invalid response (not HTTP)", service: .pota)
            throw POTAError.uploadFailed("Invalid response")
        }

        return try handleUploadResponse(
            data: data, httpResponse: httpResponse,
            parkReference: normalizedParkRef, qsoCount: parkQSOs.count
        )
    }

    /// Upload activation with attempt recording for debugging
    func uploadActivationWithRecording(
        parkReference: String, qsos: [QSO], modelContext: ModelContext
    ) async throws -> POTAUploadResult {
        let debugLog = SyncDebugLog.shared
        let startTime = Date()
        let normalizedParkRef = try validateAndNormalizePark(parkReference)
        let token = try await acquireTokenWithLogging(for: normalizedParkRef)

        let parkQSOs = filterQSOsForParkRef(qsos, parkRef: normalizedParkRef)
        guard !parkQSOs.isEmpty else {
            debugLog.info("No QSOs to upload for park \(normalizedParkRef)", service: .pota)
            return POTAUploadResult(
                success: true, qsosAccepted: 0, message: "No QSOs for this park"
            )
        }

        guard
            let requestData = buildUploadRequest(
                parkReference: normalizedParkRef, qsos: parkQSOs, token: token
            )
        else {
            debugLog.error(
                "buildUploadRequest returned nil for park \(normalizedParkRef)", service: .pota
            )
            throw POTAError.uploadFailed("Failed to build request")
        }

        let attempt = createUploadAttempt(
            startTime: startTime, parkReference: normalizedParkRef,
            requestData: requestData, modelContext: modelContext
        )
        logUploadRequestDetails(requestData, parkRef: normalizedParkRef)

        return try await executeUploadWithRecording(
            request: requestData.request, attempt: attempt, startTime: startTime,
            parkReference: normalizedParkRef, qsoCount: requestData.qsoCount
        )
    }

    // MARK: - Download Methods

    func fetchActivations() async throws -> [POTARemoteActivation] {
        let token = try await authService.ensureValidToken()

        guard let url = URL(string: "\(baseURL)/user/activations?all=1") else {
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POTAError.fetchFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                // Invalidate the cached token so next call will re-authenticate
                authService.invalidateToken()
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let decoded = try JSONDecoder().decode(POTAActivationsResponse.self, from: data)
        return decoded.activations
    }

    func fetchActivationQSOs(
        reference: String, date: String, page: Int = 1, pageSize: Int = 100
    ) async throws -> POTALogbookResponse {
        let token = try await authService.ensureValidToken()

        var components = URLComponents(string: "\(baseURL)/user/logbook")!
        components.queryItems = [
            URLQueryItem(name: "activatorOnly", value: "1"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(pageSize)),
            URLQueryItem(name: "startDate", value: date),
            URLQueryItem(name: "endDate", value: date),
            URLQueryItem(name: "reference", value: reference),
        ]

        guard let url = components.url else {
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POTAError.fetchFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try JSONDecoder().decode(POTALogbookResponse.self, from: data)
    }

    func fetchAllActivationQSOs(reference: String, date: String) async throws -> [POTARemoteQSO] {
        var allQSOs: [POTARemoteQSO] = []
        var page = 1
        let pageSize = 100

        while true {
            let response = try await fetchActivationQSOs(
                reference: reference, date: date, page: page, pageSize: pageSize
            )
            allQSOs.append(contentsOf: response.entries)

            NSLog(
                "[POTA] Pagination %@ %@: page=%d, fetched=%d, total=%d",
                reference, date, page, response.entries.count, allQSOs.count
            )

            // Use actual count, not hardcoded page limit
            // Previous 10-page cap silently truncated activations with >1000 QSOs
            if response.entries.count < pageSize {
                break
            }
            page += 1
        }

        return allQSOs
    }

    // fetchAllQSOs, checkpoint methods, and fetchJobs are in POTAClient+Checkpoint.swift

    func convertToFetchedQSO(
        _ qso: POTARemoteQSO, activation: POTARemoteActivation
    ) -> POTAFetchedQSO? {
        guard let band = qso.band, let mode = qso.mode else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let timestamp = formatter.date(from: qso.qsoDateTime) ?? Date()

        let myState = activation.locationDesc?.split(separator: "-").last.map(String.init)

        // Use mySigInfo from the QSO if available (more accurate), fall back to activation reference
        let parkRef = qso.mySigInfo.nonEmpty ?? activation.reference

        return POTAFetchedQSO(
            callsign: qso.workedCallsign, band: band, mode: mode, timestamp: timestamp,
            rstSent: qso.rstSent, rstReceived: qso.rstRcvd,
            myCallsign: qso.stationCallsign, parkReference: parkRef,
            myState: myState, potaQsoId: qso.qsoId
        )
    }
}

// Grid lookup in POTAClient+GridLookup.swift
// ADIF generation in POTAClient+ADIF.swift
// Upload helpers in POTAClient+Upload.swift
// Checkpoint methods in POTAClient+Checkpoint.swift
