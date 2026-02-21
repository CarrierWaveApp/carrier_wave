import SwiftUI

// MARK: - RecordingTranscriptView

/// Karaoke-style scrolling CW transcript, time-aligned to recording playback.
/// Words highlight as playback passes them, and the active line stays centered.
struct RecordingTranscriptView: View {
    // MARK: Internal

    let transcript: SDRRecordingTranscript?
    let segments: [SDRRecordingSegment]
    let activeLineIndex: Int?
    let activeWordIndex: Int?
    let currentTime: TimeInterval
    var onSeek: ((TimeInterval) -> Void)?
    var onTranscribe: (() -> Void)?

    var body: some View {
        if let transcript, !transcript.lines.isEmpty {
            transcriptContent(transcript)
        } else {
            emptyState
        }
    }

    // MARK: Private

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text("No transcript available")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let onTranscribe {
                Button {
                    onTranscribe()
                } label: {
                    Label("Transcribe", systemImage: "text.magnifyingglass")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transcriptContent(
        _ transcript: SDRRecordingTranscript
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(
                        Array(interleaveItems(transcript).enumerated()),
                        id: \.element.id
                    ) { _, item in
                        switch item {
                        case let .line(line, lineIndex):
                            transcriptLineView(line, lineIndex: lineIndex)
                                .id(line.id)
                                .onTapGesture {
                                    onSeek?(line.startOffset)
                                }
                        case let .segment(segment):
                            segmentDivider(segment)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onChange(of: activeLineIndex) { _, newIndex in
                if let idx = newIndex,
                   idx < transcript.lines.count
                {
                    let lineId = transcript.lines[idx].id
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lineId, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Line Rendering

    @ViewBuilder
    private func transcriptLineView(
        _ line: SDRTranscriptLine, lineIndex: Int
    ) -> some View {
        let isActive = lineIndex == activeLineIndex

        HStack(alignment: .top, spacing: 8) {
            // Speaker callsign label
            Text(line.speakerCallsign ?? "")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 70, alignment: .leading)

            // Words with per-word highlighting
            wordFlow(line: line, lineIndex: lineIndex)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            isActive
                ? Color.accentColor.opacity(0.06)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(lineOpacity(lineIndex: lineIndex))
    }

    private func wordFlow(
        line: SDRTranscriptLine, lineIndex: Int
    ) -> some View {
        // Use a wrapping layout for words
        WrappingHStack(alignment: .leading, spacing: 4) {
            ForEach(
                Array(line.words.enumerated()), id: \.element.id
            ) { wordIdx, word in
                let isWordActive = lineIndex == activeLineIndex
                    && wordIdx == activeWordIndex

                Text(word.text)
                    .font(.subheadline.monospaced())
                    .fontWeight(isWordActive ? .bold : .regular)
                    .foregroundStyle(wordColor(
                        lineIndex: lineIndex, isWordActive: isWordActive
                    ))
                    .padding(.horizontal, isWordActive ? 2 : 0)
                    .background(
                        isWordActive
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
    }

    // MARK: - Segment Dividers

    private func segmentDivider(
        _ segment: SDRRecordingSegment
    ) -> some View {
        HStack(spacing: 8) {
            VStack { Divider() }
            Text(segmentLabel(segment))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            VStack { Divider() }
        }
        .padding(.vertical, 4)
    }

    private func wordColor(
        lineIndex: Int, isWordActive: Bool
    ) -> some ShapeStyle {
        if isWordActive || lineIndex == activeLineIndex {
            return AnyShapeStyle(.primary)
        }
        guard let activeLine = activeLineIndex else {
            return AnyShapeStyle(.secondary)
        }
        if lineIndex < activeLine {
            return AnyShapeStyle(.secondary)
        }
        return AnyShapeStyle(.tertiary)
    }

    private func lineOpacity(lineIndex: Int) -> Double {
        guard let activeLine = activeLineIndex else {
            return 0.8
        }
        if lineIndex == activeLine {
            return 1.0
        }
        let distance = abs(lineIndex - activeLine)
        return max(0.4, 1.0 - Double(distance) * 0.15)
    }

    private func segmentLabel(_ segment: SDRRecordingSegment) -> String {
        let mHz = segment.frequencyKHz / 1_000
        let freqStr = mHz == mHz.rounded()
            ? String(format: "%.0f MHz", mHz)
            : String(format: "%.3f MHz", mHz)
        return "\(freqStr) \u{00B7} \(segment.mode)"
    }

    // MARK: - Interleaving

    /// Interleave transcript lines with segment dividers at the right offsets
    private func interleaveItems(
        _ transcript: SDRRecordingTranscript
    ) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        var segmentIdx = 0
        // Skip first segment (no divider needed at recording start)
        let boundaries = Array(segments.dropFirst())

        for (lineIndex, line) in transcript.lines.enumerated() {
            // Insert segment dividers that fall before this line
            while segmentIdx < boundaries.count,
                  boundaries[segmentIdx].startOffset <= line.startOffset
            {
                let seg = boundaries[segmentIdx]
                if !seg.isSilence {
                    items.append(.segment(seg))
                }
                segmentIdx += 1
            }
            items.append(.line(line, lineIndex: lineIndex))
        }
        return items
    }
}

// MARK: - TranscriptItem

private enum TranscriptItem: Identifiable {
    case line(SDRTranscriptLine, lineIndex: Int)
    case segment(SDRRecordingSegment)

    // MARK: Internal

    var id: String {
        switch self {
        case let .line(line, _):
            "line-\(line.id)"
        case let .segment(seg):
            "seg-\(seg.startOffset)"
        }
    }
}

// MARK: - WrappingHStack

/// Simple wrapping horizontal layout for words that flow to the next line
struct WrappingHStack: Layout {
    // MARK: Internal

    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 4

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        let rows = computeRows(
            proposal: proposal, subviews: subviews
        )
        guard !rows.isEmpty else {
            return .zero
        }
        let height = rows.reduce(CGFloat(0)) { total, row in
            total + row.height + (total > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let rows = computeRows(
            proposal: proposal, subviews: subviews
        )
        var y = bounds.minY
        var subviewIdx = 0

        for row in rows {
            var x = bounds.minX
            for _ in 0 ..< row.count {
                let size = subviews[subviewIdx].sizeThatFits(.unspecified)
                subviews[subviewIdx].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
                subviewIdx += 1
            }
            y += row.height + spacing
        }
    }

    // MARK: Private

    private struct Row {
        var count: Int
        var height: CGFloat
    }

    private func computeRows(
        proposal: ProposedViewSize, subviews: Subviews
    ) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        var currentCount = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needed = currentCount > 0
                ? size.width + spacing
                : size.width

            if currentWidth + needed > maxWidth, currentCount > 0 {
                rows.append(Row(count: currentCount, height: currentHeight))
                currentWidth = size.width
                currentHeight = size.height
                currentCount = 1
            } else {
                currentWidth += needed
                currentHeight = max(currentHeight, size.height)
                currentCount += 1
            }
        }

        if currentCount > 0 {
            rows.append(Row(count: currentCount, height: currentHeight))
        }
        return rows
    }
}
