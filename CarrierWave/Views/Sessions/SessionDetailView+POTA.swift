// Session Detail View - POTA Sections
//
// POTA-specific sections for SessionDetailView: activation info,
// metadata grid, conditions, upload controls, jobs, and recording.

import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - POTA Info Section

extension SessionDetailView {
    var potaInfoSection: some View {
        Section {
            if let parkName {
                Text(parkName)
                    .font(.headline)
            }

            if let activation {
                HStack {
                    Text(activation.displayDate)
                        .font(.subheadline)
                    Spacer()
                    Text(activation.callsign)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                statStrip(
                    qsoCount: activation.qsoCount,
                    duration: activation.formattedDuration,
                    rate: activationRate
                )

                activationMetadataGrid

                QSOTimelineView(qsos: activation.qsos)

                if hasConditions {
                    conditionsRow
                }
            }

            if shouldShowUpload {
                inlineUploadRow
            }
        }
    }

    private var activationRate: String? {
        guard let activation, activation.duration > 0 else {
            return nil
        }
        let hours = activation.duration / 3_600
        guard hours > 0 else {
            return nil
        }
        let rate = Double(activation.qsoCount) / hours
        return String(format: "%.1f", rate)
    }

    var shouldShowUpload: Bool {
        guard let activation, onUpload != nil else {
            return false
        }
        return activation.hasQSOsToUpload && isAuthenticated && !hasCompletedJob
    }

    var hasCompletedJob: Bool {
        matchingJobs.contains { $0.status == .completed }
    }

    // MARK: - Metadata Grid

    private var activationMetadataGrid: some View {
        let items = buildMetadataItems()
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
            ],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(items, id: \.label) { item in
                Label(item.label, systemImage: item.icon)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var hasConditions: Bool {
        activationMetadata?.hasSolarData == true
            || activationMetadata?.hasWeatherData == true
            || (activationMetadata?.weather != nil
                && !(activationMetadata?.weather?.isEmpty ?? true))
            || (activationMetadata?.solarConditions != nil
                && !(activationMetadata?.solarConditions?.isEmpty ?? true))
    }

    private var conditionsRow: some View {
        HStack {
            if let meta = activationMetadata {
                ConditionsGaugeRow(
                    metadata: meta, showingSheet: $showingConditions
                )
            }
        }
        .sheet(isPresented: $showingConditions) {
            if let meta = activationMetadata {
                ActivationConditionsSheet(metadata: meta)
            }
        }
    }

    private var activationRadio: String? {
        activation?.qsos.compactMap(\.myRig).first
    }

    private func buildMetadataItems() -> [MetadataItem] {
        guard let activation else {
            return []
        }
        var items: [MetadataItem] = []

        if !activation.uniqueBands.isEmpty {
            items.append(MetadataItem(
                icon: "dial.medium.fill",
                label: activation.uniqueBands.sorted().joined(separator: ", ")
            ))
        }
        if !activation.uniqueModes.isEmpty {
            items.append(MetadataItem(icon: "waveform", label: activation.uniqueModes.joined(separator: ", ")))
        }
        items.append(contentsOf: buildEquipmentMetadataItems())
        return items
    }

    private func buildEquipmentMetadataItems() -> [MetadataItem] {
        var items: [MetadataItem] = []
        if let watts = activationMetadata?.watts {
            items.append(MetadataItem(icon: "bolt.fill", label: "\(watts)W"))
        }
        if let wpm = activationMetadata?.averageWPM {
            items.append(MetadataItem(icon: "metronome", label: "\(wpm) WPM"))
        }
        if let radio = activationRadio {
            items.append(MetadataItem(icon: "radio", label: radio))
        }
        if let antenna = activationSession?.myAntenna {
            items.append(MetadataItem(icon: "antenna.radiowaves.left.and.right", label: antenna))
        }
        if let key = activationSession?.myKey {
            items.append(MetadataItem(icon: "pianokeys", label: key))
        }
        if let mic = activationSession?.myMic {
            items.append(MetadataItem(icon: "mic", label: mic))
        }
        return items
    }
}

// MARK: - Upload Section

extension SessionDetailView {
    @ViewBuilder
    private var inlineUploadRow: some View {
        if isUploading {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Uploading...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else if let activation, let onUpload {
            Button {
                isUploading = true
                Task {
                    let errors = await onUpload()
                    uploadErrors = errors
                    isUploading = false
                }
            } label: {
                Label(
                    "Upload \(activation.pendingCount) QSO\(activation.pendingCount == 1 ? "" : "s") to POTA",
                    systemImage: "arrow.up.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInMaintenance)
            .listRowInsets(
                EdgeInsets(
                    top: 8, leading: 16, bottom: 8, trailing: 16
                )
            )
        }

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
        // Use session IDs from the activation's actual QSOs
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
