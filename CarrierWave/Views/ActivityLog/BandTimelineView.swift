import SwiftUI

// MARK: - ActivityBandSegment

/// A contiguous period of activity on a single band/mode combination
struct ActivityBandSegment: Identifiable {
    let id = UUID()
    let band: String
    let mode: String
    let count: Int
    let startTime: Date
    let endTime: Date

    var duration: TimeInterval {
        max(endTime.timeIntervalSince(startTime), 60)
    }

    var label: String {
        "\(band) \(mode) (\(count))"
    }
}

// MARK: - BandTimelineView

/// Horizontal band timeline showing activity segments throughout the day.
/// Each segment represents a band/mode combination with its duration.
struct BandTimelineView: View {
    // MARK: Internal

    let qsos: [QSO]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Band Timeline")
                .font(.subheadline.weight(.semibold))

            if segments.isEmpty {
                Text("No QSOs to display")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                GeometryReader { geometry in
                    timelineContent(width: geometry.size.width)
                }
                .frame(height: segmentRowHeight)

                timeLabels
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    private let segmentRowHeight: CGFloat = 32

    private var segments: [ActivityBandSegment] {
        buildSegments(from: qsos)
    }

    private var timeRange: (start: Date, end: Date)? {
        let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else {
            return nil
        }
        return (first.timestamp, last.timestamp)
    }

    @ViewBuilder
    private var timeLabels: some View {
        if let range = timeRange {
            HStack {
                Text(formatTime(range.start))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(range.end))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timelineContent(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(segments) { segment in
                segmentBar(segment, totalWidth: width)
            }
        }
    }

    private func segmentBar(_ segment: ActivityBandSegment, totalWidth: CGFloat) -> some View {
        let (x, barWidth) = segmentPosition(segment, totalWidth: totalWidth)
        let color = bandColor(segment.band)

        return Text(segment.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(width: max(barWidth, 20), height: segmentRowHeight - 4)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .offset(x: x)
    }

    private func segmentPosition(
        _ segment: ActivityBandSegment,
        totalWidth: CGFloat
    ) -> (x: CGFloat, width: CGFloat) {
        guard let range = timeRange else {
            return (0, totalWidth)
        }
        let totalDuration = max(range.end.timeIntervalSince(range.start), 60)
        let startOffset = segment.startTime.timeIntervalSince(range.start)
        let x = CGFloat(startOffset / totalDuration) * totalWidth
        let segWidth = CGFloat(segment.duration / totalDuration) * totalWidth
        return (x, max(segWidth, 20))
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private func buildSegments(from qsos: [QSO]) -> [ActivityBandSegment] {
        let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else {
            return []
        }

        var result: [ActivityBandSegment] = []
        var currentBand = sorted[0].band
        var currentMode = sorted[0].mode
        var batchStart = sorted[0].timestamp
        var batchEnd = sorted[0].timestamp
        var count = 1

        for qso in sorted.dropFirst() {
            if qso.band == currentBand, qso.mode == currentMode {
                batchEnd = qso.timestamp
                count += 1
            } else {
                result.append(ActivityBandSegment(
                    band: currentBand, mode: currentMode,
                    count: count, startTime: batchStart, endTime: batchEnd
                ))
                currentBand = qso.band
                currentMode = qso.mode
                batchStart = qso.timestamp
                batchEnd = qso.timestamp
                count = 1
            }
        }

        result.append(ActivityBandSegment(
            band: currentBand, mode: currentMode,
            count: count, startTime: batchStart, endTime: batchEnd
        ))

        return result
    }
}
