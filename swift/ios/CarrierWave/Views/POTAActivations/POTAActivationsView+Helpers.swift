import CarrierWaveData
import SwiftData
import SwiftUI

extension POTAActivationsContentView {
    func applySessionEdits(
        _ result: ActivationMetadataEditResult, to session: LoggingSession
    ) {
        if let newCallsign = result.newCallsign {
            session.myCallsign = newCallsign
            let sessionId = session.id
            var desc = FetchDescriptor<QSO>(
                predicate: #Predicate { $0.loggingSessionId == sessionId }
            )
            desc.fetchLimit = 1_000
            if let qsos = try? modelContext.fetch(desc) {
                for qso in qsos {
                    qso.myCallsign = newCallsign
                }
            }
        }
        session.myRig = result.radio
        session.myAntenna = result.antenna
        session.myKey = result.key
        session.myMic = result.mic
        session.extraEquipment = result.extraEquipment
        session.attendees = result.attendees
        session.notes = result.notes

        for photo in result.addedPhotos {
            if let filename = try? SessionPhotoManager.savePhoto(
                photo, sessionID: session.id
            ) {
                session.photoFilenames.append(filename)
            }
        }
        for filename in result.deletedPhotoFilenames {
            try? SessionPhotoManager.deletePhoto(
                filename: filename, sessionID: session.id
            )
            session.photoFilenames.removeAll { $0 == filename }
        }
    }

    /// Find the LoggingSession matching an activation via QSO loggingSessionId
    func findSession(for activation: POTAActivation) -> LoggingSession? {
        guard let sessionId = activation.qsos.compactMap(\.loggingSessionId).first else {
            return nil
        }
        let predicate = #Predicate<LoggingSession> { $0.id == sessionId }
        var descriptor = FetchDescriptor<LoggingSession>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Activation Metadata

extension POTAActivationsContentView {
    /// Load activation metadata into a lookup dictionary keyed by
    /// "parkReference|yyyy-MM-dd".
    ///
    /// This view lists every park activation, so it needs metadata for the
    /// whole set; page it in bounded batches (same pattern as the QSO load in
    /// `loadActivations`) instead of one unbounded fetch.
    func loadMetadata() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        let batchSize = BoundedDescriptor<ActivationMetadata>.maxLimit
        var offset = 0
        var dict: [String: ActivationMetadata] = [:]

        while true {
            let descriptor = BoundedDescriptor<ActivationMetadata>(
                sortBy: [
                    SortDescriptor(\.date, order: .reverse),
                    SortDescriptor(\.parkReference),
                ],
                limit: batchSize,
                offset: offset
            )
            guard let batch = try? modelContext.boundedFetch(descriptor), !batch.isEmpty else {
                break
            }

            for item in batch {
                let dateStr = formatter.string(from: item.date)
                dict["\(item.parkReference)|\(dateStr)"] = item
            }

            if batch.count < batchSize {
                break
            }
            offset += batch.count
            await Task.yield()
        }

        metadataByKey = dict
    }
}
