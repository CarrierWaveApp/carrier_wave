import CarrierWaveCore
import CloudKit
import Foundation

// MARK: - CKRecordMapper

/// Pure functions mapping SwiftData models to/from CKRecords.
/// Each model type has a `toCKRecord` and `fromCKRecord` pair.
/// All methods are explicitly nonisolated to allow use from any actor context.
enum CKRecordMapper {
    // MARK: - Record Types

    enum RecordType: String, Sendable {
        case qso = "QSO"
        case servicePresence = "ServicePresence"
        case loggingSession = "LoggingSession"
        case activationMetadata = "ActivationMetadata"
        case sessionSpot = "SessionSpot"
        case activityLog = "ActivityLog"
    }

    // MARK: - Constants

    nonisolated static let zoneName = "CarrierWaveData"
    nonisolated static let zoneID = CKRecordZone.ID(
        zoneName: zoneName, ownerName: CKCurrentUserDefaultName
    )

    nonisolated static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    // MARK: - Record Identity

    /// Build a deterministic CKRecord name from entity type and UUID
    nonisolated static func recordName(entityType: String, id: UUID) -> String {
        "\(entityType)-\(id.uuidString)"
    }

    nonisolated static func recordID(type: RecordType, id: UUID) -> CKRecord.ID {
        let name = recordName(entityType: type.rawValue, id: id)
        return CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    /// Parse a UUID from a CKRecord name like "QSO-A1B2C3D4-..."
    nonisolated static func parseUUID(from recordName: String) -> UUID? {
        // Format: "EntityType-UUID"
        guard let dashIndex = recordName.firstIndex(of: "-") else {
            return nil
        }
        let uuidString = String(recordName[recordName.index(after: dashIndex)...])
        return UUID(uuidString: uuidString)
    }

    /// Parse the entity type from a CKRecord name
    nonisolated static func parseEntityType(from recordName: String) -> String? {
        guard let dashIndex = recordName.firstIndex(of: "-") else {
            return nil
        }
        return String(recordName[..<dashIndex])
    }

    // MARK: - QSO Mapping

    /// Whether a mode should be synced (excludes metadata pseudo-modes)
    nonisolated static func shouldSync(mode: String) -> Bool {
        !metadataModes.contains(mode.uppercased())
    }

    /// Convert QSOFields to a CKRecord
    nonisolated static func qsoFieldsToCKRecord(
        _ fields: QSOFields,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.qso.rawValue,
            recordID: recordID(type: .qso, id: fields.id)
        )

        record["id"] = fields.id.uuidString
        record["callsign"] = fields.callsign
        record["band"] = fields.band
        record["mode"] = fields.mode
        record["frequency"] = fields.frequency as CKRecordValue?
        record["timestamp"] = fields.timestamp
        record["rstSent"] = fields.rstSent
        record["rstReceived"] = fields.rstReceived
        record["myCallsign"] = fields.myCallsign
        record["myGrid"] = fields.myGrid
        record["theirGrid"] = fields.theirGrid
        record["parkReference"] = fields.parkReference
        record["theirParkReference"] = fields.theirParkReference
        record["notes"] = fields.notes
        record["importSource"] = fields.importSource.rawValue
        record["importedAt"] = fields.importedAt
        record["modifiedAt"] = fields.modifiedAt
        record["rawADIF"] = fields.rawADIF
        record["name"] = fields.name
        record["qth"] = fields.qth
        record["state"] = fields.state
        record["country"] = fields.country
        record["power"] = fields.power as CKRecordValue?
        record["myRig"] = fields.myRig
        record["stationProfileName"] = fields.stationProfileName
        record["sotaRef"] = fields.sotaRef
        record["qrzLogId"] = fields.qrzLogId
        record["qrzConfirmed"] = fields.qrzConfirmed ? 1 : 0
        record["lotwConfirmedDate"] = fields.lotwConfirmedDate
        record["lotwConfirmed"] = fields.lotwConfirmed ? 1 : 0
        record["dxcc"] = fields.dxcc as CKRecordValue?
        record["theirLicenseClass"] = fields.theirLicenseClass
        record["isHidden"] = fields.isHidden ? 1 : 0
        record["isActivityLogQSO"] = fields.isActivityLogQSO ? 1 : 0
        record["loggingSessionId"] = fields.loggingSessionId?.uuidString

        return record
    }

    /// Populate a QSO from a CKRecord's fields. Returns a struct with all values.
    nonisolated static func qsoFields(from record: CKRecord) -> QSOFields? {
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
            modifiedAt: record["modifiedAt"] as? Date,
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

    // MARK: - ServicePresence Mapping

    /// Convert ServicePresenceFields to a CKRecord
    nonisolated static func servicePresenceFieldsToCKRecord(
        _ fields: ServicePresenceFields,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.servicePresence.rawValue,
            recordID: recordID(type: .servicePresence, id: fields.id)
        )

        record["id"] = fields.id.uuidString
        record["serviceType"] = fields.serviceType.rawValue
        record["isPresent"] = fields.isPresent ? 1 : 0
        record["needsUpload"] = fields.needsUpload ? 1 : 0
        record["uploadRejected"] = fields.uploadRejected ? 1 : 0
        record["isSubmitted"] = fields.isSubmitted ? 1 : 0
        record["lastConfirmedAt"] = fields.lastConfirmedAt
        record["parkReference"] = fields.parkReference

        // Parent reference to QSO
        if let qsoUUID = fields.qsoUUID {
            let qsoRecordID = recordID(type: .qso, id: qsoUUID)
            record["qsoRef"] = CKRecord.Reference(
                recordID: qsoRecordID,
                action: .deleteSelf
            )
        }

        return record
    }

    nonisolated static func servicePresenceFields(
        from record: CKRecord
    ) -> ServicePresenceFields? {
        guard let serviceTypeRaw = record["serviceType"] as? String,
              let serviceType = ServiceType(rawValue: serviceTypeRaw)
        else {
            return nil
        }

        // Extract QSO UUID from parent reference
        let qsoUUID: UUID? = if let ref = record["qsoRef"] as? CKRecord.Reference {
            parseUUID(from: ref.recordID.recordName)
        } else {
            nil
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
}
