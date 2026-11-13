//
//  EnrichedLinkPayload+QSO.swift
//  CarrierWaveCore
//
//  QSO and Activation payload structs for enriched share links. Split from
//  EnrichedLinkPayload.swift to keep each file under the 500-line limit.
//

import Foundation

// MARK: - QSOPayload

public struct QSOPayload: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        theirCall: String,
        myCall: String,
        band: String,
        mode: String,
        timestamp: Date,
        frequency: Double? = nil,
        rstSent: String? = nil,
        rstReceived: String? = nil,
        myGrid: String? = nil,
        theirGrid: String? = nil,
        parkReference: String? = nil,
        notes: String? = nil
    ) {
        self.theirCall = theirCall
        self.myCall = myCall
        self.band = band
        self.mode = mode
        self.timestamp = timestamp
        self.frequency = frequency
        self.rstSent = rstSent
        self.rstReceived = rstReceived
        self.myGrid = myGrid
        self.theirGrid = theirGrid
        self.parkReference = parkReference
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theirCall = try container.decode(String.self, forKey: .theirCall)
        myCall = try container.decode(String.self, forKey: .myCall)
        band = try container.decode(String.self, forKey: .band)
        mode = try container.decode(String.self, forKey: .mode)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        frequency = try container.decodeIfPresent(Double.self, forKey: .frequency)
        rstSent = try container.decodeIfPresent(String.self, forKey: .rstSent)
        rstReceived = try container.decodeIfPresent(String.self, forKey: .rstReceived)
        myGrid = try container.decodeIfPresent(String.self, forKey: .myGrid)
        theirGrid = try container.decodeIfPresent(String.self, forKey: .theirGrid)
        parkReference = try container.decodeIfPresent(String.self, forKey: .parkReference)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    // MARK: Public

    public let theirCall: String
    public let myCall: String
    public let band: String
    public let mode: String
    public let timestamp: Date
    public let frequency: Double?
    public let rstSent: String?
    public let rstReceived: String?
    public let myGrid: String?
    public let theirGrid: String?
    public let parkReference: String?
    public let notes: String?

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("qso", forKey: .kind)
        try container.encode(EnrichedLinkPayload.schemaVersion, forKey: .version)
        try container.encode(theirCall, forKey: .theirCall)
        try container.encode(myCall, forKey: .myCall)
        try container.encode(band, forKey: .band)
        try container.encode(mode, forKey: .mode)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(frequency, forKey: .frequency)
        try container.encodeIfPresent(rstSent, forKey: .rstSent)
        try container.encodeIfPresent(rstReceived, forKey: .rstReceived)
        try container.encodeIfPresent(myGrid, forKey: .myGrid)
        try container.encodeIfPresent(theirGrid, forKey: .theirGrid)
        try container.encodeIfPresent(parkReference, forKey: .parkReference)
        try container.encodeIfPresent(notes, forKey: .notes)
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case kind = "k"
        case version = "v"
        case theirCall = "c"
        case myCall = "me"
        case band = "b"
        case mode = "md"
        case timestamp = "ts"
        case frequency = "f"
        case rstSent = "rs"
        case rstReceived = "rr"
        case myGrid = "mg"
        case theirGrid = "tg"
        case parkReference = "p"
        case notes = "nt"
    }
}

// MARK: - ActivationPayload

public struct ActivationPayload: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        myCall: String,
        parkReference: String,
        parkName: String? = nil,
        startTime: Date,
        endTime: Date? = nil,
        qsoCount: Int,
        bands: [String] = [],
        modes: [String] = [],
        parkToParkCount: Int? = nil,
        dxccCount: Int? = nil,
        notes: String? = nil
    ) {
        self.myCall = myCall
        self.parkReference = parkReference
        self.parkName = parkName
        self.startTime = startTime
        self.endTime = endTime
        self.qsoCount = qsoCount
        self.bands = bands
        self.modes = modes
        self.parkToParkCount = parkToParkCount
        self.dxccCount = dxccCount
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        myCall = try container.decode(String.self, forKey: .myCall)
        parkReference = try container.decode(String.self, forKey: .parkReference)
        parkName = try container.decodeIfPresent(String.self, forKey: .parkName)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        qsoCount = try container.decode(Int.self, forKey: .qsoCount)
        bands = try container.decodeIfPresent([String].self, forKey: .bands) ?? []
        modes = try container.decodeIfPresent([String].self, forKey: .modes) ?? []
        parkToParkCount = try container.decodeIfPresent(Int.self, forKey: .parkToParkCount)
        dxccCount = try container.decodeIfPresent(Int.self, forKey: .dxccCount)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    // MARK: Public

    /// Maximum number of bands/modes to encode in the fragment. Truncated
    /// from the front (most-recent / most-used kept) by callers as needed.
    public static let maxBandModeArrayLength = 5

    /// Maximum length of an activation note in the fragment.
    public static let maxNoteLength = 80

    public let myCall: String
    public let parkReference: String
    public let parkName: String?
    public let startTime: Date
    public let endTime: Date?
    public let qsoCount: Int
    public let bands: [String]
    public let modes: [String]
    public let parkToParkCount: Int?
    public let dxccCount: Int?
    public let notes: String?

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("act", forKey: .kind)
        try container.encode(EnrichedLinkPayload.schemaVersion, forKey: .version)
        try container.encode(myCall, forKey: .myCall)
        try container.encode(parkReference, forKey: .parkReference)
        try container.encodeIfPresent(parkName, forKey: .parkName)
        try container.encode(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encode(qsoCount, forKey: .qsoCount)
        if !bands.isEmpty {
            try container.encode(bands, forKey: .bands)
        }
        if !modes.isEmpty {
            try container.encode(modes, forKey: .modes)
        }
        try container.encodeIfPresent(parkToParkCount, forKey: .parkToParkCount)
        try container.encodeIfPresent(dxccCount, forKey: .dxccCount)
        try container.encodeIfPresent(notes, forKey: .notes)
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case kind = "k"
        case version = "v"
        case myCall = "me"
        case parkReference = "p"
        case parkName = "pn"
        case startTime = "st"
        case endTime = "et"
        case qsoCount = "qc"
        case bands = "bs"
        case modes = "ms"
        case parkToParkCount = "p2p"
        case dxccCount = "dx"
        case notes = "nt"
    }
}
