import CarrierWaveData
import Foundation

// MARK: - Equipment Submission Endpoints

extension ActivitiesClient {
    /// Submit custom equipment specs to the server for catalog review.
    /// Anonymous — uses no auth token, just the default request headers.
    func submitCustomEquipment(
        _ submission: EquipmentSubmissionPayload
    ) async throws {
        let url = try buildURL(baseURL, path: "/v1/equipment/submissions")
        var request = try buildRequest(url: url, method: "POST")
        request.httpBody = try JSONEncoder.activitiesEncoder.encode(
            submission
        )

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
    }
}

// MARK: - EquipmentSubmissionPayload

struct EquipmentSubmissionPayload: Codable {
    enum CodingKeys: String, CodingKey {
        case name
        case manufacturer
        case category
        case bands
        case modes
        case maxPowerWatts = "max_power_watts"
        case portability
        case weightGrams = "weight_grams"
    }

    let name: String
    let manufacturer: String
    let category: String
    let bands: [String]
    let modes: [String]
    let maxPowerWatts: Int?
    let portability: String
    let weightGrams: Int?
}
