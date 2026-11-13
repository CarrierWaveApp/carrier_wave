#!/usr/bin/env swift
//
// LoFi Sync Test Script
//
// Usage: swift scripts/lofi-sync-test.swift <callsign> <email>
//
// This script emulates the entire LoFi sync flow from CarrierWave:
// 1. Configure client credentials
// 2. Register with LoFi to get bearer token
// 3. Send link device email
// 4. (User confirms email manually)
// 5. Fetch all operations
// 6. Fetch QSOs for each operation
//

// Run the async main
import Dispatch
import Foundation

// MARK: - LoFiRegistrationRequest

struct LoFiRegistrationRequest: Encodable {
    let client: LoFiClientCredentials
    let account: LoFiAccountRequest
    let meta: LoFiMetaRequest
}

// MARK: - LoFiClientCredentials

struct LoFiClientCredentials: Encodable {
    let key: String
    let name: String
    let secret: String
}

// MARK: - LoFiAccountRequest

struct LoFiAccountRequest: Encodable {
    let call: String
}

// MARK: - LoFiMetaRequest

struct LoFiMetaRequest: Encodable {
    let app: String
}

// MARK: - LoFiRegistrationResponse

struct LoFiRegistrationResponse: Decodable {
    let token: String
    let client: LoFiClientInfo
    let account: LoFiAccountInfo
    let meta: LoFiMetaInfo
}

// MARK: - LoFiClientInfo

struct LoFiClientInfo: Decodable {
    let uuid: String
    let name: String
}

// MARK: - LoFiAccountInfo

struct LoFiAccountInfo: Decodable {
    enum CodingKeys: String, CodingKey {
        case uuid
        case call
        case name
        case email
        case cutoffDate = "cutoff_date"
        case cutoffDateMillis = "cutoff_date_millis"
    }

    let uuid: String
    let call: String
    let name: String?
    let email: String?
    let cutoffDate: String?
    let cutoffDateMillis: Int64?
}

// MARK: - LoFiMetaInfo

struct LoFiMetaInfo: Decodable {
    let flags: LoFiSyncFlags
}

// MARK: - LoFiSyncFlags

struct LoFiSyncFlags: Decodable {
    enum CodingKeys: String, CodingKey {
        case suggestedSyncBatchSize = "suggested_sync_batch_size"
        case suggestedSyncLoopDelay = "suggested_sync_loop_delay"
        case suggestedSyncCheckPeriod = "suggested_sync_check_period"
    }

    let suggestedSyncBatchSize: Int
    let suggestedSyncLoopDelay: Int
    let suggestedSyncCheckPeriod: Int
}

// MARK: - LoFiLinkDeviceRequest

struct LoFiLinkDeviceRequest: Encodable {
    let email: String
}

// MARK: - LoFiOperationsResponse

struct LoFiOperationsResponse: Decodable {
    let operations: [LoFiOperation]
    let meta: LoFiOperationsMetaWrapper
}

// MARK: - LoFiOperationsMetaWrapper

struct LoFiOperationsMetaWrapper: Decodable {
    let operations: LoFiOperationsMeta
}

// MARK: - LoFiOperationsMeta

struct LoFiOperationsMeta: Decodable {
    enum CodingKeys: String, CodingKey {
        case totalRecords = "total_records"
        case syncedUntilMillis = "synced_until_millis"
        case syncedUntil = "synced_until"
        case syncedSinceMillis = "synced_since_millis"
        case limit
        case recordsLeft = "records_left"
        case nextUpdatedAtMillis = "next_updated_at_millis"
        case nextSyncedAtMillis = "next_synced_at_millis"
        case extendedPage = "extended_page"
        case otherClientsOnly = "other_clients_only"
    }

    let totalRecords: Int
    let syncedUntilMillis: Double?
    let syncedUntil: String?
    let syncedSinceMillis: Double?
    let limit: Int
    let recordsLeft: Int
    let nextUpdatedAtMillis: Double?
    let nextSyncedAtMillis: Double?
    let extendedPage: Bool?
    let otherClientsOnly: Bool?
}

