import CarrierWaveCore
import CloudKit
import Foundation

/// Pure functions mapping SwiftData models to/from CKRecords.
/// Each model type has a `toCKRecord` and `fromCKRecord` pair.
enum CKRecordMapper {
    // MARK: - Constants

    static let zoneName = "CarrierWaveData"
    static let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

    static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    // MARK: - Record Types

    enum RecordType: String {
        case qso = "QSO"
        case servicePresence = "ServicePresence"
        case loggingSession = "LoggingSession"
        case activationMetadata = "ActivationMetadata"
    }

    // MARK: - Record Identity

    static func recordID(type: RecordType, id: UUID) -> CKRecord.ID {
        let name = CloudSyncMetadata.recordName(entityType: type.rawValue, id: id)
        return CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    /// Parse a UUID from a CKRecord name like "QSO-A1B2C3D4-..."
    static func parseUUID(from recordName: String) -> UUID? {
        // Format: "EntityType-UUID"
        guard let dashIndex = recordName.firstIndex(of: "-") else {
            return nil
        }
        let uuidString = String(recordName[recordName.index(after: dashIndex)...])
        return UUID(uuidString: uuidString)
    }

    /// Parse the entity type from a CKRecord name
    static func parseEntityType(from recordName: String) -> String? {
        guard let dashIndex = recordName.firstIndex(of: "-") else {
            return nil
        }
        return String(recordName[..<dashIndex])
    }

    // MARK: - QSO Mapping

    /// Whether a QSO should be synced (excludes metadata pseudo-modes)
    static func shouldSync(qso: QSO) -> Bool {
        !metadataModes.contains(qso.mode.uppercased())
    }

    static func qsoToCKRecord(
        _ qso: QSO,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.qso.rawValue,
            recordID: recordID(type: .qso, id: qso.id)
        )

        record["id"] = qso.id.uuidString
        record["callsign"] = qso.callsign
        record["band"] = qso.band
        record["mode"] = qso.mode
        record["frequency"] = qso.frequency as CKRecordValue?
        record["timestamp"] = qso.timestamp
        record["rstSent"] = qso.rstSent
        record["rstReceived"] = qso.rstReceived
        record["myCallsign"] = qso.myCallsign
        record["myGrid"] = qso.myGrid
        record["theirGrid"] = qso.theirGrid
        record["parkReference"] = qso.parkReference
        record["theirParkReference"] = qso.theirParkReference
        record["notes"] = qso.notes
        record["importSource"] = qso.importSource.rawValue
        record["importedAt"] = qso.importedAt
        record["rawADIF"] = qso.rawADIF
        record["name"] = qso.name
        record["qth"] = qso.qth
        record["state"] = qso.state
        record["country"] = qso.country
        record["power"] = qso.power as CKRecordValue?
        record["myRig"] = qso.myRig
        record["stationProfileName"] = qso.stationProfileName
        record["sotaRef"] = qso.sotaRef
        record["qrzLogId"] = qso.qrzLogId
        record["qrzConfirmed"] = qso.qrzConfirmed ? 1 : 0
        record["lotwConfirmedDate"] = qso.lotwConfirmedDate
        record["lotwConfirmed"] = qso.lotwConfirmed ? 1 : 0
        record["dxcc"] = qso.dxcc as CKRecordValue?
        record["theirLicenseClass"] = qso.theirLicenseClass
        record["isHidden"] = qso.isHidden ? 1 : 0
        record["isActivityLogQSO"] = qso.isActivityLogQSO ? 1 : 0
        record["loggingSessionId"] = qso.loggingSessionId?.uuidString

        return record
    }

