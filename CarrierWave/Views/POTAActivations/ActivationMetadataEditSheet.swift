// Activation Metadata Edit Sheet
//
// Thin wrapper around SessionMetadataEditSheet for POTA activation editing.
// Finds the matching LoggingSession and delegates to the unified edit sheet.

import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - ActivationMetadataEditResult

/// Result of editing activation metadata (bridges to SessionMetadataEditResult)
struct ActivationMetadataEditResult {
    // MARK: Lifecycle

    /// Create from a SessionMetadataEditResult
    init(from result: SessionMetadataEditResult) {
        title = result.title
        watts = result.watts
        radio = result.radio
        antenna = result.antenna
        key = result.key
        mic = result.mic
        extraEquipment = result.extraEquipment
        attendees = result.attendees
        notes = result.notes
        newParkReference = result.newParkReference
        addedPhotos = result.addedPhotos
        deletedPhotoFilenames = result.deletedPhotoFilenames
    }

    // MARK: Internal

    let title: String?
    let watts: Int?
    let radio: String?
    let antenna: String?
    let key: String?
    let mic: String?
    let extraEquipment: String?
    let attendees: String?
    let notes: String?
    /// New park reference, if changed (nil means no change)
    let newParkReference: String?
    let addedPhotos: [UIImage]
    let deletedPhotoFilenames: [String]
}

// MARK: - ActivationMetadataEditSheet

struct ActivationMetadataEditSheet: View {
    // MARK: Lifecycle

    init(
        activation: POTAActivation,
        metadata: ActivationMetadata?,
        userGrid: String?,
        onSave: @escaping (ActivationMetadataEditResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.activation = activation
        self.metadata = metadata
        self.userGrid = userGrid
        self.onSave = onSave
        self.onCancel = onCancel
    }

    // MARK: Internal

    var body: some View {
        Group {
            if let session {
                SessionMetadataEditSheet(
                    session: session,
                    metadata: metadata,
                    userGrid: userGrid,
                    onSave: { result in
                        onSave(ActivationMetadataEditResult(from: result))
                    },
                    onCancel: onCancel
                )
            } else {
                ProgressView("Loading session...")
            }
        }
        .task {
            await findSession()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var session: LoggingSession?

    private let activation: POTAActivation
    private let metadata: ActivationMetadata?
    private let userGrid: String?
    private let onSave: (ActivationMetadataEditResult) -> Void
    private let onCancel: () -> Void

    private func findSession() async {
        // Try to find session via QSO's loggingSessionId
        if let sessionId = activation.qsos.compactMap(\.loggingSessionId).first {
            let predicate = #Predicate<LoggingSession> { $0.id == sessionId }
            var descriptor = FetchDescriptor<LoggingSession>(predicate: predicate)
            descriptor.fetchLimit = 1
            if let found = try? modelContext.fetch(descriptor).first {
                session = found
                return
            }
        }

        // Fallback: create a temporary session from activation data
        let tempSession = LoggingSession(
            myCallsign: activation.callsign,
            startedAt: activation.qsos.map(\.timestamp).min() ?? Date(),
            mode: activation.qsos.first?.mode ?? "CW",
            activationType: .pota,
            parkReference: activation.parkReference,
            myGrid: activation.qsos.first?.myGrid,
            power: metadata?.watts,
            myRig: activation.qsos.compactMap(\.myRig).first
        )
        tempSession.endedAt = activation.qsos.map(\.timestamp).max()
        tempSession.customTitle = metadata?.title
        tempSession.qsoCount = activation.qsoCount
        session = tempSession
    }
}
