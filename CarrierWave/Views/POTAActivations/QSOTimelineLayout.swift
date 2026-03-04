// QSO Timeline Layout
//
// Shared layout engine for QSO timelines. Splits QSOs into segments
// separated by gaps > 1 hour, then allocates horizontal space proportionally
// to segment duration with fixed-width gap breaks between them.

import CarrierWaveData
import SwiftUI

// MARK: - TimelineSegment

/// A contiguous burst of QSO activity with no gaps > 1 hour
struct TimelineSegment: Identifiable {
    let id = UUID()
    let qsos: [QSO]
    let startTime: Date
    let endTime: Date

    var duration: TimeInterval {
        max(endTime.timeIntervalSince(startTime), 1)
    }
}

// MARK: - GapInfo

/// Layout info for a single gap break, including position and duration
struct GapInfo: Identifiable {
    let id = UUID()
    let x: CGFloat
    let width: CGFloat
    let duration: TimeInterval

    var formattedDuration: String {
        let totalMinutes = Int(duration) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return "\(hours)h\(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

// MARK: - SegmentRange

/// Layout info for a segment's horizontal extent
struct SegmentRange: Identifiable {
    let id = UUID()
    let startX: CGFloat
    let endX: CGFloat
    let startTime: Date
    let endTime: Date

    var centerX: CGFloat {
        (startX + endX) / 2
    }

    var width: CGFloat {
        endX - startX
    }
}

// MARK: - TimelineLayout

/// Computes segment layout and QSO x-positions, shared by both view variants
struct TimelineLayout {
    // MARK: Lifecycle

    init(qsos: [QSO]) {
        let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else {
            segments = []
            gaps = []
            return
        }

        var segs: [TimelineSegment] = []
        var gapList: [TimeInterval] = []
        var currentBatch: [QSO] = [sorted[0]]

        for i in 1 ..< sorted.count {
            let gap = sorted[i].timestamp.timeIntervalSince(sorted[i - 1].timestamp)
            if gap >= Self.gapThreshold {
                segs.append(
                    TimelineSegment(
                        qsos: currentBatch,
                        startTime: currentBatch.first!.timestamp,
                        endTime: currentBatch.last!.timestamp
                    )
                )
                gapList.append(gap)
                currentBatch = [sorted[i]]
            } else {
                currentBatch.append(sorted[i])
            }
        }
        segs.append(
            TimelineSegment(
                qsos: currentBatch,
                startTime: currentBatch.first!.timestamp,
                endTime: currentBatch.last!.timestamp
            )
        )

        segments = segs
        gaps = gapList
    }

    // MARK: Internal

    /// Minimum gap (seconds) to trigger a visual break
    static let gapThreshold: TimeInterval = 3_600

    /// Fixed width allocated to each gap break (points)
    static let gapWidth: CGFloat = 32

    let segments: [TimelineSegment]
    let gaps: [TimeInterval]

    var hasGaps: Bool {
        !gaps.isEmpty
    }

    /// Compute x-position for every QSO given total available width
    func xPositions(in totalWidth: CGFloat) -> [UUID: CGFloat] {
        guard !segments.isEmpty else {
            return [:]
        }

        if segments.count == 1, segments[0].qsos.count == 1 {
            return [segments[0].qsos[0].id: totalWidth / 2]
        }

        let params = layoutParams(in: totalWidth)
        var result: [UUID: CGFloat] = [:]
        var cursor = params.inset

        for (segIndex, segment) in segments.enumerated() {
            let segWidth = segmentWidth(
                segment, totalSegDuration: params.totalSegDuration,
                segmentSpace: params.segmentSpace
            )

            for qso in segment.qsos {
                let fraction: CGFloat =
                    segment.duration > 1
                        ? CGFloat(
                            qso.timestamp.timeIntervalSince(segment.startTime)
                                / segment.duration
                        )
                        : 0.5
                result[qso.id] = cursor + fraction * segWidth
            }

            cursor += segWidth
            if segIndex < gaps.count {
                cursor += Self.gapWidth
            }
        }

        return result
    }

    /// Compute gap info with positions and durations for rendering
    func gapInfos(in totalWidth: CGFloat) -> [GapInfo] {
        guard !segments.isEmpty else {
            return []
        }

        let params = layoutParams(in: totalWidth)
        var infos: [GapInfo] = []
        var cursor = params.inset

        for segIndex in 0 ..< segments.count {
            let segWidth = segmentWidth(
                segments[segIndex], totalSegDuration: params.totalSegDuration,
                segmentSpace: params.segmentSpace
            )
            cursor += segWidth

            if segIndex < gaps.count {
                infos.append(
                    GapInfo(
                        x: cursor, width: Self.gapWidth,
                        duration: gaps[segIndex]
                    )
                )
                cursor += Self.gapWidth
            }
        }

        return infos
    }

    /// Compute the horizontal range for each segment (for time labels)
    func segmentRanges(in totalWidth: CGFloat) -> [SegmentRange] {
        guard !segments.isEmpty else {
            return []
        }

        let params = layoutParams(in: totalWidth)
        var ranges: [SegmentRange] = []
        var cursor = params.inset

        for (segIndex, segment) in segments.enumerated() {
            let segWidth = segmentWidth(
                segment, totalSegDuration: params.totalSegDuration,
                segmentSpace: params.segmentSpace
            )

            ranges.append(
                SegmentRange(
                    startX: cursor, endX: cursor + segWidth,
                    startTime: segment.startTime, endTime: segment.endTime
                )
            )

            cursor += segWidth
            if segIndex < gaps.count {
                cursor += Self.gapWidth
            }
        }

        return ranges
    }

    // MARK: Private

    private struct LayoutParams {
        let inset: CGFloat
        let segmentSpace: CGFloat
        let totalSegDuration: TimeInterval
    }

    private func layoutParams(in totalWidth: CGFloat) -> LayoutParams {
        let inset: CGFloat = 2
        let usableWidth = totalWidth - inset * 2
        let totalGapWidth = CGFloat(gaps.count) * Self.gapWidth
        let minSegDuration: TimeInterval = 60
        let totalSegDuration = segments.reduce(0.0) {
            $0 + max($1.duration, minSegDuration)
        }
        let segmentSpace = max(usableWidth - totalGapWidth, 0)
        return LayoutParams(
            inset: inset, segmentSpace: segmentSpace,
            totalSegDuration: totalSegDuration
        )
    }

    private func segmentWidth(
        _ segment: TimelineSegment,
        totalSegDuration: TimeInterval,
        segmentSpace: CGFloat
    ) -> CGFloat {
        let minSegDuration: TimeInterval = 60
        let segDuration = max(segment.duration, minSegDuration)
        return totalSegDuration > 0
            ? segmentSpace * CGFloat(segDuration / totalSegDuration)
            : segmentSpace / CGFloat(segments.count)
    }
}

// MARK: - GapBreakShape

/// A zigzag shape indicating a time break in the timeline
struct GapBreakShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let amplitude = rect.height * 0.45
        let steps = 3
        let stepWidth = rect.width / CGFloat(steps)

        path.move(to: CGPoint(x: rect.minX, y: midY))
        for i in 0 ..< steps {
            let xStart = rect.minX + CGFloat(i) * stepWidth
            let yDir: CGFloat = i.isMultiple(of: 2) ? -1 : 1
            path.addLine(
                to: CGPoint(
                    x: xStart + stepWidth / 2,
                    y: midY + amplitude * yDir
                )
            )
            path.addLine(
                to: CGPoint(
                    x: xStart + stepWidth,
                    y: midY
                )
            )
        }

        return path
    }
}

// MARK: - Band Colors

/// Band color mapping for timeline ticks
func bandColor(_ band: String) -> Color {
    switch band.lowercased() {
    case "160m": .indigo
    case "80m": .purple
    case "60m": .cyan
    case "40m": .green
    case "30m": .teal
    case "20m": .blue
    case "17m": .mint
    case "15m": .orange
    case "12m": .pink
    case "10m": .red
    case "6m": .yellow
    case "2m": .brown
    default: .gray
    }
}
