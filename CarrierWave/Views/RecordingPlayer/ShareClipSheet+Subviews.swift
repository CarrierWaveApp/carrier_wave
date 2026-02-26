import SwiftUI

// MARK: - Waveform & Handles

extension ShareClipSheet {
    /// Waveform with QSO markers, segment boundaries, and draggable range handles
    var waveformWithHandles: some View {
        RecordingWaveformView(
            amplitudes: engine.amplitudeEnvelope,
            duration: engine.duration,
            currentTime: isPreviewing ? engine.currentTime : rangeStart,
            qsoOffsets: qsoOffsets,
            activeQSOIndex: engine.activeQSOIndex,
            height: 80,
            seekable: false,
            qsoCallsigns: sortedQSOs.map(\.callsign),
            qsoRanges: engine.qsoRanges,
            segments: engine.segments
        )
        .overlay { rangeOverlay }
        .padding(.horizontal)
    }

    var rangeOverlay: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let startX = xPos(rangeStart, in: width)
            let endX = xPos(rangeEnd, in: width)

            // Dimmed regions outside selection
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(.label).opacity(0.25))
                    .frame(width: max(0, startX))
                Spacer()
                Rectangle()
                    .fill(Color(.label).opacity(0.25))
                    .frame(width: max(0, width - endX))
            }

            // Start handle
            rangeHandle(at: startX, height: height)
                .gesture(handleDrag(isStart: true, width: width))
                .accessibilityLabel("Clip start handle")

            // End handle
            rangeHandle(at: endX, height: height)
                .gesture(handleDrag(isStart: false, width: width))
                .accessibilityLabel("Clip end handle")
        }
    }

    // MARK: - Time Labels & Duration

    var timeLabels: some View {
        HStack {
            Text(formatTime(rangeStart))
            Spacer()
            Text(formatTime(rangeEnd))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal)
    }

    var durationLabel: some View {
        Text("Clip: \(formatTime(clipDuration))")
            .font(.subheadline)
    }

    // MARK: - Transcript Snippet

    var transcriptSnippet: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("CW Transcript", systemImage: "text.quote")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            let lines = transcriptLinesInRange()
            if lines.isEmpty {
                Text("No decoded text in selected range")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                Text(lines.joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Preview Controls

    var previewControls: some View {
        Button {
            togglePreview()
        } label: {
            Label(
                isPreviewing ? "Stop Preview" : "Preview Clip",
                systemImage: isPreviewing ? "stop.fill" : "play.fill"
            )
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Export Actions

    var exportActions: some View {
        VStack(spacing: 12) {
            // Audio export / share
            audioExportButton

            // Share card button
            Button {
                Task { await renderShareCard() }
            } label: {
                if isRenderingCard {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Create Share Card", systemImage: "photo.artframe")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRenderingCard || isExporting)
        }
    }
}

// MARK: - Private Helpers

extension ShareClipSheet {
    @ViewBuilder
    var audioExportButton: some View {
        if let url = exportedURL {
            let items = shareItems(audioURL: url)
            ShareLink(items: items) { item in
                SharePreview(item.caption)
            } label: {
                Label("Share Audio", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                Task { await exportClip() }
            } label: {
                if isExporting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Export Clip", systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting)
        }
    }

    func rangeHandle(at xPosition: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.accentColor)
            .frame(width: 6, height: height + 8)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.001))
                    .frame(width: 44, height: height + 8)
            }
            .position(x: xPosition, y: height / 2)
    }

    func handleDrag(isStart: Bool, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let fraction = max(0, min(1, value.location.x / width))
                let time = TimeInterval(fraction) * engine.duration
                if isStart {
                    rangeStart = min(time, rangeEnd - 1)
                } else {
                    rangeEnd = max(time, rangeStart + 1)
                }
            }
    }

    func setDefaultRange() {
        if let activeIdx = engine.activeQSOIndex {
            let sorted = sortedQSOs
            if activeIdx < sorted.count {
                let offset = sorted[activeIdx].timestamp
                    .timeIntervalSince(recording.startedAt)
                rangeStart = max(0, offset - 90)
                rangeEnd = min(engine.duration, offset + 15)
                return
            }
        }
        rangeStart = 0
        rangeEnd = min(60, engine.duration)
    }

    func togglePreview() {
        if isPreviewing {
            engine.pause()
            isPreviewing = false
        } else {
            engine.seek(to: rangeStart)
            engine.play()
            isPreviewing = true
            // Schedule stop at rangeEnd
            let end = rangeEnd
            Task {
                while engine.isPlaying, engine.currentTime < end {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if isPreviewing {
                    engine.pause()
                    isPreviewing = false
                }
            }
        }
    }

    func exportClip() async {
        guard let fileURL = recording.fileURL else {
            return
        }
        isExporting = true
        exportError = nil

        do {
            let url = try await RecordingClipExporter.exportClip(
                sourceURL: fileURL,
                startTime: rangeStart,
                endTime: rangeEnd,
                metadata: clipMetadata()
            )
            exportedURL = url
        } catch {
            exportError = error.localizedDescription
        }

        isExporting = false
    }

    func renderShareCard() async {
        isRenderingCard = true
        let snippetText = transcriptLinesInRange().joined(separator: "\n")
        let data = await RecordingShareCardRenderer.render(
            recording: recording,
            clipStart: rangeStart,
            clipEnd: rangeEnd,
            qsos: sortedQSOs,
            transcriptSnippet: snippetText.isEmpty ? nil : snippetText,
            amplitudes: engine.amplitudeEnvelope,
            duration: engine.duration
        )
        shareCardData = data
        isRenderingCard = false
    }

    func transcriptLinesInRange() -> [String] {
        guard let transcript = engine.transcript else {
            return []
        }
        return transcript.lines
            .filter { $0.startOffset < rangeEnd && $0.endOffset > rangeStart }
            .map { line in
                let prefix = line.speakerCallsign.map { "[\($0)] " } ?? ""
                let text = line.words.map(\.text).joined(separator: " ")
                return prefix + text
            }
    }

    func clipMetadata() -> RecordingClipMetadata {
        RecordingClipMetadata(
            receiverName: recording.kiwisdrName,
            frequencyKHz: recording.frequencyKHz,
            mode: recording.mode,
            recordingDate: recording.startedAt,
            callsigns: sortedQSOs.map(\.callsign)
        )
    }

    func shareItems(audioURL: URL) -> [ShareableClipItem] {
        var items: [ShareableClipItem] = [
            ShareableClipItem(url: audioURL, caption: shareCaption()),
        ]
        let transcript = transcriptLinesInRange().joined(separator: "\n")
        if !transcript.isEmpty {
            items.append(ShareableClipItem(
                url: audioURL,
                caption: "CW Transcript:\n\(transcript)"
            ))
        }
        return items
    }

    func shareCaption() -> String {
        let freq = formatFrequencyMHz(recording.frequencyKHz)
        let mode = recording.mode
        let rx = recording.kiwisdrName
        return "\(freq) \(mode) via \(rx)"
    }

    func xPos(_ time: TimeInterval, in width: CGFloat) -> CGFloat {
        guard engine.duration > 0 else {
            return 0
        }
        return CGFloat(time / engine.duration) * width
    }

    func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    func formatFrequencyMHz(_ kHz: Double) -> String {
        let mHz = kHz / 1_000
        if mHz == mHz.rounded() {
            return String(format: "%.0f MHz", mHz)
        }
        return String(format: "%.3f MHz", mHz)
    }
}

// MARK: - ShareableClipItem

/// Item for multi-item ShareLink with caption
struct ShareableClipItem: Identifiable {
    let id = UUID()
    let url: URL
    let caption: String
}