// MARK: - LoFiOperation

struct LoFiOperation: Decodable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        stationCall = try container.decode(String.self, forKey: .stationCall)
        account = try container.decode(String.self, forKey: .account)
        createdAtMillis = try container.decode(Double.self, forKey: .createdAtMillis)
        createdOnDeviceId = try container.decodeIfPresent(String.self, forKey: .createdOnDeviceId)
        updatedAtMillis = try container.decode(Double.self, forKey: .updatedAtMillis)
        updatedOnDeviceId = try container.decodeIfPresent(String.self, forKey: .updatedOnDeviceId)
        syncedAtMillis = try container.decodeIfPresent(Double.self, forKey: .syncedAtMillis)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        grid = try container.decodeIfPresent(String.self, forKey: .grid)
        refs = try container.decode([LoFiOperationRef].self, forKey: .refs)
        qsoCount = try container.decode(Int.self, forKey: .qsoCount)
        startAtMillisMin = try container.decodeIfPresent(Double.self, forKey: .startAtMillisMin)
        startAtMillisMax = try container.decodeIfPresent(Double.self, forKey: .startAtMillisMax)
        isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew)

        if let intValue = try? container.decodeIfPresent(Int.self, forKey: .deleted) {
            deleted = intValue
        } else if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .deleted) {
            deleted = boolValue ? 1 : 0
        } else {
            deleted = nil
        }

        if let intValue = try? container.decodeIfPresent(Int.self, forKey: .synced) {
            synced = intValue
        } else if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .synced) {
            synced = boolValue ? 1 : 0
        } else {
            synced = nil
        }
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case uuid
        case stationCall
        case account
        case createdAtMillis
        case createdOnDeviceId
        case updatedAtMillis
        case updatedOnDeviceId
        case syncedAtMillis
        case title
        case subtitle
        case grid
        case refs
        case qsoCount
        case startAtMillisMin
        case startAtMillisMax
        case isNew
        case deleted
        case synced
    }

    let uuid: String
    let stationCall: String
    let account: String
    let createdAtMillis: Double
    let createdOnDeviceId: String?
    let updatedAtMillis: Double
    let updatedOnDeviceId: String?
    let syncedAtMillis: Double?
    let title: String?
    let subtitle: String?
    let grid: String?
    let refs: [LoFiOperationRef]
    let qsoCount: Int
    let startAtMillisMin: Double?
    let startAtMillisMax: Double?
    let isNew: Bool?
    let deleted: Int?
    let synced: Int?
}

// MARK: - LoFiOperationRef

struct LoFiOperationRef: Decodable {
    enum CodingKeys: String, CodingKey {
        case refType = "type"
        case reference = "ref"
        case name, location, label
        case shortLabel = "short_label"
        case program
    }

    let refType: String
    let reference: String?
    let name: String?
    let location: String?
    let label: String?
    let shortLabel: String?
    let program: String?
}

// MARK: - LoFiQsosResponse

struct LoFiQsosResponse: Decodable {
    let qsos: [LoFiQso]
    let meta: LoFiQsosMetaWrapper
}

// MARK: - LoFiQsosMetaWrapper

struct LoFiQsosMetaWrapper: Decodable {
    let qsos: LoFiQsosMeta
}

// MARK: - LoFiQsosMeta

struct LoFiQsosMeta: Decodable {
    enum CodingKeys: String, CodingKey {
        case totalRecords = "total_records"
        case syncedUntilMillis = "synced_until_millis"
        case syncedUntil = "synced_until"
        case syncedSinceMillis = "synced_since_millis"
        case limit
        case recordsLeft = "records_left"
        case nextUpdatedAtMillis = "next_updated_at_millis"
        case nextSyncedAtMillis = "next_synced_at_millis"
        case extendedPage = "extended_page"
        case otherClientsOnly = "other_clients_only"
    }

