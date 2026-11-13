// TOTA activation create — also self-spots the operator on the public spots feed.
//
// POST https://icneuzxitdqtofutxbla.supabase.co/functions/v1/activations
//   Auth: x-api-key (required).
//   Body: application/json (TOTAActivationRequest).
// Points are calculated server-side and returned in the response.

import UIKit

extension TOTAClient {
    /// Create (or self-spot) a TOTA activation. Returns the server-calculated detail
    /// — most notably `points` and the canonical `maidenhead_grid`.
    @discardableResult
    func createActivation(_ request: TOTAActivationRequest) async throws -> TOTAActivationDetail {
        var urlRequest = try makeRequest(
            path: "/activations",
            method: "POST",
            requireAuth: true
        )
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            urlRequest.httpBody = try Self.makeEncoder().encode(request)
        } catch {
            throw TOTAError.decodingFailed(error)
        }

        let data = try await executeRequest(urlRequest)
        let decoded = try Self.decodeActivationResponse(data)
        guard decoded.success, let detail = decoded.activation else {
            throw TOTAError.httpError(
                status: 200,
                body: decoded.error ?? "TOTA reported success=false with no detail"
            )
        }
        return detail
    }

    // MARK: Internal helpers

    static func decodeActivationResponse(_ data: Data) throws -> TOTAActivationResponse {
        do {
            return try makeDecoder().decode(TOTAActivationResponse.self, from: data)
        } catch {
            throw TOTAError.decodingFailed(error)
        }
    }
}
