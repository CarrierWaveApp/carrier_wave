//
//  EnrichedLinkPayload.swift
//  CarrierWaveCore
//
//  Codable payload schema for enriched share links. Encodes QSO, Activation,
//  Callsign, and Park share data into a base64url JSON blob that travels in
//  the URL fragment (so it never reaches the server). See
//  docs/plans/2026-04-07-imessage-enriched-text-design.md.
//

import Foundation

// MARK: - EnrichedLinkPayload

/// Top-level enriched link payload. Embedded in the URL fragment as
/// `#d=<base64url(JSON)>`. The fragment is never sent in HTTP requests, so
/// log data never reaches a server.
public enum EnrichedLinkPayload: Codable, Sendable, Equatable {
    case callsign(CallsignPayload)
    case park(ParkPayload)
    case summit(SummitPayload)
    case qso(QSOPayload)
    case activation(ActivationPayload)

    // MARK: Lifecycle

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "call":
            self = try .callsign(CallsignPayload(from: decoder))
        case "park":
            self = try .park(ParkPayload(from: decoder))
        case "sum":
            self = try .summit(SummitPayload(from: decoder))
        case "qso":
            self = try .qso(QSOPayload(from: decoder))
        case "act":
            self = try .activation(ActivationPayload(from: decoder))
        default:
            throw EnrichedLinkPayloadError.unknownKind(kind)
        }
    }

    // MARK: Public

    public static let schemaVersion = 1

    /// Maximum size of the entire enriched URL (including scheme, host, path,
    /// fragment marker, and base64url payload). Chosen so that every share
    /// kind survives Discord, Signal, Slack, iMessage, Mail, and QR codes.
    public static let maxURLByteCount = 1_500

    /// Approximate base URL overhead (`https://carrierwave.app/link/<kind>/<id>#d=`).
    public static let baseURLOverhead = 50

    /// Maximum base64url-encoded fragment size that fits within
    /// `maxURLByteCount` after the base URL overhead.
    public static let maxFragmentByteCount = maxURLByteCount - baseURLOverhead

    public var kind: String {
        switch self {
        case .callsign: "call"
        case .park: "park"
        case .summit: "sum"
        case .qso: "qso"
        case .activation: "act"
        }
    }

    /// Decode a base64url fragment back into a payload. Used by the in-app
    /// router and the in-browser JS card renderer (the JS implementation
    /// mirrors this format).
    public static func decodeFragment(_ fragment: String) throws -> EnrichedLinkPayload {
        guard let data = base64URLDecode(fragment) else {
            throw EnrichedLinkPayloadError.invalidEncoding
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(EnrichedLinkPayload.self, from: data)
    }

    /// Encode this payload to a base64url string suitable for the fragment.
    /// Throws `EnrichedLinkPayloadError.payloadTooLarge` if the encoded
    /// payload would exceed `maxFragmentByteCount`.
    public func encodeFragment() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(self)
        let base64 = Self.base64URLEncode(data)
        if base64.utf8.count > Self.maxFragmentByteCount {
            throw EnrichedLinkPayloadError.payloadTooLarge(
                actual: base64.utf8.count, limit: Self.maxFragmentByteCount
            )
        }
        return base64
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .callsign(payload): try payload.encode(to: encoder)
        case let .park(payload): try payload.encode(to: encoder)
        case let .summit(payload): try payload.encode(to: encoder)
        case let .qso(payload): try payload.encode(to: encoder)
        case let .activation(payload): try payload.encode(to: encoder)
        }
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case kind = "k"
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        return Data(base64Encoded: base64)
    }
}

// MARK: - EnrichedLinkPayloadError

public enum EnrichedLinkPayloadError: Error, Equatable, Sendable {
    case payloadTooLarge(actual: Int, limit: Int)
    case invalidEncoding
    case unknownKind(String)
}

// MARK: - CallsignPayload

public struct CallsignPayload: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        callsign: String,
        name: String? = nil,
        grid: String? = nil,
        qth: String? = nil,
        country: String? = nil,
        workedCount: Int? = nil,
        lastWorked: Date? = nil,
        lastBand: String? = nil,
        lastMode: String? = nil,
        propagationHint: String? = nil
    ) {
        self.callsign = callsign
        self.name = name
        self.grid = grid
        self.qth = qth
        self.country = country
        self.workedCount = workedCount
        self.lastWorked = lastWorked
        self.lastBand = lastBand
        self.lastMode = lastMode
        self.propagationHint = propagationHint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callsign = try container.decode(String.self, forKey: .callsign)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        grid = try container.decodeIfPresent(String.self, forKey: .grid)
        qth = try container.decodeIfPresent(String.self, forKey: .qth)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        workedCount = try container.decodeIfPresent(Int.self, forKey: .workedCount)
        lastWorked = try container.decodeIfPresent(Date.self, forKey: .lastWorked)
        lastBand = try container.decodeIfPresent(String.self, forKey: .lastBand)
        lastMode = try container.decodeIfPresent(String.self, forKey: .lastMode)
        propagationHint = try container.decodeIfPresent(String.self, forKey: .propagationHint)
    }

    // MARK: Public

    public let callsign: String
    public let name: String?
    public let grid: String?
    public let qth: String?
    public let country: String?
    public let workedCount: Int?
    public let lastWorked: Date?
    public let lastBand: String?
    public let lastMode: String?
    /// Optional short propagation hint (e.g. "20m open to EU"), pulled
    /// from local solar/spots data at share time. Phase 5 feature.
    public let propagationHint: String?

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("call", forKey: .kind)
        try container.encode(EnrichedLinkPayload.schemaVersion, forKey: .version)
        try container.encode(callsign, forKey: .callsign)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(grid, forKey: .grid)
        try container.encodeIfPresent(qth, forKey: .qth)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encodeIfPresent(workedCount, forKey: .workedCount)
        try container.encodeIfPresent(lastWorked, forKey: .lastWorked)
        try container.encodeIfPresent(lastBand, forKey: .lastBand)
        try container.encodeIfPresent(lastMode, forKey: .lastMode)
        try container.encodeIfPresent(propagationHint, forKey: .propagationHint)
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case kind = "k"
        case version = "v"
        case callsign = "c"
        case name = "nm"
        case grid = "g"
        case qth = "q"
        case country = "co"
        case workedCount = "wc"
        case lastWorked = "lw"
        case lastBand = "lb"
        case lastMode = "lm"
        case propagationHint = "ph"
    }
}