    let totalRecords: Int
    let syncedUntilMillis: Double?
    let syncedUntil: String?
    let syncedSinceMillis: Double?
    let limit: Int
    let recordsLeft: Int
    let nextUpdatedAtMillis: Double?
    let nextSyncedAtMillis: Double?
    let extendedPage: Bool?
    let otherClientsOnly: Bool?
}

// MARK: - LoFiQso

struct LoFiQso: Decodable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        operation = try container.decodeIfPresent(String.self, forKey: .operation)
        account = try container.decodeIfPresent(String.self, forKey: .account)
        createdAtMillis = try container.decodeIfPresent(Double.self, forKey: .createdAtMillis)
        updatedAtMillis = try container.decodeIfPresent(Double.self, forKey: .updatedAtMillis)
        syncedAtMillis = try container.decodeIfPresent(Double.self, forKey: .syncedAtMillis)
        startAt = try container.decodeIfPresent(String.self, forKey: .startAt)
        startAtMillis = try container.decodeIfPresent(Double.self, forKey: .startAtMillis)
        their = try container.decodeIfPresent(LoFiTheirInfo.self, forKey: .their)
        our = try container.decodeIfPresent(LoFiOurInfo.self, forKey: .our)
        band = try container.decodeIfPresent(String.self, forKey: .band)
        freq = try container.decodeIfPresent(Double.self, forKey: .freq)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        refs = try container.decodeIfPresent([LoFiQsoRef].self, forKey: .refs)
        txPwr = try container.decodeIfPresent(String.self, forKey: .txPwr)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)

        if let intValue = try? container.decodeIfPresent(Int.self, forKey: .deleted) {
            deleted = intValue
        } else if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .deleted) {
            deleted = boolValue ? 1 : 0
        } else {
            deleted = nil
        }
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case uuid
        case operation
        case account
        case createdAtMillis
        case updatedAtMillis
        case syncedAtMillis
        case startAt
        case startAtMillis
        case their
        case our
        case band
        case freq
        case mode
        case refs
        case txPwr
        case notes
        case deleted
    }

    let uuid: String
    let operation: String?
    let account: String?
    let createdAtMillis: Double?
    let updatedAtMillis: Double?
    let syncedAtMillis: Double?
    let startAt: String?
    let startAtMillis: Double?
    let their: LoFiTheirInfo?
    let our: LoFiOurInfo?
    let band: String?
    let freq: Double?
    let mode: String?
    let refs: [LoFiQsoRef]?
    let txPwr: String?
    let notes: String?
    let deleted: Int?
}

// MARK: - LoFiTheirInfo

struct LoFiTheirInfo: Decodable {
    let call: String?
    let sent: String?
    let guess: LoFiGuessInfo?
}

// MARK: - LoFiOurInfo

struct LoFiOurInfo: Decodable {
    let call: String?
    let sent: String?
}

// MARK: - LoFiGuessInfo

struct LoFiGuessInfo: Decodable {
    enum CodingKeys: String, CodingKey {
        case call
        case name
        case state
        case city
        case grid
        case country
        case entityName = "entity_name"
        case cqZone = "cq_zone"
        case ituZone = "itu_zone"
        case dxccCode = "dxcc_code"
        case continent
    }

    let call: String?
    let name: String?
    let state: String?
    let city: String?
    let grid: String?
    let country: String?
    let entityName: String?
    let cqZone: Int?
    let ituZone: Int?
    let dxccCode: Int?
    let continent: String?
}

// MARK: - LoFiQsoRef

struct LoFiQsoRef: Decodable {
    enum CodingKeys: String, CodingKey {
        case refType = "type"
        case reference = "ref"
        case program
        case ourNumber = "our_number"
    }

    let refType: String?
    let reference: String?
    let program: String?
    let ourNumber: String?
}

// MARK: - StoredCredentials

