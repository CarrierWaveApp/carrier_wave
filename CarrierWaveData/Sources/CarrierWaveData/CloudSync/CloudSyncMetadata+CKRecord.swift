import CloudKit
import Foundation

public extension CloudSyncMetadata {
    /// Decode the stored system fields back into a skeleton CKRecord.
    /// Returns nil if no system fields are stored.
    nonisolated func decodedRecord() -> CKRecord? {
        guard let data = encodedSystemFields else {
            return nil
        }
        let coder = try? NSKeyedUnarchiver(forReadingFrom: data)
        coder?.requiresSecureCoding = true
        guard let coder else {
            return nil
        }
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }

    /// Encode a CKRecord's system fields for storage
    nonisolated static func encodeSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }
}
