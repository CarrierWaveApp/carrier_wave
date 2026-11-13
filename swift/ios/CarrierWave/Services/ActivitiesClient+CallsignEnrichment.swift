// ActivitiesClient — callsign enrichment endpoints
//
// Two surfaces consumed by the iOS app:
//   • dataset (full dump for client-side caching, ETag-aware)
//   • per-callsign (rare ad-hoc lookups; mostly used in debug paths)

import CarrierWaveData
import Foundation

extension ActivitiesClient {
    /// Result of fetching the enrichment dataset. `.notModified` is returned
    /// when the supplied `currentETag` matches the server's, in which case
    /// the caller should leave its disk cache alone.
    enum CallsignEnrichmentDatasetFetch {
        case updated(dataset: CallsignEnrichmentDataset, etag: String?)
        case notModified
    }

    /// Fetch the full enrichment dataset, optionally short-circuiting via ETag.
    func fetchCallsignEnrichmentDataset(
        currentETag: String? = nil
    ) async throws -> CallsignEnrichmentDatasetFetch {
        let url = try buildURL(baseURL, path: "/v1/callsign-enrichment/dataset")
        var request = try buildRequest(url: url, method: "GET")
        if let currentETag {
            request.setValue(currentETag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw ActivitiesError.invalidResponse("Not an HTTP response")
        }

        if http.statusCode == 304 {
            return .notModified
        }

        try validateResponse(response, data: data)

        let dataset = try JSONDecoder.activitiesDecoder.decode(
            CallsignEnrichmentDataset.self,
            from: data
        )
        let etag = http.value(forHTTPHeaderField: "Etag")
            ?? http.value(forHTTPHeaderField: "ETag")
        return .updated(dataset: dataset, etag: etag)
    }

    /// Fetch a single callsign's enrichment. Used for debugging — production
    /// code should rely on the dataset cache for offline support.
    func fetchCallsignEnrichment(
        callsign: String
    ) async throws -> CallsignEnrichmentEntry {
        let upper = callsign.uppercased()
        let url = try buildURL(
            baseURL,
            path: "/v1/callsign-enrichment/\(upper)"
        )
        let request = try buildRequest(url: url, method: "GET")
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let decoded = try JSONDecoder.activitiesDecoder.decode(
            CallsignEnrichmentSingleResponse.self,
            from: data
        )
        let memberships = decoded.memberships.map {
            CallsignEnrichmentMembership(
                sourceSlug: $0.sourceSlug,
                sourceName: $0.sourceName,
                emoji: $0.emoji,
                name: $0.name,
                memberNumber: $0.memberNumber,
                note: $0.note
            )
        }
        return CallsignEnrichmentEntry(
            callsign: decoded.callsign,
            memberships: memberships
        )
    }
}

// MARK: - CallsignEnrichmentSingleResponse

/// Wire response for the per-callsign endpoint. Lifted out of the call site
/// to keep nesting under the SwiftLint type-depth budget.
private struct CallsignEnrichmentSingleResponse: Decodable {
    let callsign: String
    let memberships: [CallsignEnrichmentSingleMembership]
}

// MARK: - CallsignEnrichmentSingleMembership

private struct CallsignEnrichmentSingleMembership: Decodable {
    enum CodingKeys: String, CodingKey {
        case sourceSlug = "source_slug"
        case sourceName = "source_name"
        case emoji
        case name
        case memberNumber = "member_number"
        case note
    }

    let sourceSlug: String
    let sourceName: String
    let emoji: String?
    let name: String?
    let memberNumber: String?
    let note: String?
}