struct StoredCredentials: Codable {
    let clientKey: String
    let clientSecret: String
    let callsign: String
    let email: String
}

// MARK: - CredentialStore

class CredentialStore {
    static let credentialsFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".lofi-test-credentials.json")

    static func load() -> StoredCredentials? {
        guard let data = try? Data(contentsOf: credentialsFile) else {
            return nil
        }
        return try? JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    static func save(_ credentials: StoredCredentials) {
        if let data = try? JSONEncoder().encode(credentials) {
            try? data.write(to: credentialsFile)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: credentialsFile)
    }
}

// MARK: - LoFiTestClient

class LoFiTestClient {
    let baseURL = "https://lofi.ham2k.net"
    let clientName = "CarrierWaveTest"
    let appName = "CarrierWaveTest"
    let session = URLSession.shared

    var clientKey: String = ""
    var clientSecret: String = ""
    var callsign: String = ""
    var email: String = ""
    var authToken: String = ""

    func generateClientSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func configure(callsign: String, email: String) {
        self.callsign = callsign.uppercased()
        self.email = email

        // Try to load existing credentials for this callsign
        if let stored = CredentialStore.load(), stored.callsign == self.callsign {
            clientKey = stored.clientKey
            clientSecret = stored.clientSecret
            print("========== CONFIGURATION (LOADED) ==========")
            print("Callsign: \(self.callsign)")
            print("Email: \(self.email)")
            print("Client Key: \(clientKey) (from saved credentials)")
            print("Client Secret: \(clientSecret.prefix(16))... (from saved credentials)")
        } else {
            // Generate new credentials
            clientKey = UUID().uuidString
            clientSecret = generateClientSecret()

            // Save for future use
            let credentials = StoredCredentials(
                clientKey: clientKey,
                clientSecret: clientSecret,
                callsign: self.callsign,
                email: self.email
            )
            CredentialStore.save(credentials)

            print("========== CONFIGURATION (NEW) ==========")
            print("Callsign: \(self.callsign)")
            print("Email: \(self.email)")
            print("Client Key: \(clientKey) (newly generated)")
            print("Client Secret: \(clientSecret.prefix(16))... (newly generated)")
            print("Credentials saved to: \(CredentialStore.credentialsFile.path)")
        }
    }

