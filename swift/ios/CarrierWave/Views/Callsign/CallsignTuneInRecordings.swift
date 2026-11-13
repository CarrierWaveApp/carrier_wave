import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - RecordingWithRanges

/// A recording paired with the detected QSO ranges for the target callsign.
struct RecordingWithRanges: Identifiable {
    let recording: WebSDRRecording
    /// Detected time ranges where the target callsign appears in the transcript.
    /// Empty for tune-in recordings (the whole recording is relevant).
    let callsignRanges: [DetectedQSORange]

    var id: UUID {
        recording.id
    }

    /// Whether this recording was a direct tune-in to the callsign
    var isTuneIn: Bool {
        recording.spotCallsign != nil
    }
}

// MARK: - CallsignTuneInRecordings

/// Section showing recordings containing this station — tune-in recordings
/// and own-session recordings with transcript-detected segments.
struct CallsignTuneInRecordings: View {
    // MARK: Internal

    let items: [RecordingWithRanges]
    /// Called when user taps a recording or range chip to play it.
    var onPlay: (WebSDRRecording, TimeInterval?) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recordings", systemImage: "waveform")
                    .font(.headline)
                Spacer()
            }

            ForEach(items) { item in
                recordingRow(item)

                if item.id != items.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt
    }()

    private func recordingRow(
        _ item: RecordingWithRanges
    ) -> some View {
        let recording = item.recording
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                onPlay(recording, nil)
            } label: {
                headerLine(recording)
            }
            .buttonStyle(.plain)

            detailLine(recording)
            parkLine(recording)
            segmentBar(item)
            rangeChips(item)
            segmentSummary(item)
        }
        .padding(.vertical, 4)
    }

    private func headerLine(
        _ recording: WebSDRRecording
    ) -> some View {
        HStack {
            Text(Self.dateFormatter.string(from: recording.startedAt))
                .font(.subheadline.weight(.medium))
            Text("·")
                .foregroundStyle(.secondary)
            Text(FrequencyFormatter.formatWithUnit(
                recording.frequencyKHz / 1_000.0
            ))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            Text(recording.mode.uppercased())
                .font(.caption.weight(.medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())
            if item(recording).isTuneIn {
                Text("Tune In")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
        }
    }

    private func detailLine(
        _ recording: WebSDRRecording
    ) -> some View {
        HStack(spacing: 4) {
            Text("KiwiSDR: \(recording.kiwisdrName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.secondary)
            Text(recording.formattedDuration)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func parkLine(
        _ recording: WebSDRRecording
    ) -> some View {
        if let parkRef = recording.spotParkRef {
            HStack(spacing: 4) {
                Image(systemName: "leaf")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(parkRef)
                    .font(.caption)
                    .foregroundStyle(.green)
                if let parkName = recording.spotParkName {
                    Text(parkName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Segment bar with callsign ranges highlighted in orange overlay.
    private func segmentBar(
        _ item: RecordingWithRanges
    ) -> some View {
        let segments = item.recording.segments
        let totalDuration = item.recording.durationSeconds
        let ranges = item.callsignRanges

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                baseSegmentBar(
                    segments: segments,
                    totalDuration: totalDuration,
                    width: geo.size.width
                )
                rangeHighlights(
                    ranges: ranges,
                    totalDuration: totalDuration,
                    width: geo.size.width
                )
            }
        }
        .frame(height: 12)
    }

    /// Show time range chips for each detected callsign range.
    @ViewBuilder
    private func rangeChips(
        _ item: RecordingWithRanges
    ) -> some View {
        if !item.callsignRanges.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(
                        Array(item.callsignRanges.enumerated()),
                        id: \.offset
                    ) { _, range in
                        Button {
                            onPlay(
                                item.recording, range.startOffset
                            )
                        } label: {
                            rangeChipLabel(range)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func rangeChipLabel(
        _ range: DetectedQSORange
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text(
                "\(formatTime(range.startOffset)) – \(formatTime(range.endOffset))"
            )
            .font(.caption2.monospaced())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func segmentSummary(
        _ item: RecordingWithRanges
    ) -> some View {
        let recording = item.recording
        let activeSegments = recording.segments.filter { !$0.isSilence }
        let transcript = SDRRecordingTranscript.load(
            sessionId: recording.loggingSessionId
        )
        let detectedCount = transcript?.detectedQSORanges.count ?? 0

        return HStack(spacing: 4) {
            Text(
                "\(activeSegments.count) segment\(activeSegments.count == 1 ? "" : "s")"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            if detectedCount > 0 {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(
                    "\(detectedCount) QSO\(detectedCount == 1 ? "" : "s") detected"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func item(
        _ recording: WebSDRRecording
    ) -> RecordingWithRanges {
        items.first { $0.recording.id == recording.id }
            ?? RecordingWithRanges(
                recording: recording, callsignRanges: []
            )
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Segment Bar Components

private extension CallsignTuneInRecordings {
    func baseSegmentBar(
        segments: [SDRRecordingSegment],
        totalDuration: Double,
        width: CGFloat
    ) -> some View {
        HStack(spacing: 1) {
            ForEach(
                Array(segments.enumerated()), id: \.offset
            ) { _, segment in
                let segEnd = segment.endOffset ?? totalDuration
                let segDuration = segEnd - segment.startOffset
                let fraction = segDuration / max(totalDuration, 1)
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        segment.isSilence
                            ? Color(.systemGray4)
                            : Color.blue.opacity(0.3)
                    )
                    .frame(width: max(width * fraction, 2))
            }
        }
    }

    func rangeHighlights(
        ranges: [DetectedQSORange],
        totalDuration: Double,
        width: CGFloat
    ) -> some View {
        ForEach(
            Array(ranges.enumerated()), id: \.offset
        ) { _, range in
            let startFrac = range.startOffset / max(totalDuration, 1)
            let endFrac = range.endOffset / max(totalDuration, 1)
            let barWidth = (endFrac - startFrac) * width
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange.opacity(0.7))
                .frame(width: max(barWidth, 4))
                .offset(x: startFrac * width)
        }
    }
}
