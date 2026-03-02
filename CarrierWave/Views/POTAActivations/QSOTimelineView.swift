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
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let tickHeight: CGFloat = compact ? 10 : 14
            let positions = layout.xPositions(in: width)
            let gapInfos = layout.gapInfos(in: width)
            let barCenterY: CGFloat = compact ? height / 2 : 9

            // Track
            let trackRect = CGRect(
                x: 0, y: barCenterY - 1.5, width: width, height: 3
            )
            context.fill(
                Path(roundedRect: trackRect, cornerRadius: 2),
                with: .color(Color(.systemGray5))
            )

            // Gap break indicators
            for gap in gapInfos {
                let gapCenterX = gap.x + gap.width / 2
                let zigzagWidth = max(gap.width - 16, 8)
                let zigzagRect = CGRect(
                    x: gapCenterX - zigzagWidth / 2,
                    y: barCenterY - 5, width: zigzagWidth, height: 10
                )
                let zigzag = GapBreakShape().path(in: zigzagRect)
                context.stroke(
                    zigzag, with: .color(Color(.systemGray3)),
                    style: StrokeStyle(lineWidth: 1.5)
                )
                if !compact {
                    let label = Text(gap.formattedDuration)
                        .font(.system(size: 7).monospaced())
                        .foregroundStyle(.tertiary)
                    context.draw(
                        context.resolve(label),
                        at: CGPoint(
                            x: gapCenterX, y: barCenterY + 14
                        ),
                        anchor: .center
                    )
                }
            }

            // QSO ticks
            for qso in sortedQSOs {
                if let xPos = positions[qso.id] {
                    let tickRect = CGRect(
                        x: xPos - 1, y: barCenterY - tickHeight / 2,
                        width: 2, height: tickHeight
                    )
                    context.fill(
                        Path(roundedRect: tickRect, cornerRadius: 1),
                        with: .color(bandColor(qso.band))
                    )
                }
            }

            // Segment time labels (non-compact only)
            if !compact {
                let segRanges = layout.segmentRanges(in: width)
                for seg in segRanges {
                    let startLabel = Text(
                        Self.utcTimeFormatter.string(from: seg.startTime) + "z"
                    )
                    .font(.system(size: 8).monospaced())
                    .foregroundStyle(.secondary)
                    context.draw(
                        context.resolve(startLabel),
                        at: CGPoint(x: seg.startX + 14, y: 24),
                        anchor: .center
                    )
                    if seg.endTime.timeIntervalSince(seg.startTime) > 60,
                       seg.width > 50
                    {
                        let endLabel = Text(
                            Self.utcTimeFormatter.string(
                                from: seg.endTime
                            ) + "z"
                        )
                        .font(.system(size: 8).monospaced())
                        .foregroundStyle(.secondary)
                        context.draw(
                            context.resolve(endLabel),
                            at: CGPoint(x: seg.endX - 14, y: 24),
                            anchor: .center
                        )
                    }
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
        Canvas { context, size in
            let width = size.width
            let positions = layout.xPositions(in: width)
            let gapInfos = layout.gapInfos(in: width)
            let segRanges = layout.segmentRanges(in: width)
            let barCenterY: CGFloat = 9

            // Track
            let trackRect = CGRect(
                x: 0, y: barCenterY - 1.5, width: width, height: 3
            )
            context.fill(
                Path(roundedRect: trackRect, cornerRadius: 2),
                with: .color(.white.opacity(0.15))
            )

            // Gap break indicators with duration
            for gap in gapInfos {
                let gapCenterX = gap.x + gap.width / 2
                let zigzagWidth = max(gap.width - 16, 8)
                let zigzagRect = CGRect(
                    x: gapCenterX - zigzagWidth / 2,
                    y: barCenterY - 5, width: zigzagWidth, height: 10
                )
                let zigzag = GapBreakShape().path(in: zigzagRect)
                context.stroke(
                    zigzag, with: .color(.white.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 1.5)
                )
                let label = Text(gap.formattedDuration)
                    .font(.system(size: 7).monospaced())
                    .foregroundStyle(.white.opacity(0.4))
                context.draw(
                    context.resolve(label),
                    at: CGPoint(x: gapCenterX, y: barCenterY + 14),
                    anchor: .center
                )
            }

            // QSO ticks
            for qso in sortedQSOs {
                if let xPos = positions[qso.id] {
                    let tickRect = CGRect(
                        x: xPos - 1, y: barCenterY - 7,
                        width: 2, height: 14
                    )
                    context.fill(
                        Path(roundedRect: tickRect, cornerRadius: 1),
                        with: .color(bandColor(qso.band))
                    )
                }
            }

            // Segment time labels
            for seg in segRanges {
                let startLabel = Text(
                    Self.utcTimeFormatter.string(from: seg.startTime) + "z"
                )
                .font(.system(size: 8).monospaced())
                .foregroundStyle(.white.opacity(0.5))
                context.draw(
                    context.resolve(startLabel),
                    at: CGPoint(x: seg.startX + 14, y: 24),
                    anchor: .center
                )
                if seg.endTime.timeIntervalSince(seg.startTime) > 60,
                   seg.width > 50
                {
                    let endLabel = Text(
                        Self.utcTimeFormatter.string(
                            from: seg.endTime
                        ) + "z"
                    )
                    .font(.system(size: 8).monospaced())
                    .foregroundStyle(.white.opacity(0.5))
                    context.draw(
                        context.resolve(endLabel),
                        at: CGPoint(x: seg.endX - 14, y: 24),
                        anchor: .center
                    )
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