    func register() async throws -> LoFiRegistrationResponse {
        print("\n========== REGISTERING ==========")

        let request = LoFiRegistrationRequest(
            client: LoFiClientCredentials(key: clientKey, name: clientName, secret: clientSecret),
            account: LoFiAccountRequest(call: callsign),
            meta: LoFiMetaRequest(app: appName)
        )

        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/v1/client")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "LoFi", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not HTTP response"]
            )
        }

        print("Status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("Error body: \(body)")
            throw NSError(
                domain: "LoFi", code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: body]
            )
        }

        let registration = try JSONDecoder().decode(LoFiRegistrationResponse.self, from: data)

        print("Token: \(registration.token.prefix(20))...")
        print("Account UUID: \(registration.account.uuid)")
        print("Account Call: \(registration.account.call)")
        print("Account Name: \(registration.account.name ?? "nil")")
        print("Account Email: \(registration.account.email ?? "nil")")

        if let cutoffDate = registration.account.cutoffDate {
            print("⚠️ CUTOFF DATE: \(cutoffDate)")
        } else {
            print("Cutoff Date: nil (no restriction)")
        }

        if let cutoffMillis = registration.account.cutoffDateMillis {
            let date = Date(timeIntervalSince1970: Double(cutoffMillis) / 1_000.0)
            let formatter = ISO8601DateFormatter()
            print("⚠️ CUTOFF DATE MILLIS: \(cutoffMillis) (\(formatter.string(from: date)))")
        }

        print("Sync Batch Size: \(registration.meta.flags.suggestedSyncBatchSize)")
        print("Sync Loop Delay: \(registration.meta.flags.suggestedSyncLoopDelay) ms")
        print("Sync Check Period: \(registration.meta.flags.suggestedSyncCheckPeriod) ms")

        authToken = registration.token
        return registration
    }

    func linkDevice() async throws {
        print("\n========== LINKING DEVICE ==========")
        print("Sending link email to: \(email)")

        let request = LoFiLinkDeviceRequest(email: email)

        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/v1/client/link")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "LoFi", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not HTTP response"]
            )
        }

        print("Status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("Error body: \(body)")
            throw NSError(
                domain: "LoFi", code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: body]
            )
        }

        print("Link email sent successfully!")
        print("Check your email and click the confirmation link.")
    }

    func fetchOperations(
        syncedSinceMillis: Int64 = 0,
        limit: Int = 50,
        otherClientsOnly: Bool = false,
        deleted: Bool = false
    ) async throws -> LoFiOperationsResponse {
        var components = URLComponents(string: "\(baseURL)/v1/operations")!
        components.queryItems = [
            URLQueryItem(name: "synced_since_millis", value: String(syncedSinceMillis)),
            URLQueryItem(name: "other_clients_only", value: String(otherClientsOnly)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if deleted {
            components.queryItems?.append(URLQueryItem(name: "deleted", value: "true"))
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "LoFi", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not HTTP response"]
            )
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "LoFi", code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: body]
            )
        }

        return try JSONDecoder().decode(LoFiOperationsResponse.self, from: data)
    }

    func fetchOperationQsos(
        operationUUID: String,
        syncedSinceMillis: Int64 = 0,
        limit: Int = 50,
        otherClientsOnly: Bool = false,
        deleted: Bool = false
    ) async throws -> LoFiQsosResponse {
        var components = URLComponents(string: "\(baseURL)/v1/operations/\(operationUUID)/qsos")!
        components.queryItems = [
            URLQueryItem(name: "synced_since_millis", value: String(syncedSinceMillis)),
            URLQueryItem(name: "other_clients_only", value: String(otherClientsOnly)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if deleted {
            components.queryItems?.append(URLQueryItem(name: "deleted", value: "true"))
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "LoFi", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not HTTP response"]
            )
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "LoFi", code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: body]
            )
        }

        do {
            return try JSONDecoder().decode(LoFiQsosResponse.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            print("  JSON decode error for QSOs: \(error)")
            print("  Response body (truncated): \(body.prefix(500))")
            throw error
        }
    }

    func fetchAllOperations() async throws -> [LoFiOperation] {
        print("\n========== FETCHING OPERATIONS ==========")

        var operationsByUUID: [String: LoFiOperation] = [:]

        for deleted in [false, true] {
            var syncedSince: Int64 = 0
            var pageCount = 0
            var totalFetched = 0

            let opType = deleted ? "deleted" : "active"
            print("Fetching \(opType) operations...")

            while true {
                pageCount += 1
                let response = try await fetchOperations(
                    syncedSinceMillis: syncedSince,
                    limit: 50,
                    otherClientsOnly: false,
                    deleted: deleted
                )

                totalFetched += response.operations.count
                for operation in response.operations {
                    operationsByUUID[operation.uuid] = operation
                }

                print(
                    "  Page \(pageCount): \(response.operations.count) ops, \(response.meta.operations.recordsLeft) left"
                )

                if response.meta.operations.recordsLeft == 0 {
                    break
                }
                // Server returns next_updated_at_millis when using synced_since_millis pagination
                guard
                    let next = response.meta.operations.nextUpdatedAtMillis
                    ?? response.meta.operations.nextSyncedAtMillis
                else {
                    print(
                        "  Warning: recordsLeft > 0 but no nextUpdatedAtMillis or nextSyncedAtMillis"
                    )
                    break
                }
                syncedSince = Int64(next)
            }

            print("  Total \(opType) operations: \(totalFetched)")
        }

        let operations = Array(operationsByUUID.values)
        let expectedQsos = operations.reduce(0) { $0 + $1.qsoCount }

        print("\nTotal unique operations: \(operations.count)")
        print("Expected QSOs: \(expectedQsos)")

        return operations
    }

    func fetchAllQsos(from operations: [LoFiOperation]) async throws -> [(LoFiQso, LoFiOperation)] {
        print("\n========== FETCHING QSOS ==========")

        var allQsos: [(LoFiQso, LoFiOperation)] = []

        for (index, operation) in operations.enumerated() {
            let opTitle = operation.title ?? "untitled"
            print(
                "[\(index + 1)/\(operations.count)] \(opTitle) (expecting \(operation.qsoCount) QSOs)"
            )

            var opQsos: [LoFiQso] = []

            for deleted in [false, true] {
                var syncedSince: Int64 = 0

                while true {
                    let response = try await fetchOperationQsos(
                        operationUUID: operation.uuid,
                        syncedSinceMillis: syncedSince,
                        limit: 50,
                        otherClientsOnly: false,
                        deleted: deleted
                    )

                    opQsos.append(contentsOf: response.qsos)

                    if response.meta.qsos.recordsLeft == 0 {
                        break
                    }
                    // Server returns next_updated_at_millis when using synced_since_millis pagination
                    guard
                        let next = response.meta.qsos.nextUpdatedAtMillis
                        ?? response.meta.qsos.nextSyncedAtMillis
                    else {
                        break
                    }
                    syncedSince = Int64(next)
                }
            }

            if opQsos.count != operation.qsoCount {
                print("  ⚠️ MISMATCH: expected \(operation.qsoCount), got \(opQsos.count)")
            } else {
                print("  ✓ Got \(opQsos.count) QSOs")
            }

            for qso in opQsos {
                allQsos.append((qso, operation))
            }
        }

        return allQsos
    }

    /// Generate a deduplication key for a QSO based on call, band, mode, and time window
    func deduplicationKey(for qso: LoFiQso) -> String {
        let theirCall = (qso.their?.call ?? "").uppercased()
        let band = (qso.band ?? "").uppercased()
        let mode = (qso.mode ?? "").uppercased()

        // Round timestamp to 5-minute window for fuzzy matching
        let timestamp = qso.startAtMillis ?? 0
        let windowMillis: Double = 5 * 60 * 1_000 // 5 minutes
        let timeWindow = Int64(timestamp / windowMillis)

        return "\(theirCall)|\(band)|\(mode)|\(timeWindow)"
    }

    /// Deduplicate QSOs, keeping only active (non-deleted) where possible
    func deduplicateQsos(_ qsos: [(LoFiQso, LoFiOperation)]) -> [(LoFiQso, LoFiOperation)] {
        var seen: [String: (LoFiQso, LoFiOperation)] = [:]
        var duplicateCount = 0

        for (qso, op) in qsos {
            let key = deduplicationKey(for: qso)

            if let existing = seen[key] {
                duplicateCount += 1
                // Prefer non-deleted over deleted
                let existingDeleted = existing.0.deleted == 1
                let currentDeleted = qso.deleted == 1

                if existingDeleted, !currentDeleted {
                    // Replace deleted with non-deleted
                    seen[key] = (qso, op)
                }
                // Otherwise keep existing (first non-deleted wins, or first deleted if both deleted)
            } else {
                seen[key] = (qso, op)
            }
        }

        print("\n========== DEDUPLICATION ==========")
        print("Total QSOs before dedup: \(qsos.count)")
        print("Duplicates removed: \(duplicateCount)")
        print("Unique QSOs after dedup: \(seen.count)")

        // Count active vs deleted
        let activeCount = seen.values.filter { $0.0.deleted != 1 }.count
        let deletedCount = seen.values.filter { $0.0.deleted == 1 }.count
        print("  Active QSOs: \(activeCount)")
        print("  Deleted QSOs: \(deletedCount)")

        return Array(seen.values)
    }

    func printSummary(_ qsos: [(LoFiQso, LoFiOperation)]) {
        print("\n========== SYNC SUMMARY ==========")
        print("Total QSOs fetched: \(qsos.count)")

        if !qsos.isEmpty {
            let timestamps = qsos.compactMap(\.0.startAtMillis)
            let minTimestamp = timestamps.min() ?? 0
            let maxTimestamp = timestamps.max() ?? 0
            let minDate = Date(timeIntervalSince1970: minTimestamp / 1_000.0)
            let maxDate = Date(timeIntervalSince1970: maxTimestamp / 1_000.0)

            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short

            print(
                "QSO Date Range: \(formatter.string(from: minDate)) to \(formatter.string(from: maxDate))"
            )

            // Count by deleted status
            let activeQsos = qsos.filter { $0.0.deleted != 1 }
            let deletedQsos = qsos.filter { $0.0.deleted == 1 }
            print("Active QSOs: \(activeQsos.count)")
            print("Deleted QSOs: \(deletedQsos.count)")

            // Sample QSOs
            print("\nSample QSOs (first 5 active):")
            for (qso, _) in activeQsos.prefix(5) {
                let date = Date(timeIntervalSince1970: (qso.startAtMillis ?? 0) / 1_000.0)
                let theirCall = qso.their?.call ?? "?"
                let band = qso.band ?? "?"
                let mode = qso.mode ?? "?"
                print("  \(formatter.string(from: date)) - \(theirCall) on \(band) \(mode)")
            }
        }
    }
}

