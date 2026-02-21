import CloudKit
import Foundation

// MARK: - SessionSpot & ActivityLog CKRecord Mapping

extension CKRecordMapper {
    // MARK: - SessionSpot Mapping

    /// Convert SessionSpotFields to a CKRecord
    nonisolated static func sessionSpotFieldsToCKRecord(
        _ fields: SessionSpotFields,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.sessionSpot.rawValue,
            recordID: recordID(type: .sessionSpot, id: fields.id)
        )

        record["id"] = fields.id.uuidString
        record["loggingSessionId"] = fields.loggingSessionId.uuidString
        record["callsign"] = fields.callsign
        record["frequencyKHz"] = fields.frequencyKHz as CKRecordValue
        record["mode"] = fields.mode
        record["timestamp"] = fields.timestamp
        record["source"] = fields.source
        record["snr"] = fields.snr as CKRecordValue?
        record["wpm"] = fields.wpm as CKRecordValue?
        record["spotter"] = fields.spotter
        record["spotterGrid"] = fields.spotterGrid
        record["parkRef"] = fields.parkRef
        record["parkName"] = fields.parkName
        record["comments"] = fields.comments
        record["region"] = fields.region
        record["distanceMeters"] = fields.distanceMeters as CKRecordValue?

        return record
    }

    /// Parse SessionSpotFields from a CKRecord
    nonisolated static func sessionSpotFields(
        from record: CKRecord
    ) -> SessionSpotFields? {
        guard let callsign = record["callsign"] as? String,
              let mode = record["mode"] as? String,
              let timestamp = record["timestamp"] as? Date,
              let source = record["source"] as? String
        else {
            return nil
        }

        return SessionSpotFields(
            id: (record["id"] as? String).flatMap(UUID.init) ?? UUID(),
            loggingSessionId: (record["loggingSessionId"] as? String)
                .flatMap(UUID.init) ?? UUID(),
            callsign: callsign,
            frequencyKHz: record["frequencyKHz"] as? Double ?? 0,
            mode: mode,
            timestamp: timestamp,
            source: source,
            snr: record["snr"] as? Int,
            wpm: record["wpm"] as? Int,
            spotter: record["spotter"] as? String,
            spotterGrid: record["spotterGrid"] as? String,
            parkRef: record["parkRef"] as? String,
            parkName: record["parkName"] as? String,
            comments: record["comments"] as? String,
            region: record["region"] as? String ?? "other",
            distanceMeters: record["distanceMeters"] as? Double
        )
    }

    // MARK: - ActivityLog Mapping

    /// Convert ActivityLogFields to a CKRecord
    nonisolated static func activityLogFieldsToCKRecord(
        _ fields: ActivityLogFields,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.activityLog.rawValue,
            recordID: recordID(type: .activityLog, id: fields.id)
        )

        record["id"] = fields.id.uuidString
        record["name"] = fields.name
        record["myCallsign"] = fields.myCallsign
        record["createdAt"] = fields.createdAt
        record["stationProfileId"] = fields.stationProfileId?.uuidString
        record["currentGrid"] = fields.currentGrid
        record["locationLabel"] = fields.locationLabel
        record["isActive"] = fields.isActive ? 1 : 0

        return record
    }

    /// Parse ActivityLogFields from a CKRecord
    nonisolated static func activityLogFields(
        from record: CKRecord
    ) -> ActivityLogFields? {
        guard let name = record["name"] as? String,
              let myCallsign = record["myCallsign"] as? String
        else {
            return nil
        }

        return ActivityLogFields(
            id: (record["id"] as? String).flatMap(UUID.init) ?? UUID(),
            name: name,
            myCallsign: myCallsign,
            createdAt: record["createdAt"] as? Date ?? Date(),
            stationProfileId: (record["stationProfileId"] as? String)
                .flatMap(UUID.init),
            currentGrid: record["currentGrid"] as? String,
            locationLabel: record["locationLabel"] as? String,
            isActive: (record["isActive"] as? Int64 ?? 0) != 0
        )
    }
}
