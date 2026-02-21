import CarrierWaveCore
import Foundation

// MARK: - QSOFields

/// Sendable snapshot of QSO fields extracted from a CKRecord
struct QSOFields: Sendable {
    let id: UUID
    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let timestamp: Date
    let rstSent: String?
    let rstReceived: String?
    let myCallsign: String
    let myGrid: String?
    let theirGrid: String?
    let parkReference: String?
    let theirParkReference: String?
    let notes: String?
    let importSource: ImportSource
    let importedAt: Date
    let modifiedAt: Date?
    let rawADIF: String?
    let name: String?
    let qth: String?
    let state: String?
    let country: String?
    let power: Int?
    let myRig: String?
    let stationProfileName: String?
    let sotaRef: String?
    let qrzLogId: String?
    let qrzConfirmed: Bool
    let lotwConfirmedDate: Date?
    let lotwConfirmed: Bool
    let dxcc: Int?
    let theirLicenseClass: String?
    let isHidden: Bool
    let isActivityLogQSO: Bool
    let loggingSessionId: UUID?

    nonisolated var deduplicationKey: String {
        let roundedTimestamp = timestamp.timeIntervalSince1970
        let rounded = Int(roundedTimestamp / 120) * 120
        let trimmedCallsign = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let canonicalMode = ModeEquivalence.canonicalName(mode).uppercased()
        return "\(trimmedCallsign)|\(band.uppercased())|\(canonicalMode)|\(rounded)"
    }
}

// MARK: - ServicePresenceFields

/// Sendable snapshot of ServicePresence fields
struct ServicePresenceFields: Sendable {
    let id: UUID
    let serviceType: ServiceType
    let isPresent: Bool
    let needsUpload: Bool
    let uploadRejected: Bool
    let isSubmitted: Bool
    let lastConfirmedAt: Date?
    let parkReference: String?
    let qsoUUID: UUID?
}

// MARK: - LoggingSessionFields

/// Sendable snapshot of LoggingSession fields
struct LoggingSessionFields: Sendable {
    let id: UUID
    let myCallsign: String
    let startedAt: Date
    let endedAt: Date?
    let frequency: Double?
    let mode: String
    let activationTypeRawValue: String
    let statusRawValue: String
    let parkReference: String?
    let sotaReference: String?
    let myGrid: String?
    let power: Int?
    let myRig: String?
    let notes: String?
    let customTitle: String?
    let qsoCount: Int
    let isRove: Bool
    let myAntenna: String?
    let myKey: String?
    let myMic: String?
    let extraEquipment: String?
    let attendees: String?
    let photoFilenames: [String]
    let spotCommentsData: Data?
    let roveStopsData: Data?
    let solarKIndex: Double?
    let solarFlux: Double?
    let solarSunspots: Int?
    let solarPropagationRating: String?
    let solarAIndex: Int?
    let solarBandConditions: String?
    let solarTimestamp: Date?
    let solarConditions: String?
    let weatherTemperatureF: Double?
    let weatherTemperatureC: Double?
    let weatherHumidity: Int?
    let weatherWindSpeed: Double?
    let weatherWindDirection: String?
    let weatherDescription: String?
    let weatherTimestamp: Date?
    let weather: String?
}

// MARK: - ActivationMetadataFields

/// Sendable snapshot of ActivationMetadata fields
struct ActivationMetadataFields: Sendable {
    let parkReference: String
    let date: Date
    let title: String?
    let watts: Int?
    let weather: String?
    let solarConditions: String?
    let averageWPM: Int?
    let solarKIndex: Double?
    let solarFlux: Double?
    let solarSunspots: Int?
    let solarPropagationRating: String?
    let solarAIndex: Int?
    let solarBandConditions: String?
    let solarTimestamp: Date?
    let weatherTemperatureF: Double?
    let weatherTemperatureC: Double?
    let weatherHumidity: Int?
    let weatherWindSpeed: Double?
    let weatherWindDirection: String?
    let weatherDescription: String?
    let weatherTimestamp: Date?
}
