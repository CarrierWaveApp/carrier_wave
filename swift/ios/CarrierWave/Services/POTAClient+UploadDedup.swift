import CarrierWaveData
import Foundation

extension POTAClient {
    /// Drop duplicate QSO instances that share a dedup key, keeping the
    /// most-recently-modified one. Logs when duplicates are dropped so the
    /// upstream QSOProcessingActor duplicate-insert bug can be detected in the
    /// wild. See CAR-245.
    static func deduplicateForUpload(_ qsos: [QSO]) -> [QSO] {
        var byKey: [String: QSO] = [:]
        var dropped = 0
        for qso in qsos {
            let key = qso.deduplicationKey
            if let existing = byKey[key] {
                let existingMod = existing.modifiedAt ?? existing.importedAt
                let candidateMod = qso.modifiedAt ?? qso.importedAt
                if candidateMod > existingMod {
                    byKey[key] = qso
                }
                dropped += 1
            } else {
                byKey[key] = qso
            }
        }
        if dropped > 0 {
            SyncDebugLog.shared.warning(
                "POTA upload: dropped \(dropped) duplicate QSO instance(s) before "
                    + "ADIF generation (likely from CAR-245 download-merge bug). "
                    + "Kept most-recently-modified per (callsign,band,mode,time) tuple.",
                service: .pota
            )
        }
        return Array(byKey.values).sorted { $0.timestamp < $1.timestamp }
    }
}
