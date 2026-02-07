import Foundation

// MARK: - ActivitiesClient Friends Extension

extension ActivitiesClient {
    // MARK: - User Search

    /// Search for users by callsign or display name
    func searchUsers(query: String, sourceURL: String) async throws -> [UserSearchResult] {
        guard var components = URLComponents(string: sourceURL + "/v1/users/search") else {
            throw ActivitiesError.invalidServerURL
        }

        components.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let url = components.url else {
            throw ActivitiesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performFriendRequest(request)
        try validateFriendResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<[UserSearchResult]>.self,
            from: data
        )
        return apiResponse.data
    }

    // MARK: - Friend Requests

    /// Send a friend request to another user
    func sendFriendRequest(
        toUserId: String,
        sourceURL: String,
        authToken: String
    ) async throws -> FriendRequestDTO {
        guard let url = URL(string: sourceURL + "/v1/friends/requests") else {
            throw ActivitiesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body = SendFriendRequestBody(toUserId: toUserId)
        request.httpBody = try JSONEncoder.activitiesEncoder.encode(body)

        let (data, response) = try await performFriendRequest(request)
        try validateFriendResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<FriendRequestDTO>.self,
            from: data
        )
        return apiResponse.data
    }

    /// Accept a pending friend request
    func acceptFriendRequest(
        requestId: UUID,
        sourceURL: String,
        authToken: String
    ) async throws {
        guard let url = URL(string: sourceURL + "/v1/friends/requests/\(requestId.uuidString)/accept")
        else {
            throw ActivitiesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performFriendRequest(request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200,
                 204:
                return
            default:
                try validateFriendResponse(response, data: data)
            }
        }
    }

    /// Decline a pending friend request
    func declineFriendRequest(
        requestId: UUID,
        sourceURL: String,
        authToken: String
    ) async throws {
        guard let url = URL(string: sourceURL + "/v1/friends/requests/\(requestId.uuidString)/decline")
        else {
            throw ActivitiesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performFriendRequest(request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200,
                 204:
                return
            default:
                try validateFriendResponse(response, data: data)
            }
        }
    }

    // MARK: - Friend Management

    /// Remove an existing friend
    func removeFriend(
        friendshipId: UUID,
        sourceURL: String,
        authToken: String
    ) async throws {
        guard let url = URL(string: sourceURL + "/v1/friends/\(friendshipId.uuidString)") else {
            throw ActivitiesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performFriendRequest(request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200,
                 204:
                return
            default:
                try validateFriendResponse(response, data: data)
            }
        }
    }

    /// Get list of current friends
    func getFriends(sourceURL: String, authToken: String) async throws -> [FriendDTO] {
        guard let url = URL(string: sourceURL + "/v1/friends") else {
            throw ActivitiesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performFriendRequest(request)
        try validateFriendResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<[FriendDTO]>.self,
            from: data
        )
        return apiResponse.data
    }

    /// Get pending friend requests (both incoming and outgoing)
    func getPendingRequests(
        sourceURL: String,
        authToken: String
    ) async throws -> PendingRequestsDTO {
        guard let url = URL(string: sourceURL + "/v1/friends/requests/pending") else {
            throw ActivitiesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performFriendRequest(request)
        try validateFriendResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<PendingRequestsDTO>.self,
            from: data
        )
        return apiResponse.data
    }

    // MARK: - Invite Links

    /// Generate a shareable invite link for adding friends
    func generateInviteLink(
        sourceURL: String,
        authToken: String
    ) async throws -> InviteLinkDTO {
        guard let url = URL(string: sourceURL + "/v1/friends/invite-link") else {
            throw ActivitiesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performFriendRequest(request)
        try validateFriendResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<InviteLinkDTO>.self,
            from: data
        )
        return apiResponse.data
    }

    /// Send a friend request using an invite token
    func sendFriendRequestWithInvite(
        inviteToken: String,
        sourceURL: String,
        authToken: String
    ) async throws -> FriendRequestDTO {
        guard let url = URL(string: sourceURL + "/v1/friends/requests") else {
            throw ActivitiesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body = SendFriendRequestWithInviteBody(inviteToken: inviteToken)
        request.httpBody = try JSONEncoder.activitiesEncoder.encode(body)

        let (data, response) = try await performFriendRequest(request)
        try validateFriendResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<FriendRequestDTO>.self,
            from: data
        )
        return apiResponse.data
    }

    // MARK: - Private Helpers

    private func performFriendRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw ActivitiesError.networkError(error)
        }
    }

    private func validateFriendResponse(_ response: URLResponse, data: Data) throws {
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

// MARK: - UserSearchResult

struct UserSearchResult: Codable {
    var userId: String
    var callsign: String
    var displayName: String?
}

// MARK: - FriendRequestDTO

struct FriendRequestDTO: Codable {
    var id: UUID
    var fromUserId: String
    var fromCallsign: String
    var toUserId: String
    var toCallsign: String
    var status: String
    var requestedAt: Date
}

// MARK: - FriendDTO

struct FriendDTO: Codable {
    var friendshipId: UUID
    var callsign: String
    var userId: String
    var acceptedAt: Date
}

// MARK: - PendingRequestsDTO

struct PendingRequestsDTO: Codable {
    var incoming: [FriendRequestDTO]
    var outgoing: [FriendRequestDTO]
}

// MARK: - SendFriendRequestBody

private struct SendFriendRequestBody: Codable {
    var toUserId: String
}

// MARK: - SendFriendRequestWithInviteBody

private struct SendFriendRequestWithInviteBody: Codable {
    var inviteToken: String
}

// MARK: - InviteLinkDTO

struct InviteLinkDTO: Codable {
    var token: String
    var url: String
    var expiresAt: Date
}
