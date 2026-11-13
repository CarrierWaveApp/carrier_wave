import CarrierWaveData
import SwiftUI

// MARK: - QSORowSnapshot from a live QSO

extension QSORowSnapshot {
    /// Map a live SwiftData `QSO` to the unified row snapshot the Logbook renders.
    /// The `id` uses the same lowercase-UUID convention as the Rust store
    /// (`SwiftDataStoreImporter.uuid`) so selection/delete bridge identically across
    /// backends. Presence is derived from the (already-faulted) `servicePresence`
    /// relationship the old `QSORow` read, so this adds no fetch cost.
    init(qso: QSO) {
        self.init(
            id: SwiftDataStoreImporter.uuid(qso.id),
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            timestamp: qso.timestamp,
            frequency: qso.frequency,
            rstSent: qso.rstSent,
            theirGrid: qso.theirGrid,
            parkReference: qso.parkReference,
            name: qso.name,
            power: qso.power,
            state: qso.state,
            lotwConfirmed: qso.lotwConfirmed,
            qrzConfirmed: qso.qrzConfirmed,
            presence: qso.servicePresence.map {
                PresenceSummary(
                    serviceTypeRawValue: $0.serviceTypeRawValue,
                    isPresent: $0.isPresent,
                    isSubmitted: $0.isSubmitted,
                    needsUpload: $0.needsUpload
                )
            }
        )
    }
}
