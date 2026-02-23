import os
import SwiftData
import SwiftUI

// MARK: - Data Loading, QSO Rows, Transcription

extension RecordingPlayerView {
    // MARK: - QSO Summary

    var qsoSummarySection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isQSOListExpanded.toggle()
                }
            } label: {
                qsoSummaryHeader
            }
            .buttonStyle(.plain)

            if isQSOListExpanded {
                qsoExpandedList
                    .frame(maxHeight: 200)
            }
        }
    }

    var qsoSummaryHeader: some View {
        HStack {
            Text("QSOs (\(sortedQSOs.count))")
                .font(.subheadline.weight(.medium))

            if !isQSOListExpanded, let idx = engine.activeQSOIndex,
               idx < sortedQSOs.count
            {
                Text(sortedQSOs[idx].callsign)
                    .font(.subheadline.monospaced().weight(.semibold))
                    .foregroundStyle(.tint)
            }

            Spacer()

            Image(systemName: isQSOListExpanded
                ? "chevron.down" : "chevron.up")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    var qsoExpandedList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(
                    Array(sortedQSOs.enumerated()), id: \.element.id
                ) { index, qso in
                    qsoRow(qso, index: index)
                        .id(qso.id)
                        .onTapGesture {
                            engine.seekToQSO(at: index)
                        }
                }
            }
            .listStyle(.plain)
            .onChange(of: engine.activeQSOIndex) { _, newIndex in
                if let idx = newIndex, idx < sortedQSOs.count {
                    withAnimation {
                        proxy.scrollTo(sortedQSOs[idx].id, anchor: .center)
                    }
                }
            }
        }
    }

    func qsoRow(_ qso: QSO, index: Int) -> some View {
        let isActive = index == engine.activeQSOIndex

        return HStack(spacing: 8) {
            if isActive {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
            } else {
                Text(formatQSOTime(qso.timestamp))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(qso.callsign)
                .font(.subheadline)
                .fontWeight(isActive ? .bold : .regular)

            Spacer()

            if let rst = qso.rstSent {
                Text(rst)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(qso.band)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(qso.mode)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .listRowBackground(
            isActive ? Color.accentColor.opacity(0.1) : nil
        )
    }

    // MARK: - Transcription

    func transcriptionErrorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                transcriptionError = nil
                Task { await startTranscription() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func startTranscription() async {
        guard let fileURL = recording.fileURL else {
            Logger(subsystem: "com.jsvana.FullDuplex", category: "CW-SWL").info("[CW-SWL] No file URL for recording")
            return
        }
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        let size = (try? FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )[.size] as? Int64) ?? 0
        Logger(subsystem: "com.jsvana.FullDuplex", category: "CW-SWL")
            .info("[CW-SWL] Starting transcription: \(fileURL.lastPathComponent), exists=\(exists), size=\(size)")

        isTranscribing = true
        transcriptionProgress = 0
        transcriptionError = nil

        let client = CWSWLClient()
        do {
            let transcript = try await client.transcribe(
                fileURL: fileURL
            ) { progress in
                Task { @MainActor in
                    transcriptionProgress = progress
                }
            }
            do {
                try transcript.save(sessionId: recording.loggingSessionId)
            } catch {
                Logger(subsystem: "com.jsvana.FullDuplex", category: "CW-SWL")
                    .error("[CW-SWL] Failed to save transcript: \(error)")
            }
            engine.setTranscript(transcript)
        } catch {
            Logger(subsystem: "com.jsvana.FullDuplex", category: "CW-SWL")
                .info("[CW-SWL] Transcription error: \(error)")
            transcriptionError = error.localizedDescription
        }
        isTranscribing = false
    }

    // MARK: - Data Loading

    func loadQSOs() async {
        guard initialQSOs.isEmpty else {
            return
        }
        let sessionId = recording.loggingSessionId
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate {
                $0.loggingSessionId == sessionId && !$0.isHidden
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchLimit = 500
        loadedQSOs = (try? modelContext.fetch(descriptor)) ?? []
    }

    func loadIfNeeded() async {
        guard !engine.isLoaded, let fileURL = recording.fileURL else {
            return
        }
        let timestamps = sortedQSOs.map(\.timestamp)
        try? engine.load(
            fileURL: fileURL,
            qsoTimestamps: timestamps,
            recordingStart: recording.startedAt,
            segments: recording.segments
        )
        engine.loadTranscript(sessionId: recording.loggingSessionId)
    }

    // MARK: - Formatting

    func formatUTCTime(_ offset: TimeInterval) -> String {
        let date = recording.startedAt.addingTimeInterval(offset)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date) + "z"
    }

    func formatQSOTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date) + "z"
    }

    func formatOffset(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    func formatFrequency(_ kHz: Double) -> String {
        let mHz = kHz / 1_000
        if mHz == mHz.rounded() {
            return String(format: "%.0f MHz", mHz)
        }
        return String(format: "%.3f MHz", mHz)
    }
}
