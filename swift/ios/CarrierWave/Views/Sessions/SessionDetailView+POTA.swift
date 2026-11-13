// Session Detail View - POTA Sections
//
// POTA-specific sections for SessionDetailView: upload controls,
// jobs, and recording player. Hero section handles activation
// info, metadata, conditions, and shift windows.

import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Upload Visibility

extension SessionDetailView {
    var shouldShowUpload: Bool {
        shouldShowPOTAUpload || shouldShowQRZUpload
    }

    var shouldShowPOTAUpload: Bool {
        guard let activation else {
            return false
        }
        return activation.hasQSOsToUpload && !hasCompletedJob
    }

    var shouldShowQRZUpload: Bool {
        onQRZUpload != nil && qrzUploadCount > 0
    }

    var hasCompletedJob: Bool {
        matchingJobs.contains { $0.status == .completed }
    }
}

// MARK: - Upload Section

extension SessionDetailView {
    @ViewBuilder
    var inlineUploadRow: some View {
        if isUploading || isUploadingQRZ {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Uploading...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            HStack(spacing: 8) {
                if shouldShowPOTAUpload, let activation {
                    potaExportButton(count: activation.pendingCount)
                }
                if shouldShowQRZUpload, let onQRZUpload {
                    qrzDetailUploadButton(
                        count: qrzUploadCount, action: onQRZUpload
                    )
                }
            }
            .listRowInsets(
                EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            )
        }

        inlineUploadErrors
    }

    private func potaExportButton(count: Int) -> some View {
        Button {
            onExport?()
        } label: {
            Label(
                "Upload \(count) to POTA",
                systemImage: "arrow.up.forward.app.fill"
            )
        }
        .buttonStyle(.bordered)
    }

    private func qrzDetailUploadButton(
        count: Int, action: @escaping () async -> String?
    ) -> some View {
        Button {
            isUploadingQRZ = true
            Task {
                qrzUploadError = await action()
                isUploadingQRZ = false
            }
        } label: {
            Label(
                "Upload \(count) to QRZ",
                systemImage: "arrow.up.circle.fill"
            )
        }
        .buttonStyle(.bordered)
        .tint(.orange)
    }

    @ViewBuilder
    private var uploadCountMismatchCaption: some View {
        if shouldShowPOTAUpload, shouldShowQRZUpload, let activation {
            let potaCount = activation.pendingCount
            if potaCount != qrzUploadCount, potaCount > 0, qrzUploadCount > 0 {
                Text(
                    "Counts differ — some QSOs may have been logged before a service was configured."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .listRowInsets(
                    EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16)
                )
            }
        }
    }

    @ViewBuilder
    private var inlineUploadErrors: some View {
        if !uploadErrors.isEmpty {
            ForEach(
                uploadErrors.sorted(by: { $0.key < $1.key }),
                id: \.key
            ) { park, error in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(park)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(error).font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        if let qrzError = qrzUploadError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(qrzError).font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var potaJobsSection: some View {
        Section {
            ForEach(matchingJobs) { job in
                POTAJobRow(job: job, potaClient: potaClient)
            }
        } header: {
            Text("POTA Jobs")
        }
    }
}

// MARK: - Recording Section

extension SessionDetailView {
    func recordingSection(_ recording: WebSDRRecording) -> some View {
        Section {
            NavigationLink {
                RecordingPlayerView(
                    recording: recording,
                    initialQSOs: activation?.qsos ?? qsos,
                    engine: engine
                )
            } label: {
                CompactRecordingPlayer(
                    recording: recording,
                    qsos: activation?.qsos ?? qsos,
                    engine: engine
                )
            }
            .buttonStyle(.plain)
            .listRowInsets(
                EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            )
        }
    }

    func loadRecording() async {
        guard let activation else {
            return
        }
        let sessionIds = Array(
            Set(activation.qsos.compactMap(\.loggingSessionId))
        )
        guard !sessionIds.isEmpty else {
            return
        }

        let recordings = (try? WebSDRRecording.findRecordings(
            forSessionIds: sessionIds, in: modelContext
        )) ?? []

        let qsoTimestamps = activation.qsos.map(\.timestamp)
        guard let earliest = qsoTimestamps.min(),
              let latest = qsoTimestamps.max()
        else {
            return
        }

        recording = recordings.first { rec in
            let recEnd = rec.endedAt ?? rec.startedAt
            return rec.startedAt <= latest && recEnd >= earliest
        }
    }

    func loadActivationSession() {
        guard let activation else {
            return
        }
        guard let sessionId = activation.qsos
            .compactMap(\.loggingSessionId).first
        else {
            return
        }
        let predicate = #Predicate<LoggingSession> { $0.id == sessionId }
        var descriptor = FetchDescriptor<LoggingSession>(predicate: predicate)
        descriptor.fetchLimit = 1
        activationSession = try? modelContext.fetch(descriptor).first
    }
}

// MARK: - MetadataItem

struct MetadataItem {
    let icon: String
    let label: String
}
