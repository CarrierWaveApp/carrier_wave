import Foundation
import SwiftData

// MARK: - ActivityItem

@Model
nonisolated final class ActivityItem {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        callsign: String,
        activityType: ActivityType,
        timestamp: Date = Date(),
        detailsData: Data = Data(),
        isOwn: Bool = false,
        challengeId: UUID? = nil
    ) {
        self.id = id
        self.callsign = callsign
        activityTypeRawValue = activityType.rawValue
        self.timestamp = timestamp
        self.detailsData = detailsData
        self.isOwn = isOwn
        self.challengeId = challengeId
    }

    // MARK: Internal

    var id = UUID()
    var callsign = ""
    var activityTypeRawValue = ActivityType.dxContact.rawValue
    var timestamp = Date()
    var detailsData = Data()
    var isOwn = false
    var challengeId: UUID?

    var activityType: ActivityType {
        get { ActivityType(rawValue: activityTypeRawValue) ?? .dxContact }
        set { activityTypeRawValue = newValue.rawValue }
    }

    var details: ActivityDetails? {
        get {
            ActivityDetails.decode(from: detailsData)
        }
        set {
            detailsData = newValue?.encode() ?? Data()
        }
    }
}

// MARK: - ActivityDetails

struct ActivityDetails: Sendable {
    // Generic fields that apply to multiple activity types
    var entityName: String? // DXCC entity name
    var entityCode: String? // DXCC entity code
    var band: String?
    var mode: String?
    var distanceKm: Double?
    var workedCallsign: String? // The station worked for DX contacts
    var parkReference: String? // POTA/SOTA reference
    var parkName: String?
    var qsoCount: Int? // For activations
    var streakDays: Int? // For streak activities
    var challengeName: String? // For challenge activities
    var tierName: String? // For tier unlock
    var recordType: String? // For personal bests (e.g., "distance", "qsos_in_day")
    var recordValue: String? // The record value as display string

    // Session summary fields (for sessionCompleted)
    var sessionDurationMinutes: Int?
    var sessionBands: [String]?
    var sessionModes: [String]?
    var sessionDXCCCount: Int?
    var sessionFarthestKm: Double?
    var sessionActivationType: String? // "casual", "pota", "sota"
    var sessionMyGrid: String?
    var sessionRig: String?
    var sessionAntenna: String?
    var sessionContactGrids: [ContactGridEntry]?
    var sessionTimeline: [TimelineEntry]?

    // MARK: - Nonisolated Codable Helpers

    /// Decode from data in a nonisolated context (for use with @Model classes)
    nonisolated static func decode(from data: Data) -> ActivityDetails? {
        try? JSONDecoder().decode(ActivityDetails.self, from: data)
    }

    /// Encode to data in a nonisolated context (for use with @Model classes)
    nonisolated func encode() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

// MARK: Codable

extension ActivityDetails: Codable {
    private enum CodingKeys: String, CodingKey {
        case entityName
        case entityCode
        case band
        case mode
        case distanceKm
        case workedCallsign
        case parkReference
        case parkName
        case qsoCount
        case streakDays
        case challengeName
        case tierName
        case recordType
        case recordValue
        case sessionDurationMinutes
        case sessionBands
        case sessionModes
        case sessionDXCCCount
        case sessionFarthestKm
        case sessionActivationType
        case sessionMyGrid
        case sessionRig
        case sessionAntenna
        case sessionContactGrids
        case sessionTimeline
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entityName = try container.decodeIfPresent(String.self, forKey: .entityName)
        entityCode = try container.decodeIfPresent(String.self, forKey: .entityCode)
        band = try container.decodeIfPresent(String.self, forKey: .band)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        distanceKm = try container.decodeIfPresent(Double.self, forKey: .distanceKm)
        workedCallsign = try container.decodeIfPresent(String.self, forKey: .workedCallsign)
        parkReference = try container.decodeIfPresent(String.self, forKey: .parkReference)
        parkName = try container.decodeIfPresent(String.self, forKey: .parkName)
        qsoCount = try container.decodeIfPresent(Int.self, forKey: .qsoCount)
        streakDays = try container.decodeIfPresent(Int.self, forKey: .streakDays)
        challengeName = try container.decodeIfPresent(String.self, forKey: .challengeName)
        tierName = try container.decodeIfPresent(String.self, forKey: .tierName)
        recordType = try container.decodeIfPresent(String.self, forKey: .recordType)
        recordValue = try container.decodeIfPresent(String.self, forKey: .recordValue)
        sessionDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .sessionDurationMinutes)
        sessionBands = try container.decodeIfPresent([String].self, forKey: .sessionBands)
        sessionModes = try container.decodeIfPresent([String].self, forKey: .sessionModes)
        sessionDXCCCount = try container.decodeIfPresent(Int.self, forKey: .sessionDXCCCount)
        sessionFarthestKm = try container.decodeIfPresent(Double.self, forKey: .sessionFarthestKm)
        sessionActivationType = try container.decodeIfPresent(String.self, forKey: .sessionActivationType)
        sessionMyGrid = try container.decodeIfPresent(String.self, forKey: .sessionMyGrid)
        sessionRig = try container.decodeIfPresent(String.self, forKey: .sessionRig)
        sessionAntenna = try container.decodeIfPresent(String.self, forKey: .sessionAntenna)
        sessionContactGrids = try container.decodeIfPresent([ContactGridEntry].self, forKey: .sessionContactGrids)
        sessionTimeline = try container.decodeIfPresent([TimelineEntry].self, forKey: .sessionTimeline)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(entityName, forKey: .entityName)
        try container.encodeIfPresent(entityCode, forKey: .entityCode)
        try container.encodeIfPresent(band, forKey: .band)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(distanceKm, forKey: .distanceKm)
        try container.encodeIfPresent(workedCallsign, forKey: .workedCallsign)
        try container.encodeIfPresent(parkReference, forKey: .parkReference)
        try container.encodeIfPresent(parkName, forKey: .parkName)
        try container.encodeIfPresent(qsoCount, forKey: .qsoCount)
        try container.encodeIfPresent(streakDays, forKey: .streakDays)
        try container.encodeIfPresent(challengeName, forKey: .challengeName)
        try container.encodeIfPresent(tierName, forKey: .tierName)
        try container.encodeIfPresent(recordType, forKey: .recordType)
        try container.encodeIfPresent(recordValue, forKey: .recordValue)
        try container.encodeIfPresent(sessionDurationMinutes, forKey: .sessionDurationMinutes)
        try container.encodeIfPresent(sessionBands, forKey: .sessionBands)
        try container.encodeIfPresent(sessionModes, forKey: .sessionModes)
        try container.encodeIfPresent(sessionDXCCCount, forKey: .sessionDXCCCount)
        try container.encodeIfPresent(sessionFarthestKm, forKey: .sessionFarthestKm)
        try container.encodeIfPresent(sessionActivationType, forKey: .sessionActivationType)
        try container.encodeIfPresent(sessionMyGrid, forKey: .sessionMyGrid)
        try container.encodeIfPresent(sessionRig, forKey: .sessionRig)
        try container.encodeIfPresent(sessionAntenna, forKey: .sessionAntenna)
        try container.encodeIfPresent(sessionContactGrids, forKey: .sessionContactGrids)
        try container.encodeIfPresent(sessionTimeline, forKey: .sessionTimeline)
    }
}

// MARK: - ContactGridEntry

struct ContactGridEntry: Codable, Sendable {
    var grid: String
    var band: String
}

// MARK: - TimelineEntry

struct TimelineEntry: Codable, Sendable {
    var timestamp: Date
    var band: String
}
