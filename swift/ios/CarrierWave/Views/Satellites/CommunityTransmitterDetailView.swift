import Charts
import SwiftUI

// MARK: - CommunityTransmitterDetailView

/// One transmitter's week on Swift Charts: a summary card, a scrubbable
/// stacked-bar chart of hourly reports with a "now" rule and your own
/// passes shaded behind it, and an hour-of-day histogram answering "when
/// is this bird usually heard". Drag the week chart to read any hour.
struct CommunityTransmitterDetailView: View {
    // MARK: Internal

    let model: SatelliteTrackerModel
    let row: CommunityActivityRow
    let onShowOnMap: (Int) -> Void

    var body: some View {
        List {
            Section {
                CommunityDetailSummary(row: row, onShowOnMap: onShowOnMap)
            }
            Section {
                CommunityWeekChart(
                    activity: hourly,
                    buckets: hourlyRow.buckets,
                    passes: passes,
                    selection: $selectedHour
                )
                .frame(height: 190)
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 6, trailing: 12))
            } header: {
                Text("This week")
            } footer: {
                Text(weekFooter)
            }
            Section {
                CommunityHourOfDayChart(buckets: hourlyRow.buckets)
                    .frame(height: 130)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 6, trailing: 12))
            } header: {
                Text("By hour of day (UTC)")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reports summed over the week per UTC hour — the bird's usual active hours.")
                    AmsatAttributionLabel()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(row.displayName + (row.capability.map { " · \($0)" } ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showReport = true
                } label: {
                    Label("Report", systemImage: "square.and.pencil")
                }
                .accessibilityLabel("Report this transmitter's status to AMSAT")
            }
        }
        .sheet(isPresented: $showReport) {
            SatelliteCommunityReportSheet(model: model, rows: [row], initialName: row.amsatName)
        }
        .task {
            hourly = try? await model.communityActivity(cellSeconds: 3_600)
            if let noradID = row.noradID, row.inCatalog, let window = hourly {
                passes = await model.passes(for: noradID, from: window.windowStart, to: window.windowEnd)
            }
        }
    }

    // MARK: Private

    @State private var hourly: CommunityActivity?
    @State private var passes = [SatellitePass]()
    @State private var selectedHour: Date?
    @State private var showReport = false

    /// The hourly row for this transmitter (falls back to the list's row).
    private var hourlyRow: CommunityActivityRow {
        hourly?.rows.first { $0.id == row.id } ?? row
    }

    private var weekFooter: String {
        var parts = ["Pinch to zoom, drag to pan, hold to read an hour, double-tap to reset"]
        if !passes.isEmpty {
            parts.append("shaded bands are your passes")
        }
        return parts.joined(separator: " · ") + "."
    }
}

// MARK: - CommunityDetailSummary

/// Frequencies, SatNOGS status, last heard, next pass, your QSOs, and the
/// Show on Map button (or why the bird can't be shown).
struct CommunityDetailSummary: View {
    // MARK: Internal

    let row: CommunityActivityRow
    let onShowOnMap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let detail = row.detailName {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                SatelliteModeBadge(mode: row.badgeMode)
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.subheadline.monospacedDigit())
            }
            if row.inCatalog, let noradID = row.noradID {
                Button {
                    onShowOnMap(noradID)
                } label: {
                    Label("Show on Map", systemImage: "map")
                }
                .buttonStyle(.bordered)
            } else {
                Text("Not in your satellite catalog — no TLE or no active amateur transmitter on SatNOGS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    private var lines: [String] {
        var lines = [String]()
        if let downlink = row.downlinkLow {
            var freq = "↓ " + CommunityFormat.mhz(downlink)
            if let uplink = row.uplinkLow {
                freq += "  ↑ " + CommunityFormat.mhz(uplink)
            }
            if row.transmitterActive == false {
                freq += "  (SatNOGS: inactive)"
            }
            lines.append(freq)
        }
        if let heard = row.lastHeardAt {
            let ago = CommunityFormat.ago(from: heard)
            let counts = "\(row.heardReports24h)/\(row.totalReports24h) heard in 24 h"
            lines.append("Last heard \(ago) · \(counts)")
        } else {
            lines.append("No positive report this week")
        }
        if let pass = row.nextPass {
            let minutes = Int(pass.duration / 60)
            let when = CommunityFormat.countdown(to: pass.aos)
            let peak = Int(pass.peakElevationDeg.rounded())
            lines.append("Next pass \(when) · peak \(peak)° · \(minutes) min")
        }
        if row.myQSOCount > 0 {
            lines.append("You logged \(row.myQSOCount) QSO\(row.myQSOCount == 1 ? "" : "s") this week")
        }
        return lines
    }
}

