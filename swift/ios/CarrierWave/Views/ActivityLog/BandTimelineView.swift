import CarrierWaveData
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

    /// Optional fixed time range to anchor the timeline. When provided,
    /// segments render at their absolute position within this window
    /// (a 5-minute session inside a 24-hour day shows as a small bar).
    /// When nil (default), the timeline auto-fits the first/last QSO.
    var dayWindow: ClosedRange<Date>?

    /// When true, the view drops its own card chrome (title, padding,
    /// background) and renders as plain inline content. Callers that
    /// embed it inside a List `Section("Band Timeline") { … }` opt in to
    /// this mode so the parent section header + List row styling drive
    /// the visual frame instead of double-decorating the card.
    var unwrapped: Bool = false

    var body: some View {
        if unwrapped {
            inlineContent
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Band Timeline")
                    .font(.subheadline.weight(.semibold))
                inlineContent
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: Private

    private struct LegendEntry {
        let id: String
        let band: String
        let mode: String
        let earliest: Date
        let latest: Date
        let count: Int

        var timeRangeText: String {
            let formatter = BandTimelineView.utcTimeFormatter
            let start = formatter.string(from: earliest)
            let end = formatter.string(from: latest)
            return start == end ? start : "\(start)–\(end)"
        }

        var accessibilityLabel: String {
            "\(band) \(mode), \(count) QSO\(count == 1 ? "" : "s"), \(timeRangeText)"
        }
    }

    private static let utcTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @ScaledMetric(relativeTo: .caption2) private var segmentRowHeight: CGFloat = 32

    private var segments: [ActivityBandSegment] {
        buildSegments(from: qsos)
    }

    private var timeRange: (start: Date, end: Date)? {
        if let dayWindow {
            return (dayWindow.lowerBound, dayWindow.upperBound)
        }
        let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else {
            return nil
        }
        return (first.timestamp, last.timestamp)
    }

    /// Groups segments by case-normalised band + mode so the same combo
    /// logged twice with inconsistent casing ("20m CW" vs "20M CW")
    /// collapses to one row, sorted by first activity.
    private var aggregatedLegend: [LegendEntry] {
        var buckets: [String: LegendEntry] = [:]
        for segment in segments {
            let band = segment.band.uppercased()
            let mode = segment.mode.uppercased()
            let key = "\(band)|\(mode)"
            if let existing = buckets[key] {
                buckets[key] = LegendEntry(
                    id: key,
                    band: band,
                    mode: mode,
                    earliest: min(existing.earliest, segment.startTime),
                    latest: max(existing.latest, segment.endTime),
                    count: existing.count + segment.count
                )
            } else {
                buckets[key] = LegendEntry(
                    id: key,
                    band: band,
                    mode: mode,
                    earliest: segment.startTime,
                    latest: segment.endTime,
                    count: segment.count
                )
            }
        }
        return buckets.values.sorted { $0.earliest < $1.earliest }
    }

    @ViewBuilder
    private var inlineContent: some View {
        if segments.isEmpty {
            Text("No QSOs to display")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        if dayWindow != nil {
                            hourGridlines(width: geometry.size.width)
                        }
                        timelineContent(width: geometry.size.width)
                    }
                }
                .frame(height: segmentRowHeight)

                timeLabels

                if dayWindow != nil {
                    segmentLegend
                }
            }
        }
    }

    @ViewBuilder
    private var timeLabels: some View {
        if dayWindow != nil {
            // Anchored to the full UTC day — label every six hours.
            HStack(spacing: 0) {
                ForEach(["00", "06", "12", "18", "24"], id: \.self) { hour in
                    Text(hour)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: hour == "00"
                            ? .leading
                            : (hour == "24" ? .trailing : .center))
                }
            }
        } else if let range = timeRange {
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

    /// Aggregated legend — one row per unique band/mode pair across the
    /// whole day. Surfaces what was worked, when it spanned, and how many
    /// contacts each combo netted. Used only in day-window mode.
    private var segmentLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(aggregatedLegend, id: \.id) { entry in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(bandColor(entry.band))
                        .frame(width: 10, height: 10)
                    Text("\(entry.band) \(entry.mode)")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 8)
                    Text(entry.timeRangeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("\(entry.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 24, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(entry.accessibilityLabel)
            }
        }
        .padding(.top, 8)
    }

    private func hourGridlines(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(1 ..< 24, id: \.self) { hour in
                let isMajor = hour.isMultiple(of: 6)
                Rectangle()
                    .fill(Color(.systemGray4).opacity(isMajor ? 0.6 : 0.25))
                    .frame(width: isMajor ? 1 : 0.5)
                    .offset(x: CGFloat(hour) / 24 * width)
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

    @ViewBuilder
    private func segmentBar(_ segment: ActivityBandSegment, totalWidth: CGFloat) -> some View {
        let (x, barWidth) = segmentPosition(segment, totalWidth: totalWidth)
        let color = bandColor(segment.band)

        if dayWindow != nil {
            // Day-window mode: bars are pure colored markers. The label
            // would truncate to "..." inside a 4pt blip, so we surface
            // segment details in the legend below instead.
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: max(barWidth, 4), height: segmentRowHeight - 4)
                .offset(x: x)
        } else {
            Text(segment.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color(.systemBackground))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .frame(width: max(barWidth, 20), height: segmentRowHeight - 4)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .offset(x: x)
        }
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
        let minimum: CGFloat = dayWindow != nil ? 4 : 20
        return (x, max(segWidth, minimum))
    }

    private func formatTime(_ date: Date) -> String {
        Self.utcTimeFormatter.string(from: date)
    }

    private func buildSegments(from qsos: [QSO]) -> [ActivityBandSegment] {
        let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else {
            return []
        }

        var result: [ActivityBandSegment] = []
        // Normalise band + mode case so "20m CW" and "20M CW" don't get
        // split into separate segments because of inconsistent capitalisation
        // in the underlying QSO records.
        var currentBand = sorted[0].band.uppercased()
        var currentMode = sorted[0].mode.uppercased()
        var batchStart = sorted[0].timestamp
        var batchEnd = sorted[0].timestamp
        var count = 1

        for qso in sorted.dropFirst() {
            let band = qso.band.uppercased()
            let mode = qso.mode.uppercased()
            if band == currentBand, mode == currentMode {
                batchEnd = qso.timestamp
                count += 1
            } else {
                result.append(ActivityBandSegment(
                    band: currentBand, mode: currentMode,
                    count: count, startTime: batchStart, endTime: batchEnd
                ))
                currentBand = band
                currentMode = mode
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
