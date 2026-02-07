import Foundation

// MARK: - ActivitiesClient Friend Suggestions Extension

extension ActivitiesClient {
    /// Validate callsigns against server to find registered app users.
    /// Falls back to individual search if batch endpoint is unavailable.
    func getSuggestions(
        callsigns: [String],
        sourceURL: String,
        authToken: String
    ) async throws -> [FriendSuggestionDTO] {
        do {
            return try await batchValidateCallsigns(
                callsigns: callsigns,
                sourceURL: sourceURL,
                authToken: authToken
            )
        } catch {
            // Fallback to individual search if batch endpoint doesn't exist.
            // Server returns JSON 404 which decodes as .serverError(0, "NOT_FOUND")
            // or raw HTTP 404 as .serverError(404, _).
            let isMissingEndpoint = switch error {
            case ActivitiesError.serverError(404, _):
                true
            case let ActivitiesError.serverError(0, msg) where msg?.contains("NOT_FOUND") == true:
                true
            default:
                false
            }

            if isMissingEndpoint {
                return await fallbackSearchCallsigns(
                    callsigns: callsigns,
                    sourceURL: sourceURL
                )
            }
            throw error
        }
    }

    // MARK: - Private

    /// Batch validate callsigns via POST /v1/friends/suggestions.
    private func batchValidateCallsigns(
        callsigns: [String],
        sourceURL: String,
        authToken: String
    ) async throws -> [FriendSuggestionDTO] {
        guard let url = URL(string: sourceURL + "/v1/friends/suggestions") else {
            throw ActivitiesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body = SuggestionsRequestBody(callsigns: callsigns)
        request.httpBody = try JSONEncoder.activitiesEncoder.encode(body)

        let (data, response) = try await performSuggestionRequest(request)
        try validateSuggestionResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<[FriendSuggestionDTO]>.self,
            from: data
        )
        return apiResponse.data
    }

    /// Fallback: search callsigns one by one using existing search endpoint.
    /// Capped at 10 to avoid long waits when batch endpoint is unavailable.
    private func fallbackSearchCallsigns(
        callsigns: [String],
        sourceURL: String
    ) async -> [FriendSuggestionDTO] {
        var results: [FriendSuggestionDTO] = []

        for callsign in callsigns.prefix(10) {
            guard !Task.isCancelled else {
                break
            }
            do {
                let searchResults = try await searchUsers(query: callsign, sourceURL: sourceURL)
                if let match = searchResults.first(where: {
                    $0.callsign.uppercased() == callsign.uppercased()
                }) {
                    results.append(
                        FriendSuggestionDTO(
                            userId: match.userId,
                            callsign: match.callsign
                        )
                    )
                }
            } catch {
                continue
            }
        }

        return results
    }

    private func performSuggestionRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw ActivitiesError.networkError(error)
        }
    }

    private func validateSuggestionResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ActivitiesError.invalidResponse("Not an HTTP response")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder.activitiesDecoder.decode(
                APIErrorResponse.self,
                from: data
            ) {
                throw ActivitiesError.from(
                    apiCode: errorResponse.error.code,
                    message: errorResponse.error.message
                )
            }

            let message = String(data: data, encoding: .utf8)
            throw ActivitiesError.serverError(httpResponse.statusCode, message)
        }
    }
}

// MARK: - SuggestionsRequestBody

private struct SuggestionsRequestBody: Codable {
    let callsigns: [String]
}
