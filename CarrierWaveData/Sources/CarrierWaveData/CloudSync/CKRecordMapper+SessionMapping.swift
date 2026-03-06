import CloudKit
import Foundation

// MARK: - LoggingSession & ActivationMetadata Mapping

public extension CKRecordMapper {
    /// Convert LoggingSessionFields to a CKRecord
    nonisolated static func loggingSessionFieldsToCKRecord(
        _ fields: LoggingSessionFields,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.loggingSession.rawValue,
            recordID: recordID(type: .loggingSession, id: fields.id)
        )

        record["id"] = fields.id.uuidString
        record["myCallsign"] = fields.myCallsign
        record["startedAt"] = fields.startedAt
        record["endedAt"] = fields.endedAt
        record["frequency"] = fields.frequency as CKRecordValue?
        record["mode"] = fields.mode
        record["activationTypeRawValue"] = fields.activationTypeRawValue
        record["statusRawValue"] = fields.statusRawValue
        record["parkReference"] = fields.parkReference
        record["sotaReference"] = fields.sotaReference
        record["wwffReference"] = fields.wwffReference
        record["myGrid"] = fields.myGrid
        record["power"] = fields.power as CKRecordValue?
        record["myRig"] = fields.myRig
        record["notes"] = fields.notes
        record["customTitle"] = fields.customTitle
        record["qsoCount"] = fields.qsoCount
        record["isRove"] = fields.isRove ? 1 : 0
        record["myAntenna"] = fields.myAntenna
        record["myKey"] = fields.myKey
        record["myMic"] = fields.myMic
        record["extraEquipment"] = fields.extraEquipment
        record["attendees"] = fields.attendees
        if !fields.photoFilenames.isEmpty {
            record["photoFilenames"] = fields.photoFilenames as CKRecordValue
        }

        // JSON data fields
        record["spotCommentsData"] = fields.spotCommentsData
        record["roveStopsData"] = fields.roveStopsData

        // Solar conditions
        record["solarKIndex"] = fields.solarKIndex as CKRecordValue?
        record["solarFlux"] = fields.solarFlux as CKRecordValue?
        record["solarSunspots"] = fields.solarSunspots as CKRecordValue?
        record["solarPropagationRating"] = fields.solarPropagationRating
        record["solarAIndex"] = fields.solarAIndex as CKRecordValue?
        record["solarBandConditions"] = fields.solarBandConditions
        record["solarTimestamp"] = fields.solarTimestamp
        record["solarConditions"] = fields.solarConditions

        // Weather conditions
        record["weatherTemperatureF"] = fields.weatherTemperatureF as CKRecordValue?
        record["weatherTemperatureC"] = fields.weatherTemperatureC as CKRecordValue?
        record["weatherHumidity"] = fields.weatherHumidity as CKRecordValue?
        record["weatherWindSpeed"] = fields.weatherWindSpeed as CKRecordValue?
        record["weatherWindDirection"] = fields.weatherWindDirection
        record["weatherDescription"] = fields.weatherDescription
        record["weatherTimestamp"] = fields.weatherTimestamp
        record["weather"] = fields.weather

        return record
    }

    nonisolated static func loggingSessionFields(
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
            activationTypeRawValue: (record["activationTypeRawValue"] as? String) ?? ActivationType.casual.rawValue,
            statusRawValue: (record["statusRawValue"] as? String) ?? LoggingSessionStatus.completed.rawValue,
            parkReference: record["parkReference"] as? String,
            sotaReference: record["sotaReference"] as? String,
            wwffReference: record["wwffReference"] as? String,
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

    /// Convert ActivationMetadataFields to a CKRecord
    nonisolated static func activationMetadataFieldsToCKRecord(
        _ fields: ActivationMetadataFields,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let syntheticID = activationMetadataID(
            parkReference: fields.parkReference,
            date: fields.date
        )
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.activationMetadata.rawValue,
            recordID: recordID(type: .activationMetadata, id: syntheticID)
        )

        record["parkReference"] = fields.parkReference
        record["date"] = fields.date
        record["title"] = fields.title
        record["watts"] = fields.watts as CKRecordValue?
        record["weather"] = fields.weather
        record["solarConditions"] = fields.solarConditions
        record["averageWPM"] = fields.averageWPM as CKRecordValue?

        // Structured solar
        record["solarKIndex"] = fields.solarKIndex as CKRecordValue?
        record["solarFlux"] = fields.solarFlux as CKRecordValue?
        record["solarSunspots"] = fields.solarSunspots as CKRecordValue?
        record["solarPropagationRating"] = fields.solarPropagationRating
        record["solarAIndex"] = fields.solarAIndex as CKRecordValue?
        record["solarBandConditions"] = fields.solarBandConditions
        record["solarTimestamp"] = fields.solarTimestamp

        // Structured weather
        record["weatherTemperatureF"] = fields.weatherTemperatureF as CKRecordValue?
        record["weatherTemperatureC"] = fields.weatherTemperatureC as CKRecordValue?
        record["weatherHumidity"] = fields.weatherHumidity as CKRecordValue?
        record["weatherWindSpeed"] = fields.weatherWindSpeed as CKRecordValue?
        record["weatherWindDirection"] = fields.weatherWindDirection
        record["weatherDescription"] = fields.weatherDescription
        record["weatherTimestamp"] = fields.weatherTimestamp

        return record
    }

    nonisolated static func activationMetadataFields(
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
    nonisolated static func activationMetadataID(
        parkReference: String,
        date: Date
    ) -> UUID {
        let key = "\(parkReference.uppercased())|\(Int(date.timeIntervalSince1970))"
        let data = Data(key.utf8)
        var hash = [UInt8](repeating: 0, count: 16)
        data.withUnsafeBytes { buffer in
            for (index, byte) in buffer.enumerated() {
                hash[index % 16] ^= byte
            }
        }
        // Set version 5 and variant bits
        hash[6] = (hash[6] & 0x0F) | 0x50
        hash[8] = (hash[8] & 0x3F) | 0x80
        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
    }
}
