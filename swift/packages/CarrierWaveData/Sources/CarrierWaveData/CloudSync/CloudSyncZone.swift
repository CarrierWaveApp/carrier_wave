import CloudKit
import Foundation

/// Shared CloudKit zone constants for journal-based sync.
public enum CloudSyncZone {
    public static let zoneName = "CarrierWaveData"
    public static let zoneID = CKRecordZone.ID(
        zoneName: zoneName, ownerName: CKCurrentUserDefaultName
    )
}
