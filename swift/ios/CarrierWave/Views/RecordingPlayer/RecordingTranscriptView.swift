import CarrierWaveData
import SwiftUI

// MARK: - RecordingTranscriptView

/// Karaoke-style scrolling CW transcript, time-aligned to recording playback.
/// Words highlight as playback passes them, and the active line stays centered.
/// Two-operator conversations use a chat-style layout (OP 1 left, OP 2 right)
/// with UTC timestamps on each operator change.
struct RecordingTranscriptView: View {
    // MARK: Internal

    let transcript: SDRRecordingTranscript?
    let segments: [SDRRecordingSegment]
    let activeLineIndex: Int?
    let activeWordIndex: Int?
    let currentTime: TimeInterval
    let recordingStartedAt: Date
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

    /// Distinct colors for different operators (by frequency group).
    private static let operatorColors: [Color] = [
        .blue, .orange, .green, .purple, .pink, .cyan, .yellow, .red,
    ]

    private static let utcTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Use chat-style left/right layout when exactly 2 operators are present
    private var isChatLayout: Bool {
        guard let transcript else {
            return false
        }
        let ops = Set(transcript.lines.compactMap(\.operatorId))
        return ops.count == 2
    }

    /// The operator ID that gets left-aligned (lowest = primary station)
    private var primaryOperatorId: Int {
        guard let transcript else {
            return 0
        }
        return transcript.lines.compactMap(\.operatorId).min() ?? 0
    }

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
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(
                        interleaveItems(transcript), id: \.id
                    ) { item in
                        switch item {
                        case let .line(line, lineIndex, overlap, continues):
                            transcriptLineView(
                                line, lineIndex: lineIndex,
                                overlapsWithPrevious: overlap,
                                continuesOperator: continues
                            )
                            .id(line.id)
                            .onTapGesture {
                                onSeek?(line.startOffset)
                            }
                        case let .segment(segment):
                            segmentDivider(segment)
                                .padding(.vertical, 6)
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
        _ line: SDRTranscriptLine, lineIndex: Int,
        overlapsWithPrevious: Bool, continuesOperator: Bool
    ) -> some View {
        let isActive = lineIndex == activeLineIndex
        let opColor = operatorColor(for: line.operatorId)
        let rightAligned = isChatLayout
            && (line.operatorId ?? 0) != primaryOperatorId

        HStack(alignment: .top, spacing: 0) {
            if rightAligned {
                Spacer(minLength: 40)
            }

            if !rightAligned {
                colorBar(opColor, continuesOperator: continuesOperator)
            }

            VStack(alignment: .leading, spacing: 2) {
                if !continuesOperator {
                    lineHeader(line, opColor: opColor)
                }
                wordFlow(line: line, lineIndex: lineIndex)
            }
            .padding(.leading, rightAligned ? 0 : 8)
            .padding(.trailing, rightAligned ? 8 : 0)

            if rightAligned {
                colorBar(opColor, continuesOperator: continuesOperator)
            }

            if !rightAligned {
                Spacer(minLength: isChatLayout ? 40 : 0)
            }
        }
        .padding(.top, continuesOperator ? 0 : (overlapsWithPrevious ? 2 : 6))
        .padding(.bottom, 2)
        .padding(.horizontal, 8)
        .background(
            isActive
                ? opColor.opacity(0.08)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: continuesOperator ? 0 : 6))
    }

    private func colorBar(
        _ color: Color, continuesOperator: Bool
    ) -> some View {
        RoundedRectangle(cornerRadius: continuesOperator ? 0 : 1.5)
            .fill(color)
            .frame(width: 3)
            .padding(.vertical, continuesOperator ? 0 : 2)
    }

    private func lineHeader(
        _ line: SDRTranscriptLine, opColor: Color
    ) -> some View {
        HStack(spacing: 6) {
            Text(speakerLabel(for: line))
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(opColor)
            Text(formatUTCTime(line.startOffset))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private func wordFlow(
        line: SDRTranscriptLine, lineIndex: Int
    ) -> some View {
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
    }

    // MARK: - Helpers

    private func wordColor(
        lineIndex: Int, isWordActive: Bool
    ) -> some ShapeStyle {
        if isWordActive || lineIndex == activeLineIndex {
            return AnyShapeStyle(.primary)
        }
        guard let activeLine = activeLineIndex else {
            return AnyShapeStyle(.secondary)
        }
        return lineIndex < activeLine
            ? AnyShapeStyle(.secondary)
            : AnyShapeStyle(.tertiary)
    }

    private func segmentLabel(_ segment: SDRRecordingSegment) -> String {
        let mHz = segment.frequencyKHz / 1_000
        let freqStr = mHz == mHz.rounded()
            ? String(format: "%.0f MHz", mHz)
            : String(format: "%.3f MHz", mHz)
        return "\(freqStr) \u{00B7} \(segment.mode)"
    }

    private func formatUTCTime(_ offset: TimeInterval) -> String {
        let date = recordingStartedAt.addingTimeInterval(offset)
        return Self.utcTimeFormatter.string(from: date) + "z"
    }

    private func operatorColor(for operatorId: Int?) -> Color {
        guard let id = operatorId else {
            return .accentColor
        }
        return Self.operatorColors[id % Self.operatorColors.count]
    }

    private func speakerLabel(for line: SDRTranscriptLine) -> String {
        if let callsign = line.speakerCallsign {
            return callsign
        }
        if let id = line.operatorId {
            return "OP \(id + 1)"
        }
        return ""
    }

    // MARK: - Interleaving with Overlap Detection

    /// Interleave transcript lines with segment dividers, detecting time overlaps
    private func interleaveItems(
        _ transcript: SDRRecordingTranscript
    ) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        var segmentIdx = 0
        let boundaries = Array(segments.dropFirst())
        var prevEndOffset: TimeInterval = -.infinity
        var prevOperatorId: Int?

        for (lineIndex, line) in transcript.lines.enumerated() {
            // Insert segment dividers that fall before this line
            while segmentIdx < boundaries.count,
                  boundaries[segmentIdx].startOffset <= line.startOffset
            {
                let seg = boundaries[segmentIdx]
                if !seg.isSilence {
                    items.append(.segment(seg))
                    prevEndOffset = -.infinity
                    prevOperatorId = nil // reset after divider
                }
                segmentIdx += 1
            }

            let sameOperator = line.operatorId != nil
                && line.operatorId == prevOperatorId

            // Lines overlap when this one starts before the previous ends
            // and they come from different operators
            let overlaps = line.startOffset < prevEndOffset && !sameOperator

            items.append(.line(
                line, lineIndex: lineIndex,
                overlapsWithPrevious: overlaps,
                continuesOperator: sameOperator
            ))
            prevEndOffset = line.endOffset
            prevOperatorId = line.operatorId
        }
        return items
    }
}

// MARK: - TranscriptItem

private enum TranscriptItem: Identifiable {
    case line(
        SDRTranscriptLine, lineIndex: Int,
        overlapsWithPrevious: Bool, continuesOperator: Bool
    )
    case segment(SDRRecordingSegment)

    // MARK: Internal

    var id: String {
        switch self {
        case let .line(line, _, _, _):
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
        let rows = computeRows(proposal: proposal, subviews: subviews)
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
        let rows = computeRows(proposal: proposal, subviews: subviews)
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