// MARK: - Main

func runMain() async {
    let args = CommandLine.arguments

    // Handle --reset before checking arg count
    if args.contains("--reset") {
        CredentialStore.clear()
        print("Credentials cleared. Run again without --reset to generate new credentials.")
        exit(0)
    }

    if args.count < 3 {
        print("Usage: swift \(args[0]) <callsign> <email>")
        print("")
        print("Options:")
        print("  --link-only    Only send the link email, don't try to fetch data")
        print("  --fetch-only   Skip registration/linking, just fetch (requires prior linking)")
        print("  --reset        Clear saved credentials and exit")
        print("")
        print("Credentials are saved to ~/.lofi-test-credentials.json and reused between runs.")
        print("")
        print("Example:")
        print("  swift \(args[0]) W1ABC user@example.com --link-only  # First run: link device")
        print("  swift \(args[0]) W1ABC user@example.com --fetch-only # After confirming email")
        exit(1)
    }

    let callsign = args[1]
    let email = args[2]
    let linkOnly = args.contains("--link-only")
    let fetchOnly = args.contains("--fetch-only")

    let client = LoFiTestClient()

    do {
        // Step 1: Configure
        client.configure(callsign: callsign, email: email)

        // Step 2: Register
        _ = try await client.register()

        if fetchOnly {
            // Skip linking, go straight to fetch
            print("\n--fetch-only: Skipping link step, attempting fetch...")
        } else {
            // Step 3: Send link email
            try await client.linkDevice()

            if linkOnly {
                print(
                    "\n--link-only: Stopping here. Check your email and run again with --fetch-only"
                )
                exit(0)
            }

            // Wait for user to confirm email
            print("\n========== WAITING FOR CONFIRMATION ==========")
            print("Press ENTER after you've clicked the confirmation link in your email...")
            _ = readLine()
        }

        // Step 4: Fetch operations
        let operations = try await client.fetchAllOperations()

        // Step 5: Fetch QSOs
        let rawQsos = try await client.fetchAllQsos(from: operations)

        // Step 6: Deduplicate
        let qsos = client.deduplicateQsos(rawQsos)

        // Step 7: Print summary
        client.printSummary(qsos)

        print("\n✓ Sync test completed successfully!")
    } catch {
        print("\n✗ Error: \(error.localizedDescription)")
        exit(1)
    }
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    await runMain()
    semaphore.signal()
}

semaphore.wait()