    /// Populate a QSO from a CKRecord's fields. Returns a struct with all values.
    static func qsoFields(from record: CKRecord) -> QSOFields? {
        guard let callsign = record["callsign"] as? String,
              let band = record["band"] as? String,
              let mode = record["mode"] as? String,
              let timestamp = record["timestamp"] as? Date,
              let myCallsign = record["myCallsign"] as? String,
              let importSourceRaw = record["importSource"] as? String,
              let importSource = ImportSource(rawValue: importSourceRaw)
        else {
            return nil
        }

        return QSOFields(
            id: (record["id"] as? String).flatMap(UUID.init) ?? UUID(),
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: record["frequency"] as? Double,
            timestamp: timestamp,
            rstSent: record["rstSent"] as? String,
            rstReceived: record["rstReceived"] as? String,
            myCallsign: myCallsign,
            myGrid: record["myGrid"] as? String,
            theirGrid: record["theirGrid"] as? String,
            parkReference: record["parkReference"] as? String,
            theirParkReference: record["theirParkReference"] as? String,
            notes: record["notes"] as? String,
            importSource: importSource,
            importedAt: record["importedAt"] as? Date ?? Date(),
            rawADIF: record["rawADIF"] as? String,
            name: record["name"] as? String,
            qth: record["qth"] as? String,
            state: record["state"] as? String,
            country: record["country"] as? String,
            power: record["power"] as? Int,
            myRig: record["myRig"] as? String,
            stationProfileName: record["stationProfileName"] as? String,
            sotaRef: record["sotaRef"] as? String,
            qrzLogId: record["qrzLogId"] as? String,
            qrzConfirmed: (record["qrzConfirmed"] as? Int64 ?? 0) != 0,
            lotwConfirmedDate: record["lotwConfirmedDate"] as? Date,
            lotwConfirmed: (record["lotwConfirmed"] as? Int64 ?? 0) != 0,
            dxcc: record["dxcc"] as? Int,
            theirLicenseClass: record["theirLicenseClass"] as? String,
            isHidden: (record["isHidden"] as? Int64 ?? 0) != 0,
            isActivityLogQSO: (record["isActivityLogQSO"] as? Int64 ?? 0) != 0,
            loggingSessionId: (record["loggingSessionId"] as? String).flatMap(UUID.init)
        )
    }

    /// Apply QSOFields to a QSO model
    static func applyFields(_ fields: QSOFields, to qso: QSO) {
        qso.callsign = fields.callsign
        qso.band = fields.band
        qso.mode = fields.mode
        qso.frequency = fields.frequency
        qso.timestamp = fields.timestamp
        qso.rstSent = fields.rstSent
        qso.rstReceived = fields.rstReceived
        qso.myCallsign = fields.myCallsign
        qso.myGrid = fields.myGrid
        qso.theirGrid = fields.theirGrid
        qso.parkReference = fields.parkReference
        qso.theirParkReference = fields.theirParkReference
        qso.notes = fields.notes
        qso.importSource = fields.importSource
        qso.importedAt = fields.importedAt
        qso.rawADIF = fields.rawADIF
        qso.name = fields.name
        qso.qth = fields.qth
        qso.state = fields.state
        qso.country = fields.country
        qso.power = fields.power
        qso.myRig = fields.myRig
        qso.stationProfileName = fields.stationProfileName
        qso.sotaRef = fields.sotaRef
        qso.qrzLogId = fields.qrzLogId
        qso.qrzConfirmed = fields.qrzConfirmed
        qso.lotwConfirmedDate = fields.lotwConfirmedDate
        qso.lotwConfirmed = fields.lotwConfirmed
        qso.dxcc = fields.dxcc
        qso.theirLicenseClass = fields.theirLicenseClass
        qso.isHidden = fields.isHidden
        qso.isActivityLogQSO = fields.isActivityLogQSO
        qso.loggingSessionId = fields.loggingSessionId
    }

    // MARK: - ServicePresence Mapping

    static func servicePresenceToCKRecord(
        _ presence: ServicePresence,
        qsoID: UUID,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.servicePresence.rawValue,
            recordID: recordID(type: .servicePresence, id: presence.id)
        )

