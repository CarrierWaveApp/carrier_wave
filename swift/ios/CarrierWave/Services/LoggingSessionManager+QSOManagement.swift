import CarrierWaveData
import Foundation
import SwiftData
import UIKit

// MARK: - QSO Management

extension LoggingSessionManager {
    /// Log a new QSO. All-in on Rust: assembly (band-from-frequency, session-field
    /// stamping, RST defaults, notes merge, contest fields) + persistence run in the
    /// shared `SessionApi` (see `+RustDelegation`), then the row is reflected into
    /// SwiftData and the side effects fire. There is no Swift QSO-build fallback: if
    /// the cw-store seam is unavailable (the `.off` kill switch / experiment off) or
    /// the Rust write fails, the QSO is not persisted and the caller is told, rather
    /// than silently building a divergent SwiftData-only record.
    func logQSO(
        callsign: String,
        rstSent: String = "599",
        rstReceived: String = "599",
        theirGrid: String? = nil,
        theirParkReference: String? = nil,
        notes: String? = nil,
        name: String? = nil,
        operatorName: String? = nil,
        state: String? = nil,
        country: String? = nil,
        qth: String? = nil,
        theirLicenseClass: String? = nil,
        aoaCode: String? = nil,
        callsignChangeNote: String? = nil,
        contestExchangeSent: String? = nil,
        contestExchangeReceived: String? = nil,
        contestSerialSent: Int? = nil,
        contestSerialReceived: Int? = nil,
        frequencyOverride: Double? = nil,
        modeOverride: String? = nil,
        timestampOverride: Date? = nil
    ) -> LoggedQSO? {
        guard activeSession != nil else {
            return nil
        }

        guard let logged = logQSOViaRustIfEnabled(
            callsign: callsign, rstSent: rstSent, rstReceived: rstReceived,
            theirGrid: theirGrid, theirParkReference: theirParkReference, notes: notes,
            name: name, qth: qth, state: state, country: country,
            theirLicenseClass: theirLicenseClass, aoaCode: aoaCode,
            callsignChangeNote: callsignChangeNote,
            contestExchangeSent: contestExchangeSent,
            contestExchangeReceived: contestExchangeReceived,
            contestSerialSent: contestSerialSent,
            contestSerialReceived: contestSerialReceived,
            frequencyOverride: frequencyOverride,
            modeOverride: modeOverride, timestampOverride: timestampOverride
        ) else {
            CwStoreWriteLog.shared.record("logQSO: Rust session path unavailable — QSO not logged")
            ToastManager.shared.error("Couldn't log QSO — the log store is unavailable")
            return nil
        }
        return logged
    }

    /// Hide a QSO (soft delete). Routes the data write through `QSOWriteSink` when a
    /// cw-store seam is active (`on`/`shadow`); otherwise the legacy SwiftData path.
    /// Session counter mutations are applied in memory first and ride the seam's
    /// `save()` (so a failed write is reverted by `rollback()`); the Live Activity /
    /// widget pushes happen only after the write commits, so a failed hide never
    /// leaves those external surfaces showing a decremented count.
    func hideQSO(_ qso: QSO) {
        let activeMatch = activeSession.flatMap { qso.loggingSessionId == $0.id ? $0 : nil }
        if let session = activeMatch {
            session.decrementQSOCount()
            decrementRoveStopQSOCount(for: qso)
        }

        do {
            if let sink = QSOWriteSinkRegistry.current {
                try sink.setHidden(qso, hidden: true, in: modelContext)
            } else {
                qso.isHidden = true
                for presence in qso.servicePresence where presence.needsUpload {
                    presence.needsUpload = false
                }
                try modelContext.save()
            }
            if let session = activeMatch {
                updateLiveActivity()
                writeSessionToWidget(session)
            }
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Hide failed: \(error.localizedDescription)")
        }
    }

    /// Unhide a previously hidden QSO. Same routing as `hideQSO`.
    func unhideQSO(_ qso: QSO) {
        do {
            if let sink = QSOWriteSinkRegistry.current {
                try sink.setHidden(qso, hidden: false, in: modelContext)
            } else {
                qso.isHidden = false
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Unhide failed: \(error.localizedDescription)")
        }
    }

    /// Get QSOs for the current session
    func getSessionQSOs() -> [QSO] {
        guard let session = activeSession else {
            return []
        }

        let sessionId = session.id
        let predicate = #Predicate<QSO> { qso in
            qso.loggingSessionId == sessionId && !qso.isHidden
        }

        let descriptor = BoundedDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
            limit: BoundedDescriptor<QSO>.maxLimit
        )

        do {
            return try modelContext.boundedFetch(descriptor)
        } catch {
            return []
        }
    }

    // MARK: - Photo Management

    /// Add a photo to the current session, returning the filename
    func addPhoto(_ image: UIImage) throws -> String {
        guard let session = activeSession else {
            throw SessionPhotoManager.PhotoError.compressionFailed
        }

        let filename = try SessionPhotoManager.savePhoto(image, sessionID: session.id)
        session.photoFilenames.append(filename)
        try? modelContext.save()
        return filename
    }

    /// Delete a photo from the current session
    func deletePhoto(filename: String) throws {
        guard let session = activeSession else {
            return
        }

        try SessionPhotoManager.deletePhoto(filename: filename, sessionID: session.id)
        session.photoFilenames.removeAll { $0 == filename }
        try? modelContext.save()
    }
}
