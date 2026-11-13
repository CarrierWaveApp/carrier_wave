import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - Row Views

extension CallsignEnrichedTimeline {
    func enrichedRow(_ item: EnrichedTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let qso = item.qso {
                qsoHeader(qso, item: item)
                qsoDetail(qso)
                parkRow(qso)
            } else if let recording = item.recording {
                tuneInHeader(recording)
                recordingDetail(recording)
            }

            if let recording = item.recording {
                recordingSection(item, recording: recording)
            }

            if let clip = item.clip, item.recording == nil {
                QSORecordingClipView(clip: clip)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - QSO Headers

    private func qsoHeader(
        _ qso: QSO, item: EnrichedTimelineItem
    ) -> some View {
        HStack(spacing: 4) {
            Text(Self.dateFormatter.string(from: qso.timestamp))
                .font(.subheadline.weight(.medium))
            Text("\u{b7}")
                .foregroundStyle(.secondary)
            Text("\(Self.timeFormatter.string(from: qso.timestamp)) UTC")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Spacer()
            if item.isTuneIn {
                tuneInBadge
            }
        }
    }

    private func qsoDetail(_ qso: QSO) -> some View {
        HStack(spacing: 6) {
            bandModeBadge(qso.band)
            bandModeBadge(qso.mode)

            if let freq = qso.frequency {
                Text(FrequencyFormatter.formatWithUnit(freq))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let sent = qso.rstSent, let rcvd = qso.rstReceived {
                Text("\(sent)/\(rcvd)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func parkRow(_ qso: QSO) -> some View {
        if let park = qso.theirParkReference, !park.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "leaf")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(park)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Tune-In Headers

    private func tuneInHeader(_ recording: WebSDRRecording) -> some View {
        HStack(spacing: 4) {
            Text(Self.dateFormatter.string(from: recording.startedAt))
                .font(.subheadline.weight(.medium))
            Text("\u{b7}")
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
            Spacer()
            tuneInBadge
        }
    }

    private func recordingDetail(
        _ recording: WebSDRRecording
    ) -> some View {
        HStack(spacing: 4) {
            Text("KiwiSDR: \(recording.kiwisdrName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\u{b7}")
                .foregroundStyle(.secondary)
            Text(recording.formattedDuration)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Recording Section

    private func recordingSection(
        _ item: EnrichedTimelineItem,
        recording: WebSDRRecording
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { onPlay(recording, nil) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(recording.kiwisdrName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\u{b7}")
                        .foregroundStyle(.tertiary)
                    Text(recording.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            .buttonStyle(.plain)

            rangeChips(item, recording: recording)
        }
        .padding(8)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func rangeChips(
        _ item: EnrichedTimelineItem,
        recording: WebSDRRecording
    ) -> some View {
        if !item.callsignRanges.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(
                        Array(item.callsignRanges.enumerated()),
                        id: \.offset
                    ) { _, range in
                        Button {
                            onPlay(recording, range.startOffset)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text(
                                    "\(formatTime(range.startOffset)) \u{2013} \(formatTime(range.endOffset))"
                                )
                                .font(.caption2.monospaced())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Shared Helpers

    private var tuneInBadge: some View {
        Text("Tune In")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.green.opacity(0.2))
            .clipShape(Capsule())
    }

    private func bandModeBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.2))
            .clipShape(Capsule())
    }

    static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt
    }()

    static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