        record["id"] = presence.id.uuidString
        record["serviceType"] = presence.serviceType.rawValue
        record["isPresent"] = presence.isPresent ? 1 : 0
        record["needsUpload"] = presence.needsUpload ? 1 : 0
        record["uploadRejected"] = presence.uploadRejected ? 1 : 0
        record["isSubmitted"] = presence.isSubmitted ? 1 : 0
        record["lastConfirmedAt"] = presence.lastConfirmedAt
        record["parkReference"] = presence.parkReference

        // Parent reference to QSO
        let qsoRecordID = recordID(type: .qso, id: qsoID)
        record["qsoRef"] = CKRecord.Reference(
            recordID: qsoRecordID,
            action: .deleteSelf
        )

        return record
    }

    static func servicePresenceFields(
        from record: CKRecord
    ) -> ServicePresenceFields? {
        guard let serviceTypeRaw = record["serviceType"] as? String,
              let serviceType = ServiceType(rawValue: serviceTypeRaw)
        else {
            return nil
        }

        // Extract QSO UUID from parent reference
        let qsoUUID: UUID?
        if let ref = record["qsoRef"] as? CKRecord.Reference {
            qsoUUID = parseUUID(from: ref.recordID.recordName)
        } else {
            qsoUUID = nil
        }

        return ServicePresenceFields(
            id: (record["id"] as? String).flatMap(UUID.init) ?? UUID(),
            serviceType: serviceType,
            isPresent: (record["isPresent"] as? Int64 ?? 0) != 0,
            needsUpload: (record["needsUpload"] as? Int64 ?? 0) != 0,
            uploadRejected: (record["uploadRejected"] as? Int64 ?? 0) != 0,
            isSubmitted: (record["isSubmitted"] as? Int64 ?? 0) != 0,
            lastConfirmedAt: record["lastConfirmedAt"] as? Date,
            parkReference: record["parkReference"] as? String,
            qsoUUID: qsoUUID
        )
    }

    // MARK: - LoggingSession Mapping

    static func loggingSessionToCKRecord(
        _ session: LoggingSession,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.loggingSession.rawValue,
            recordID: recordID(type: .loggingSession, id: session.id)
        )

        record["id"] = session.id.uuidString
        record["myCallsign"] = session.myCallsign
        record["startedAt"] = session.startedAt
        record["endedAt"] = session.endedAt
        record["frequency"] = session.frequency as CKRecordValue?
        record["mode"] = session.mode
        record["activationTypeRawValue"] = session.activationTypeRawValue
        record["statusRawValue"] = session.statusRawValue
        record["parkReference"] = session.parkReference
        record["sotaReference"] = session.sotaReference
        record["myGrid"] = session.myGrid
        record["power"] = session.power as CKRecordValue?
        record["myRig"] = session.myRig
        record["notes"] = session.notes
        record["customTitle"] = session.customTitle
        record["qsoCount"] = session.qsoCount
        record["isRove"] = session.isRove ? 1 : 0
        record["myAntenna"] = session.myAntenna
        record["myKey"] = session.myKey
        record["myMic"] = session.myMic
        record["extraEquipment"] = session.extraEquipment
        record["attendees"] = session.attendees
        record["photoFilenames"] = session.photoFilenames as CKRecordValue

        // JSON data fields stored as Data (CKAsset-like but small enough for inline)
        record["spotCommentsData"] = session.spotCommentsData
        record["roveStopsData"] = session.roveStopsData

        // Solar conditions
        record["solarKIndex"] = session.solarKIndex as CKRecordValue?
        record["solarFlux"] = session.solarFlux as CKRecordValue?
        record["solarSunspots"] = session.solarSunspots as CKRecordValue?
        record["solarPropagationRating"] = session.solarPropagationRating
        record["solarAIndex"] = session.solarAIndex as CKRecordValue?
        record["solarBandConditions"] = session.solarBandConditions
        record["solarTimestamp"] = session.solarTimestamp
        record["solarConditions"] = session.solarConditions

        // Weather conditions
        record["weatherTemperatureF"] = session.weatherTemperatureF as CKRecordValue?
        record["weatherTemperatureC"] = session.weatherTemperatureC as CKRecordValue?
        record["weatherHumidity"] = session.weatherHumidity as CKRecordValue?
        record["weatherWindSpeed"] = session.weatherWindSpeed as CKRecordValue?
        record["weatherWindDirection"] = session.weatherWindDirection
        record["weatherDescription"] = session.weatherDescription
        record["weatherTimestamp"] = session.weatherTimestamp
        record["weather"] = session.weather

        return record
    }

    static func loggingSessionFields(
        from record: CKRecord
    ) -> LoggingSessionFields? {
        guard let myCallsign = record["myCallsign"] as? String,
              let startedAt = record["startedAt"] as? Date
        else {
            return nil
        }

        return LoggingSessionFields(
            id: (record["id"] as? String).flatMap(UUID.init) ?? UUID(),
            myCallsign: myCallsign,
            startedAt: startedAt,
            endedAt: record["endedAt"] as? Date,
            frequency: record["frequency"] as? Double,
            mode: record["mode"] as? String ?? "CW",
            activationTypeRawValue: record["activationTypeRawValue"] as? String
                ?? ActivationType.casual.rawValue,
            statusRawValue: record["statusRawValue"] as? String
                ?? LoggingSessionStatus.completed.rawValue,
            parkReference: record["parkReference"] as? String,
            sotaReference: record["sotaReference"] as? String,
            myGrid: record["myGrid"] as? String,
            power: record["power"] as? Int,
            myRig: record["myRig"] as? String,
            notes: record["notes"] as? String,
            customTitle: record["customTitle"] as? String,
            qsoCount: (record["qsoCount"] as? Int) ?? 0,
            isRove: (record["isRove"] as? Int64 ?? 0) != 0,
            myAntenna: record["myAntenna"] as? String,
            myKey: record["myKey"] as? String,
            myMic: record["myMic"] as? String,
            extraEquipment: record["extraEquipment"] as? String,
            attendees: record["attendees"] as? String,
            photoFilenames: record["photoFilenames"] as? [String] ?? [],
            spotCommentsData: record["spotCommentsData"] as? Data,
            roveStopsData: record["roveStopsData"] as? Data,
            solarKIndex: record["solarKIndex"] as? Double,
            solarFlux: record["solarFlux"] as? Double,
            solarSunspots: record["solarSunspots"] as? Int,
            solarPropagationRating: record["solarPropagationRating"] as? String,
            solarAIndex: record["solarAIndex"] as? Int,
            solarBandConditions: record["solarBandConditions"] as? String,
            solarTimestamp: record["solarTimestamp"] as? Date,
            solarConditions: record["solarConditions"] as? String,
            weatherTemperatureF: record["weatherTemperatureF"] as? Double,
            weatherTemperatureC: record["weatherTemperatureC"] as? Double,
            weatherHumidity: record["weatherHumidity"] as? Int,
            weatherWindSpeed: record["weatherWindSpeed"] as? Double,
            weatherWindDirection: record["weatherWindDirection"] as? String,
            weatherDescription: record["weatherDescription"] as? String,
            weatherTimestamp: record["weatherTimestamp"] as? Date,
            weather: record["weather"] as? String
        )
    }

    // MARK: - ActivationMetadata Mapping

    static func activationMetadataToCKRecord(
        _ metadata: ActivationMetadata,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        // ActivationMetadata doesn't have a UUID id, so we derive one from park+date
        let syntheticID = activationMetadataID(
            parkReference: metadata.parkReference,
            date: metadata.date
        )
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.activationMetadata.rawValue,
            recordID: recordID(type: .activationMetadata, id: syntheticID)
        )

        record["parkReference"] = metadata.parkReference
        record["date"] = metadata.date
        record["title"] = metadata.title
        record["watts"] = metadata.watts as CKRecordValue?
        record["weather"] = metadata.weather
        record["solarConditions"] = metadata.solarConditions
        record["averageWPM"] = metadata.averageWPM as CKRecordValue?

        // Structured solar
        record["solarKIndex"] = metadata.solarKIndex as CKRecordValue?
        record["solarFlux"] = metadata.solarFlux as CKRecordValue?
        record["solarSunspots"] = metadata.solarSunspots as CKRecordValue?
        record["solarPropagationRating"] = metadata.solarPropagationRating
        record["solarAIndex"] = metadata.solarAIndex as CKRecordValue?
        record["solarBandConditions"] = metadata.solarBandConditions
        record["solarTimestamp"] = metadata.solarTimestamp

        // Structured weather
        record["weatherTemperatureF"] = metadata.weatherTemperatureF as CKRecordValue?
        record["weatherTemperatureC"] = metadata.weatherTemperatureC as CKRecordValue?
        record["weatherHumidity"] = metadata.weatherHumidity as CKRecordValue?
        record["weatherWindSpeed"] = metadata.weatherWindSpeed as CKRecordValue?
        record["weatherWindDirection"] = metadata.weatherWindDirection
        record["weatherDescription"] = metadata.weatherDescription
        record["weatherTimestamp"] = metadata.weatherTimestamp

        return record
    }

    static func activationMetadataFields(
        from record: CKRecord
    ) -> ActivationMetadataFields? {
        guard let parkReference = record["parkReference"] as? String,
              let date = record["date"] as? Date
        else {
            return nil
        }

        return ActivationMetadataFields(
            parkReference: parkReference,
            date: date,
            title: record["title"] as? String,
            watts: record["watts"] as? Int,
            weather: record["weather"] as? String,
            solarConditions: record["solarConditions"] as? String,
            averageWPM: record["averageWPM"] as? Int,
            solarKIndex: record["solarKIndex"] as? Double,
            solarFlux: record["solarFlux"] as? Double,
            solarSunspots: record["solarSunspots"] as? Int,
            solarPropagationRating: record["solarPropagationRating"] as? String,
            solarAIndex: record["solarAIndex"] as? Int,
            solarBandConditions: record["solarBandConditions"] as? String,
            solarTimestamp: record["solarTimestamp"] as? Date,
            weatherTemperatureF: record["weatherTemperatureF"] as? Double,
            weatherTemperatureC: record["weatherTemperatureC"] as? Double,
            weatherHumidity: record["weatherHumidity"] as? Int,
            weatherWindSpeed: record["weatherWindSpeed"] as? Double,
            weatherWindDirection: record["weatherWindDirection"] as? String,
            weatherDescription: record["weatherDescription"] as? String,
            weatherTimestamp: record["weatherTimestamp"] as? Date
        )
    }

    /// Generate a deterministic UUID from park reference + date
    static func activationMetadataID(
        parkReference: String,
        date: Date
    ) -> UUID {
        let key = "\(parkReference.uppercased())|\(Int(date.timeIntervalSince1970))"
        // Create a deterministic UUID from the key using UUID v5 style hashing
        let data = Data(key.utf8)
        var hash = [UInt8](repeating: 0, count: 16)
        data.withUnsafeBytes { buffer in
            for (i, byte) in buffer.enumerated() {
                hash[i % 16] ^= byte
            }
        }
        // Set version 5 and variant bits
        hash[6] = (hash[6] & 0x0F) | 0x50 // version 5
        hash[8] = (hash[8] & 0x3F) | 0x80 // variant 1
        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
    }
}

// MARK: - Field Structs (Sendable intermediaries)

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

    var deduplicationKey: String {
        let roundedTimestamp = timestamp.timeIntervalSince1970
        let rounded = Int(roundedTimestamp / 120) * 120
        let trimmedCallsign = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let canonicalMode = ModeEquivalence.canonicalName(mode).uppercased()
        return "\(trimmedCallsign)|\(band.uppercased())|\(canonicalMode)|\(rounded)"
    }
}

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