// MARK: - CommunityReportPoint

/// One (hour, verdict, count) point for the stacked charts.
nonisolated struct CommunityReportPoint: Identifiable, Sendable {
    let start: Date
    let verdict: String
    let reports: Int

    var id: String {
        "\(start.timeIntervalSince1970)-\(verdict)"
    }

    /// Flatten buckets into stacked points, in legend order so the stack
    /// reads heard at the bottom, not-heard on top.
    static func points(from buckets: [CommunityActivityBucket]) -> [CommunityReportPoint] {
        buckets.flatMap { bucket -> [CommunityReportPoint] in
            [
                (bucket.heard + bucket.crew + bucket.other, CommunityActivityStatus.heard.label),
                (bucket.telemetry, CommunityActivityStatus.telemetryOnly.label),
                (bucket.notHeard, CommunityActivityStatus.notHeard.label),
            ]
            .filter { $0.0 > 0 }
            .map { CommunityReportPoint(start: bucket.start, verdict: $0.1, reports: $0.0) }
        }
    }
}

// MARK: - CommunityChartStyle

/// Chart colour scale keyed by legend label (main-actor: `Color` lives there).
@MainActor
enum CommunityChartStyle {
    static var colorScale: KeyValuePairs<String, Color> {
        [
            CommunityActivityStatus.heard.label: CommunityActivityStatus.heard.color,
            CommunityActivityStatus.telemetryOnly.label: CommunityActivityStatus.telemetryOnly.color,
            CommunityActivityStatus.notHeard.label: CommunityActivityStatus.notHeard.color,
        ]
    }
}

// MARK: - CommunityWeekChart

/// Hourly stacked bars across the window with a "now" rule, your passes as
/// faint bands, and hold-to-scrub reading the selected hour's counts. The
/// x axis scrolls (drag) and zooms (pinch) between six hours and the full
/// window; double-tap resets.
struct CommunityWeekChart: View {
    // MARK: Internal

    let activity: CommunityActivity?
    let buckets: [CommunityActivityBucket]
    let passes: [SatellitePass]

    @Binding var selection: Date?

    var body: some View {
        GeometryReader { geo in
            chart
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: visibleSeconds)
                .chartScrollPosition(x: $scrollStart)
                .simultaneousGesture(magnify(width: max(geo.size.width - 40, 1)))
        }
        .onTapGesture(count: 2) {
            visibleSeconds = fullSpan
            scrollStart = domain.lowerBound
        }
        .onChange(of: activity?.windowEnd) { _, _ in
            visibleSeconds = fullSpan
            scrollStart = domain.lowerBound
        }
    }

    // MARK: Private

    @State private var visibleSeconds: TimeInterval = 7 * 86_400
    @State private var scrollStart = Date().addingTimeInterval(-7 * 86_400)
    @State private var pinchBaseSeconds: TimeInterval?

    @State private var pinchBaseStart: Date?

    private var fullSpan: TimeInterval {
        domain.upperBound.timeIntervalSince(domain.lowerBound)
    }

    private var points: [CommunityReportPoint] {
        CommunityReportPoint.points(from: buckets)
    }

    private var domain: ClosedRange<Date> {
        guard let activity else {
            return Date().addingTimeInterval(-7 * 86_400) ... Date()
        }
        return activity.windowStart ... activity.windowEnd
    }

    private var selectedBucket: CommunityActivityBucket? {
        guard let selection else {
            return nil
        }
        let hour = Date(timeIntervalSince1970: (selection.timeIntervalSince1970 / 3_600).rounded(.down) * 3_600)
        return buckets.first { $0.start == hour } ?? CommunityActivityBucket.quiet(at: hour)
    }

    private var chart: some View {
        Chart {
            ForEach(passes) { pass in
                RectangleMark(
                    xStart: .value("AOS", pass.aos),
                    xEnd: .value("LOS", pass.los.addingTimeInterval(max(0, 1_800 - pass.duration)))
                )
                .foregroundStyle(Color.orange.opacity(0.18))
            }
            ForEach(points) { point in
                BarMark(
                    x: .value("Hour", point.start, unit: .hour),
                    y: .value("Reports", point.reports)
                )
                .foregroundStyle(by: .value("Verdict", point.verdict))
            }
            if let now = activity?.windowEnd {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            if let selectedBucket {
                RuleMark(x: .value("Selected", selectedBucket.start.addingTimeInterval(1_800)))
                    .foregroundStyle(.primary.opacity(0.5))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit, y: .disabled)) {
                        CommunityHourCallout(bucket: selectedBucket)
                    }
            }
        }
        .chartForegroundStyleScale(CommunityChartStyle.colorScale)
        .chartLegend(position: .bottom, spacing: 6)
        .chartXScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
        .chartXSelection(value: $selection)
    }

    private func magnify(width: CGFloat) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.005)
            .onChanged { value in
                let baseSeconds = pinchBaseSeconds ?? visibleSeconds
                let baseStart = pinchBaseStart ?? scrollStart
                pinchBaseSeconds = baseSeconds
                pinchBaseStart = baseStart
                // Keep the date under the pinch's centre fixed on screen.
                let anchor = min(1, max(0, Double((value.startLocation.x - 32) / width)))
                let pivot = baseStart.addingTimeInterval(anchor * baseSeconds)
                let target = min(fullSpan, max(CommunityViewport.minimumSpan, baseSeconds / value.magnification))
                visibleSeconds = target
                let latestStart = domain.upperBound.addingTimeInterval(-target)
                scrollStart = max(domain.lowerBound, min(latestStart, pivot.addingTimeInterval(-anchor * target)))
            }
            .onEnded { _ in
                pinchBaseSeconds = nil
                pinchBaseStart = nil
            }
    }
}

