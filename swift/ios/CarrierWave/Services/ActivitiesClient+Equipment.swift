import CarrierWaveData
import Foundation

// MARK: - Equipment Catalog Endpoints

// Catalog download lives in the Rust core (`ReferenceDataApi`); only the
// search endpoint remains here.

extension ActivitiesClient {
    /// Search the equipment catalog by name, manufacturer, or alias.
    func searchEquipment(
        query: String,
        category: EquipmentCategory? = nil,
        limit: Int = 10
    ) async throws -> [EquipmentSearchHit] {
        guard var components = URLComponents(
            string: baseURL + "/v1/equipment/search"
        ) else {
            throw ActivitiesError.invalidServerURL
        }
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let category {
            queryItems.append(
                URLQueryItem(name: "category", value: category.rawValue)
            )
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ActivitiesError.invalidServerURL
        }
        let request = try buildRequest(url: url, method: "GET")
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let decoded = try JSONDecoder.activitiesDecoder.decode(
            EquipmentSearchResponse.self,
            from: data
        )
        return decoded.results
    }
}

// MARK: - EquipmentSearchResponse

struct EquipmentSearchResponse: Codable {
    let results: [EquipmentSearchHit]
}

// MARK: - EquipmentSearchHit

struct EquipmentSearchHit: Codable, Identifiable {
    enum CodingKeys: String, CodingKey {
        case entry
        case confidence
        case matchedField = "matched_field"
    }

    let entry: EquipmentAPIEntry
    let confidence: Double
    let matchedField: String

    var id: String {
        entry.id
    }
}

// MARK: - EquipmentAPIEntry

struct EquipmentAPIEntry: Codable, Identifiable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case manufacturer
        case category
        case bands
        case modes
        case portability
        case description
        case aliases
        case maxPowerWatts = "max_power_watts"
        case weightGrams = "weight_grams"
        case imageUrl = "image_url"
        case antennaConnector = "antenna_connector"
        case powerConnector = "power_connector"
        case keyJack = "key_jack"
        case micJack = "mic_jack"
    }

    let id: String
    let name: String
    let manufacturer: String
    let category: String
    let bands: [String]
    let modes: [String]
    let maxPowerWatts: Int?
    let portability: String
    let weightGrams: Int?
    let description: String?
    let aliases: [String]
    let imageUrl: String?
    let antennaConnector: String?
    let powerConnector: String?
    let keyJack: String?
    let micJack: String?

    /// Full display name with manufacturer.
    var fullName: String {
        "\(manufacturer) \(name)"
    }
}