// MARK: - ParkPayload

public struct ParkPayload: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        reference: String,
        name: String? = nil,
        state: String? = nil,
        country: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        userActivations: Int? = nil,
        userHunts: Int? = nil,
        isActiveNow: Bool? = nil
    ) {
        self.reference = reference
        self.name = name
        self.state = state
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.userActivations = userActivations
        self.userHunts = userHunts
        self.isActiveNow = isActiveNow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reference = try container.decode(String.self, forKey: .reference)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        userActivations = try container.decodeIfPresent(Int.self, forKey: .userActivations)
        userHunts = try container.decodeIfPresent(Int.self, forKey: .userHunts)
        isActiveNow = try container.decodeIfPresent(Bool.self, forKey: .isActiveNow)
    }

    // MARK: Public

    public let reference: String
    public let name: String?
    public let state: String?
    public let country: String?
    public let latitude: Double?
    public let longitude: Double?
    public let userActivations: Int?
    public let userHunts: Int?
    public let isActiveNow: Bool?

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("park", forKey: .kind)
        try container.encode(EnrichedLinkPayload.schemaVersion, forKey: .version)
        try container.encode(reference, forKey: .reference)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(state, forKey: .state)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(userActivations, forKey: .userActivations)
        try container.encodeIfPresent(userHunts, forKey: .userHunts)
        try container.encodeIfPresent(isActiveNow, forKey: .isActiveNow)
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case kind = "k"
        case version = "v"
        case reference = "r"
        case name = "nm"
        case state = "st"
        case country = "co"
        case latitude = "la"
        case longitude = "lo"
        case userActivations = "ua"
        case userHunts = "uh"
        case isActiveNow = "an"
    }
}

// MARK: - SummitPayload

public struct SummitPayload: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        reference: String,
        name: String? = nil,
        associationName: String? = nil,
        regionName: String? = nil,
        altitudeMeters: Int? = nil,
        points: Int? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        activationCount: Int? = nil,
        userActivations: Int? = nil,
        userChases: Int? = nil
    ) {
        self.reference = reference
        self.name = name
        self.associationName = associationName
        self.regionName = regionName
        self.altitudeMeters = altitudeMeters
        self.points = points
        self.latitude = latitude
        self.longitude = longitude
        self.activationCount = activationCount
        self.userActivations = userActivations
        self.userChases = userChases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reference = try container.decode(String.self, forKey: .reference)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        associationName = try container.decodeIfPresent(String.self, forKey: .associationName)
        regionName = try container.decodeIfPresent(String.self, forKey: .regionName)
        altitudeMeters = try container.decodeIfPresent(Int.self, forKey: .altitudeMeters)
        points = try container.decodeIfPresent(Int.self, forKey: .points)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        activationCount = try container.decodeIfPresent(Int.self, forKey: .activationCount)
        userActivations = try container.decodeIfPresent(Int.self, forKey: .userActivations)
        userChases = try container.decodeIfPresent(Int.self, forKey: .userChases)
    }

    // MARK: Public

    /// SOTA summit reference, e.g. `W4C/CM-001`.
    public let reference: String
    public let name: String?
    public let associationName: String?
    public let regionName: String?
    public let altitudeMeters: Int?
    public let points: Int?
    public let latitude: Double?
    public let longitude: Double?
    /// Global activation count from the SOTA database.
    public let activationCount: Int?
    /// Number of times the sharer has activated this summit (optional, local).
    public let userActivations: Int?
    /// Number of times the sharer has chased this summit (optional, local).
    public let userChases: Int?

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("sum", forKey: .kind)
        try container.encode(EnrichedLinkPayload.schemaVersion, forKey: .version)
        try container.encode(reference, forKey: .reference)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(associationName, forKey: .associationName)
        try container.encodeIfPresent(regionName, forKey: .regionName)
        try container.encodeIfPresent(altitudeMeters, forKey: .altitudeMeters)
        try container.encodeIfPresent(points, forKey: .points)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(activationCount, forKey: .activationCount)
        try container.encodeIfPresent(userActivations, forKey: .userActivations)
        try container.encodeIfPresent(userChases, forKey: .userChases)
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case kind = "k"
        case version = "v"
        case reference = "r"
        case name = "nm"
        case associationName = "as"
        case regionName = "rn"
        case altitudeMeters = "am"
        case points = "pt"
        case latitude = "la"
        case longitude = "lo"
        case activationCount = "ac"
        case userActivations = "ua"
        case userChases = "uc"
    }
}
