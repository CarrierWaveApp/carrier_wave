// QSO Timeline View
//
// Compact horizontal timeline showing when QSOs occurred during an activation.
// Each tick mark represents a QSO, colored by band. Gaps longer than 1 hour
// are collapsed into a visual break with duration labels.
// Layout logic lives in QSOTimelineLayout.swift.

import SwiftUI

// MARK: - QSOTimelineView

struct QSOTimelineView: View {
    // MARK: Internal

    let qsos: [QSO]
    var compact: Bool = false

    var body: some View {
        if qsos.isEmpty {
            EmptyView()
        } else {
            content
        }
    }

    // MARK: Private

    private static let utcTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private var layout: TimelineLayout {
        TimelineLayout(qsos: qsos)
    }

    private var sortedQSOs: [QSO] {
        qsos.sorted { $0.timestamp < $1.timestamp }
    }

    private var uniqueBands: [String] {
        Array(Set(qsos.map(\.band))).sorted()
    }

    private var showBandLegend: Bool {
        !compact && uniqueBands.count > 1
    }

    private var content: some View {
        VStack(spacing: compact ? 0 : 4) {
            timelineBar
            if showBandLegend {
                bandLegend
            }
        }
    }

    private var timelineBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let tickHeight: CGFloat = compact ? 10 : 14
            let positions = layout.xPositions(in: width)
            let gapInfos = layout.gapInfos(in: width)
            let segRanges = layout.segmentRanges(in: width)
            let barCenterY: CGFloat = compact ? geo.size.height / 2 : 9

            ZStack(alignment: .topLeading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemGray5))
                    .frame(height: 3)
                    .position(x: width / 2, y: barCenterY)

                // Gap break indicators
                ForEach(gapInfos) { gap in
                    gapBreak(gap, centerY: barCenterY, compact: compact)
                }

                // QSO ticks
                ForEach(sortedQSOs) { qso in
                    if let xPos = positions[qso.id] {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(bandColor(qso.band))
                            .frame(width: 2, height: tickHeight)
                            .position(x: xPos, y: barCenterY)
                    }
                }

                // Segment time labels (non-compact only)
                if !compact {
                    segmentTimeLabels(segRanges)
                }
            }
        }
        .frame(height: compact ? 10 : 28)
    }

    private var bandLegend: some View {
        HStack(spacing: 10) {
            ForEach(uniqueBands, id: \.self) { band in
                HStack(spacing: 3) {
                    Circle()
                        .fill(bandColor(band))
                        .frame(width: 5, height: 5)
                    Text(band)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func gapBreak(
        _ gap: GapInfo, centerY: CGFloat, compact: Bool
    ) -> some View {
        let gapCenterX = gap.x + gap.width / 2
        let zigzagWidth = max(gap.width - 16, 8) // 8pt padding each side
        // Zigzag
        GapBreakShape()
            .stroke(Color(.systemGray3), style: StrokeStyle(lineWidth: 1.5))
            .frame(width: zigzagWidth, height: 10)
            .position(x: gapCenterX, y: centerY)
        // Duration label below zigzag (non-compact only)
        if !compact {
            Text(gap.formattedDuration)
                .font(.system(size: 7).monospaced())
                .foregroundStyle(.tertiary)
                .position(x: gapCenterX, y: centerY + 14)
        }
    }

    private func segmentTimeLabels(_ ranges: [SegmentRange]) -> some View {
        ForEach(ranges) { seg in
            // Start time at left edge of segment
            Text(Self.utcTimeFormatter.string(from: seg.startTime) + "z")
                .font(.system(size: 8).monospaced())
                .foregroundStyle(.secondary)
                .position(x: seg.startX + 14, y: 24)
            // End time at right edge (only if segment spans > 1 min)
            if seg.endTime.timeIntervalSince(seg.startTime) > 60,
               seg.width > 50
            {
                Text(Self.utcTimeFormatter.string(from: seg.endTime) + "z")
                    .font(.system(size: 8).monospaced())
                    .foregroundStyle(.secondary)
                    .position(x: seg.endX - 14, y: 24)
            }
        }
    }
}

// MARK: - ShareCardTimelineView

/// Timeline variant styled for the dark share card background
struct ShareCardTimelineView: View {
    // MARK: Internal

    let qsos: [QSO]

    var body: some View {
        if qsos.isEmpty {
            EmptyView()
        } else {
            content
        }
    }

    // MARK: Private

    private static let utcTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private var layout: TimelineLayout {
        TimelineLayout(qsos: qsos)
    }

    private var sortedQSOs: [QSO] {
        qsos.sorted { $0.timestamp < $1.timestamp }
    }

    private var uniqueBands: [String] {
        Array(Set(qsos.map(\.band))).sorted()
    }

    private var content: some View {
        VStack(spacing: 4) {
            timelineBar
            if uniqueBands.count > 1 {
                bandLegend
            }
        }
    }

    private var timelineBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let positions = layout.xPositions(in: width)
            let gapInfos = layout.gapInfos(in: width)
            let segRanges = layout.segmentRanges(in: width)
            let barCenterY: CGFloat = 9

            ZStack(alignment: .topLeading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 3)
                    .position(x: width / 2, y: barCenterY)

                // Gap break indicators with duration
                ForEach(gapInfos) { gap in
                    let gapCenterX = gap.x + gap.width / 2
                    let zigzagWidth = max(gap.width - 16, 8)
                    GapBreakShape()
                        .stroke(
                            Color.white.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1.5)
                        )
                        .frame(width: zigzagWidth, height: 10)
                        .position(x: gapCenterX, y: barCenterY)
                    Text(gap.formattedDuration)
                        .font(.system(size: 7).monospaced())
                        .foregroundStyle(.white.opacity(0.4))
                        .position(x: gapCenterX, y: barCenterY + 14)
                }

                // QSO ticks
                ForEach(sortedQSOs) { qso in
                    if let xPos = positions[qso.id] {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(bandColor(qso.band))
                            .frame(width: 2, height: 14)
                            .position(x: xPos, y: barCenterY)
                    }
                }

                // Segment time labels
                ForEach(segRanges) { seg in
                    Text(Self.utcTimeFormatter.string(from: seg.startTime) + "z")
                        .font(.system(size: 8).monospaced())
                        .foregroundStyle(.white.opacity(0.5))
                        .position(x: seg.startX + 14, y: 24)
                    if seg.endTime.timeIntervalSince(seg.startTime) > 60,
                       seg.width > 50
                    {
                        Text(Self.utcTimeFormatter.string(from: seg.endTime) + "z")
                            .font(.system(size: 8).monospaced())
                            .foregroundStyle(.white.opacity(0.5))
                            .position(x: seg.endX - 14, y: 24)
                    }
                }
            }
        }
        .frame(height: 28)
    }

    private var bandLegend: some View {
        HStack(spacing: 10) {
            ForEach(uniqueBands, id: \.self) { band in
                HStack(spacing: 3) {
                    Circle()
                        .fill(bandColor(band))
                        .frame(width: 5, height: 5)
                    Text(band)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}
