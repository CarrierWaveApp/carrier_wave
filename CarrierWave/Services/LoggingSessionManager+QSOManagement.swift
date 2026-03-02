import Foundation
import SwiftData
import UIKit

// MARK: - QSO Management

extension LoggingSessionManager {
    /// Log a new QSO
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
        aoaCode: String? = nil
    ) -> QSO? {
        guard let session = activeSession else {
            return nil
        }

        // Derive band from frequency
        let band: String =
            if let freq = session.frequency {
                LoggingSession.bandForFrequency(freq)
            } else {
                "Unknown"
            }

        let qso = QSO(
            callsign: callsign.trimmingCharacters(in: .whitespaces).uppercased(),
            band: band,
            mode: session.mode,
            frequency: session.frequency,
            timestamp: Date(),
            rstSent: rstSent,
            rstReceived: rstReceived,
            myCallsign: session.myCallsign,
            myGrid: session.myGrid,
            theirGrid: theirGrid,
            parkReference: session.parkReference,
            theirParkReference: theirParkReference,
            notes: combineNotes(notes: notes, operatorName: operatorName),
            importSource: .logger,
            name: name,
            qth: qth,
            state: state,
            country: country,
            power: session.power,
            myRig: session.myRig,
            sotaRef: session.isSOTA ? session.sotaReference : nil,
            wwffRef: session.isWWFF ? session.wwffReference : nil,
            theirLicenseClass: theirLicenseClass
        )

        // Set the logging session ID
        qso.loggingSessionId = session.id
        qso.aoaCode = aoaCode
        qso.cloudDirtyFlag = true
        qso.modifiedAt = Date()

        modelContext.insert(qso)
        session.incrementQSOCount()

        // Increment per-stop QSO count for rove sessions
        incrementCurrentRoveStopQSOCount()

        // Mark for upload to configured services
        markForUpload(qso)

        try? modelContext.save()

        writeSessionToWidget(session, lastCallsign: qso.callsign)
        updateLiveActivity(lastCallsign: qso.callsign)

        // Detect and report social activities async (non-blocking)
        Task { [weak self] in
            await self?.processActivityForQSO(qso)
        }

        return qso
    }

    /// Hide a QSO (soft delete)
    func hideQSO(_ qso: QSO) {
        qso.isHidden = true
        // Clear upload flags so hidden QSOs are never synced
        for presence in qso.servicePresence where presence.needsUpload {
            presence.needsUpload = false
        }

        // Decrement session QSO count and update Live Activity
        if let session = activeSession, qso.loggingSessionId == session.id {
            session.decrementQSOCount()
            decrementRoveStopQSOCount(for: qso)
            updateLiveActivity()
            writeSessionToWidget(session)
        }

        try? modelContext.save()
    }

    /// Unhide a previously hidden QSO
    func unhideQSO(_ qso: QSO) {
        qso.isHidden = false
        try? modelContext.save()
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

        let descriptor = FetchDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
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
