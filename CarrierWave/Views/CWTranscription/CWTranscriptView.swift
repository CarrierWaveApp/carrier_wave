import CarrierWaveData
import SwiftUI

// MARK: - CWTranscriptView

/// Displays the decoded CW transcript with timestamps.
/// Auto-scrolls to show the latest decoded text.
struct CWTranscriptView: View {
    // MARK: Internal

    /// Completed transcript entries
    let entries: [CWTranscriptEntry]

    /// Current line being assembled
    let currentLine: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(entries) { entry in
                        transcriptRow(entry: entry)
                    }

                    // Current line being decoded
                    if !currentLine.isEmpty {
                        currentLineRow
                            .id("currentLine")
                    }

                    // Anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: entries.count) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: currentLine) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    /// Formatter for timestamps
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var currentLineRow: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp placeholder
            Text(timeFormatter.string(from: Date()))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            // Current text with cursor
            HStack(spacing: 0) {
                Text(currentLine)
                    .font(.body.monospaced())
                    .foregroundStyle(.primary)

                // Blinking cursor
                CursorView()
            }

            Spacer()
        }
    }

    private func transcriptRow(entry: CWTranscriptEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(timeFormatter.string(from: entry.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            // Decoded text with highlighting
            if !entry.elements.isEmpty {
                CWHighlightedText(elements: entry.elements)
                    .font(.body.monospaced())
            } else {
                Text(entry.text)
                    .font(.body.monospaced())
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
    }
}

// MARK: - CursorView

/// Blinking cursor indicator
private struct CursorView: View {
    // MARK: Internal

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2, height: 16)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                guard !reduceMotion else {
                    return
                }
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isVisible.toggle()
                }
            }
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = true
}

// MARK: - CWEmptyTranscriptView

/// Placeholder shown when transcript is empty
struct CWEmptyTranscriptView: View {
    let isListening: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isListening ? "waveform" : "mic.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(isListening ? "Listening for CW..." : "Tap Start to begin")
                .font(.headline)
                .foregroundStyle(.secondary)

            if isListening {
                Text("Play CW audio near your device")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    VStack {
        CWTranscriptView(
            entries: [
                CWTranscriptEntry(text: "CQ CQ CQ DE K4SWL K4SWL K"),
                CWTranscriptEntry(text: "K4SWL DE N9HO N9HO KN"),
                CWTranscriptEntry(text: "N9HO GM UR 599 599 NC NC BK"),
            ],
            currentLine: "R R K4SWL UR 5"
        )
        .frame(height: 200)
        .padding()

        CWEmptyTranscriptView(isListening: true)
            .frame(height: 200)
            .padding()
    }
}
