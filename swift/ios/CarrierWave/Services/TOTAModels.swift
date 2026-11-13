// Tiles on the Air (TOTA) data models.
//
// TOTA is an outdoor radio program built around Maidenhead grid tiles.
// Activations are recorded by POSTing to /functions/v1/activations; the same
// record surfaces in the public spots feed (GET /functions/v1/spots), so
// "creating an activation" is also "creating a spot" in TOTA's model.

import UIKit

// MARK: - TOTAError

enum TOTAError: Error, LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case httpError(status: Int, body: String)
    case decodingFailed(Error)
    case rateLimited
    case networkError(Error)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "TOTA API key missing — generate one in your tilesontheair.com profile."
        case .invalidURL:
            "Invalid TOTA URL"
        case .invalidResponse:
            "Invalid TOTA response"
        case let .httpError(status, body):
            "TOTA HTTP \(status): \(body)"
        case let .decodingFailed(error):
            "TOTA decode failed: \(error.localizedDescription)"
        case .rateLimited:
            "TOTA rate limit hit — slow down to ≤ 1 request / 30 s, or supply an API key."
        case let .networkError(error):
            "TOTA network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - TOTAActivationKind

/// Activation taxonomy accepted by POST /activations. Comma-separated values are
/// allowed server-side (e.g. a Park + Summit two-fer); we model that as a Set.
enum TOTAActivationKind: String, CaseIterable, Codable {
    case tile = "Tile"
    case summit = "Summit"
    case park = "Park"
    case island = "Island"
    case lighthouse = "Lighthouse"
    case castle = "Castle"
    case floraAndFauna = "Flora & Fauna"
    case worldHeritage = "World Heritage"
    case other = "Other"

    // MARK: Internal

    var displayName: String {
        rawValue
    }
}

// MARK: - TOTASpot

/// Read model returned by GET /functions/v1/spots.
struct TOTASpot: Identifiable, Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id
        case callSign = "call_sign"
        case frequency
        case mode
        case maidenheadGrid = "maidenhead_grid"
        case latitude
        case longitude
        case notes
        case potaRef = "pota_ref"
        case sotaRef = "sota_ref"
        case createdAt = "created_at"
    }

    let id: String
    let callSign: String
    /// Frequency in MHz, transmitted as a numeric string by the server (e.g. "14.285").
    let frequency: String?
    let mode: String?
    let maidenheadGrid: String?
    let latitude: Double?
    let longitude: Double?
    let notes: String?
    let potaRef: String?
    let sotaRef: String?
    let createdAt: Date?

    /// Best-effort numeric conversion of the string `frequency` field.
    var frequencyMHz: Double? {
        guard let frequency else {
            return nil
        }
        return Double(frequency)
    }
}

// MARK: - TOTASpotsResponse

struct TOTASpotsResponse: Decodable {
    enum CodingKeys: String, CodingKey {
        case spots
        case count
        case generatedAt = "generated_at"
    }

    let spots: [TOTASpot]
    let count: Int
    let generatedAt: Date?
}

// MARK: - TOTAActivationRequest

/// JSON body for POST /functions/v1/activations. Mirrors the public API doc:
/// only call_sign, activation_type, latitude, longitude are required server-side.
struct TOTAActivationRequest: Encodable {
    enum CodingKeys: String, CodingKey {
        case callSign = "call_sign"
        case activationType = "activation_type"
        case latitude
        case longitude
        case maidenheadGrid = "maidenhead_grid"
        case activationDate = "activation_date"
        case distance
        case qsoCount = "qso_count"
        case ft8QsoCount = "ft8_qso_count"
        case qrpActivation = "qrp_activation"
        case ruckWeight = "ruck_weight"
        case elevationGain = "elevation_gain"
        case withPets = "with_pets"
        case withKids = "with_kids"
        case winlinkSent = "winlink_sent"
        case aprsSent = "aprs_sent"
        case varacSent = "varac_sent"
        case adaptiveSport = "adaptive_sport"
        case isPublic = "is_public"
        case notes
    }

    /// Uppercased before sending.
    let callSign: String
    /// Comma-separated kinds, e.g. "Tile" or "Park,Summit".
    let activationType: String
    let latitude: Double
    let longitude: Double
    let maidenheadGrid: String?
    /// `YYYY-MM-DD`. Server defaults to today when omitted.
    let activationDate: String?
    /// Miles from QTH.
    let distance: Double?
    let qsoCount: Int?
    let ft8QsoCount: Int?
    let qrpActivation: Bool?
    let ruckWeight: Double?
    let elevationGain: Double?
    let withPets: Bool?
    let withKids: Bool?
    let winlinkSent: Bool?
    let aprsSent: Bool?
    let varacSent: Bool?
    let adaptiveSport: Bool?
    let isPublic: Bool?
    let notes: String?
}

extension TOTAActivationRequest {
    /// Convenience initialiser that takes a typed Set of kinds and assembles the
    /// comma-separated string the server expects.
    init(
        callSign: String,
        kinds: Set<TOTAActivationKind>,
        latitude: Double,
        longitude: Double,
        maidenheadGrid: String? = nil,
        activationDate: Date? = nil,
        distance: Double? = nil,
        qsoCount: Int? = nil,
        ft8QsoCount: Int? = nil,
        qrpActivation: Bool? = nil,
        ruckWeight: Double? = nil,
        elevationGain: Double? = nil,
        withPets: Bool? = nil,
        withKids: Bool? = nil,
        winlinkSent: Bool? = nil,
        aprsSent: Bool? = nil,
        varacSent: Bool? = nil,
        adaptiveSport: Bool? = nil,
        isPublic: Bool? = nil,
        notes: String? = nil
    ) {
        self.callSign = callSign.uppercased()
        let resolvedKinds = kinds.isEmpty ? [.tile] : kinds
        activationType = resolvedKinds
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        self.latitude = latitude
        self.longitude = longitude
        self.maidenheadGrid = maidenheadGrid
        self.activationDate = activationDate.map(TOTAActivationRequest.dateFormatter.string(from:))
        self.distance = distance
        self.qsoCount = qsoCount
        self.ft8QsoCount = ft8QsoCount
        self.qrpActivation = qrpActivation
        self.ruckWeight = ruckWeight
        self.elevationGain = elevationGain
        self.withPets = withPets
        self.withKids = withKids
        self.winlinkSent = winlinkSent
        self.aprsSent = aprsSent
        self.varacSent = varacSent
        self.adaptiveSport = adaptiveSport
        self.isPublic = isPublic
        self.notes = notes
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - TOTAActivationResponse

struct TOTAActivationResponse: Decodable {
    let success: Bool
    let activation: TOTAActivationDetail?
    let error: String?
}

// MARK: - TOTAActivationDetail

struct TOTAActivationDetail: Decodable {
    enum CodingKeys: String, CodingKey {
        case id
        case callSign = "call_sign"
        case points
        case maidenheadGrid = "maidenhead_grid"
        case activationType = "activation_type"
        case activationDate = "activation_date"
    }

    let id: String
    let callSign: String?
    let points: Double?
    let maidenheadGrid: String?
    let activationType: String?
    let activationDate: String?
}