// MARK: - CommunityHourCallout

/// The scrub readout: UTC hour and verdict counts.
struct CommunityHourCallout: View {
    // MARK: Internal

    let bucket: CommunityActivityBucket

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bucket.start, format: .dateTime.month(.abbreviated).day().hour(.twoDigits(amPM: .omitted)))
                .font(.caption2.weight(.semibold))
            Text(summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .current)
    }

    // MARK: Private

    private var summary: String {
        guard bucket.total > 0 else {
            return "no reports"
        }
        var parts = [String]()
        if bucket.heard + bucket.crew + bucket.other > 0 {
            parts.append("\(bucket.heard + bucket.crew + bucket.other) heard")
        }
        if bucket.telemetry > 0 {
            parts.append("\(bucket.telemetry) TLM")
        }
        if bucket.notHeard > 0 {
            parts.append("\(bucket.notHeard) not heard")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - CommunityHourOfDayChart

/// 24 stacked bars: reports per UTC hour of day summed over the week.
struct CommunityHourOfDayChart: View {
    // MARK: Internal

    let buckets: [CommunityActivityBucket]

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Hour", point.hour),
                y: .value("Reports", point.reports)
            )
            .foregroundStyle(by: .value("Verdict", point.verdict))
        }
        .chartForegroundStyleScale(CommunityChartStyle.colorScale)
        .chartLegend(.hidden)
        .chartXScale(domain: -0.5 ... 23.5)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(String(format: "%02dz", hour))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
    }

    // MARK: Private

    private struct HourPoint: Identifiable {
        let hour: Int
        let verdict: String
        let reports: Int

        var id: String {
            "\(hour)-\(verdict)"
        }
    }

    private var points: [HourPoint] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        var heard = [Int](repeating: 0, count: 24)
        var telemetry = [Int](repeating: 0, count: 24)
        var notHeard = [Int](repeating: 0, count: 24)
        for bucket in buckets {
            let hour = calendar.component(.hour, from: bucket.start)
            heard[hour] += bucket.heard + bucket.crew + bucket.other
            telemetry[hour] += bucket.telemetry
            notHeard[hour] += bucket.notHeard
        }
        return (0 ..< 24).flatMap { hour -> [HourPoint] in
            [
                HourPoint(hour: hour, verdict: CommunityActivityStatus.heard.label, reports: heard[hour]),
                HourPoint(hour: hour, verdict: CommunityActivityStatus.telemetryOnly.label, reports: telemetry[hour]),
                HourPoint(hour: hour, verdict: CommunityActivityStatus.notHeard.label, reports: notHeard[hour]),
            ]
            .filter { $0.reports > 0 }
        }
    }
}
