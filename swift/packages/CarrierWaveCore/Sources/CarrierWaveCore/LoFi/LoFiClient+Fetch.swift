import Foundation

// MARK: - Fetch endpoints

public extension LoFiClient {
    /// Fetch account info including total QSO and operation counts
    func fetchAccountInfo() async throws -> LoFiAccountsResponse {
        let token = try getToken()

        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/v1/accounts")!)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(urlRequest)
    }

    /// Fetch operations with pagination
    /// - Parameter otherClientsOnly: When true, excludes operations uploaded by this client.
    ///   Should be false for fresh sync to get ALL operations.
    /// - Parameter deleted: When true, fetches only deleted operations. When nil/false, fetches only active.
    ///   Note: The server checks `if params[:deleted]` so passing "false" is treated as truthy.
    ///   Only pass this parameter when true, omit it entirely for active operations.
    /// - Parameter limit: Page size. If nil, uses the server-suggested batch size.
    func fetchOperations(
        syncedSinceMillis: Int64 = 0,
        limit: Int? = nil,
        otherClientsOnly: Bool = true,
        deleted: Bool = false
    ) async throws -> LoFiOperationsResponse {
        let effectiveLimit = limit ?? getSyncFlags().suggestedSyncBatchSize
        let token = try getToken()

        var components = URLComponents(string: "\(baseURL)/v1/operations")!
        components.queryItems = [
            URLQueryItem(name: "synced_since_millis", value: String(syncedSinceMillis)),
            URLQueryItem(name: "other_clients_only", value: String(otherClientsOnly)),
            URLQueryItem(name: "limit", value: String(effectiveLimit)),
        ]
        // Only include deleted param when true - server treats any value as truthy
        if deleted {
            components.queryItems?.append(URLQueryItem(name: "deleted", value: "true"))
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(urlRequest)
    }

    /// Fetch QSOs for a specific operation
    /// - Parameter otherClientsOnly: When true, excludes QSOs uploaded by this client.
    ///   Should be false for fresh sync to get ALL QSOs.
    /// - Parameter deleted: When true, fetches deleted QSOs. When nil/false, fetches active QSOs.
    ///   Note: The server checks `if params[:deleted]` so passing "false" is treated as truthy.
    ///   Only pass this parameter when true, omit it entirely for active QSOs.
    /// - Parameter limit: Page size. If nil, uses the server-suggested batch size.
    func fetchOperationQsos(
        operationUUID: String,
        syncedSinceMillis: Int64 = 0,
        limit: Int? = nil,
        otherClientsOnly: Bool = true,
        deleted: Bool = false
    ) async throws -> LoFiQsosResponse {
        let effectiveLimit = limit ?? getSyncFlags().suggestedSyncBatchSize
        let token = try getToken()

        var components = URLComponents(string: "\(baseURL)/v1/operations/\(operationUUID)/qsos")!
        components.queryItems = [
            URLQueryItem(name: "synced_since_millis", value: String(syncedSinceMillis)),
            URLQueryItem(name: "other_clients_only", value: String(otherClientsOnly)),
            URLQueryItem(name: "limit", value: String(effectiveLimit)),
        ]
        // Only include deleted param when true - server treats any value as truthy
        if deleted {
            components.queryItems?.append(URLQueryItem(name: "deleted", value: "true"))
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(urlRequest)
    }
}
