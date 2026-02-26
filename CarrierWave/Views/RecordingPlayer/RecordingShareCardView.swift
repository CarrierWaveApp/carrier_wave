import SwiftUI

// MARK: - RecordingShareCardData

/// Data needed to display the recording share card preview
struct RecordingShareCardData: Identifiable {
    let id = UUID()
    let image: UIImage
    let recording: WebSDRRecording
    let clipStart: TimeInterval
    let clipEnd: TimeInterval
    let qsoCount: Int
}

// MARK: - RecordingShareCardView

/// Branded card for sharing SDR recording clips on social media.
/// Shows a mini waveform, receiver info, frequency/mode, QSO callsigns,
/// and optional CW transcript excerpt.
struct RecordingShareCardView: View {
    // MARK: Internal

    let recording: WebSDRRecording
    let clipStart: TimeInterval
    let clipEnd: TimeInterval
    let qsos: [QSO]
    let transcriptSnippet: String?
    let amplitudes: [Float]
    let duration: TimeInterval

    var body: some View {
        VStack(spacing: 0) {
            header
            waveformStrip
            metadataSection
            if let snippet = transcriptSnippet, !snippet.isEmpty {
                transcriptSection(snippet)
            }
            qsoSection
            footer
        }
        .frame(width: 400, height: cardHeight)
        .background(cardBackground)
        .clipShape(Rectangle())
    }

    // MARK: Private

    private var cardHeight: CGFloat {
        let base: CGFloat = 340
        let transcriptHeight: CGFloat = transcriptSnippet != nil ? 80 : 0
        let qsoHeight: CGFloat = min(CGFloat(qsos.count), 4) * 22
        return base + transcriptHeight + qsoHeight
    }

    private var cardBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.10, blue: 0.16),
                Color(red: 0.12, green: 0.08, blue: 0.18),
                Color(red: 0.08, green: 0.10, blue: 0.16),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Card Sections

extension RecordingShareCardView {
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.title3)
                .foregroundStyle(.red)
            Text("SDR Recording")
                .font(.headline)
                .foregroundStyle(Color(.systemBackground))
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(Color(.systemBackground).opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var waveformStrip: some View {
        GeometryReader { geo in
            let width = geo.size.width - 32
            let clipStartFrac = duration > 0 ? clipStart / duration : 0
            let clipEndFrac = duration > 0 ? clipEnd / duration : 1
            let startIdx = Int(clipStartFrac * Double(amplitudes.count))
            let endIdx = min(Int(clipEndFrac * Double(amplitudes.count)), amplitudes.count)
            let clipAmps = Array(amplitudes[safe: startIdx ..< endIdx])

            HStack(alignment: .center, spacing: 1) {
                ForEach(Array(clipAmps.enumerated()), id: \.offset) { _, amp in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(height: max(2, 40 * CGFloat(amp)))
                }
            }
            .frame(width: width, height: 40)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 40)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var metadataSection: some View {
        VStack(spacing: 6) {
            // Frequency + mode row
            HStack(spacing: 12) {
                Text(formatFrequency(recording.frequencyKHz))
                    .font(.title2.monospaced().weight(.bold))
                    .foregroundStyle(Color(.systemBackground))

                Text(recording.mode)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.3))
                    .clipShape(Capsule())
                    .foregroundStyle(Color(.systemBackground))

                Spacer()

                Text(formatClipDuration())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color(.systemBackground).opacity(0.6))
            }

            // Receiver + date row
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.caption2)
                    .foregroundStyle(Color(.systemBackground).opacity(0.5))
                    .accessibilityHidden(true)
                Text(recording.kiwisdrName)
                    .font(.caption)
                    .foregroundStyle(Color(.systemBackground).opacity(0.7))
                Spacer()
                Text(formatDate())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color(.systemBackground).opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func transcriptSection(_ snippet: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CW DECODE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(.systemBackground).opacity(0.4))
            Text(snippet)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(.systemBackground).opacity(0.8))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var qsoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !qsos.isEmpty {
                Text("\(qsos.count) QSO\(qsos.count == 1 ? "" : "s") in clip")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground).opacity(0.4))
                    .padding(.horizontal, 16)

                let displayed = Array(qsos.prefix(4))
                ForEach(displayed, id: \.id) { qso in
                    HStack(spacing: 8) {
                        Text(qso.callsign)
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(Color(.systemBackground))
                        if let rst = qso.rstSent {
                            Text(rst)
                                .font(.caption2.monospaced())
                                .foregroundStyle(Color(.systemBackground).opacity(0.5))
                        }
                        Text(qso.band)
                            .font(.caption2)
                            .foregroundStyle(Color(.systemBackground).opacity(0.5))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
                if qsos.count > 4 {
                    Text("+\(qsos.count - 4) more")
                        .font(.caption2)
                        .foregroundStyle(Color(.systemBackground).opacity(0.3))
                        .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var footer: some View {
        HStack {
            Text("Carrier Wave")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color(.systemBackground).opacity(0.3))
            Spacer()
            Text("carrierwave.app")
                .font(.caption2)
                .foregroundStyle(Color(.systemBackground).opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Formatting

    private func formatFrequency(_ kHz: Double) -> String {
        let mHz = kHz / 1_000
        if mHz == mHz.rounded() {
            return String(format: "%.0f MHz", mHz)
        }
        return String(format: "%.3f MHz", mHz)
    }

    private func formatClipDuration() -> String {
        let total = Int(clipEnd - clipStart)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private func formatDate() -> String {
        Self.dateFormatter.string(from: recording.startedAt) + "z"
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe range: Range<Int>) -> ArraySlice<Element> {
        let lower = Swift.max(range.lowerBound, startIndex)
        let upper = Swift.min(range.upperBound, endIndex)
        guard lower < upper else {
            return []
        }
        return self[lower ..< upper]
    }
}
