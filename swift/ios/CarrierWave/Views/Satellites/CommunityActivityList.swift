import SwiftUI

// MARK: - CommunityActivityList

/// Phone-first layout of the AMSAT grid: a plain vertical list, one row
/// per transmitter, each carrying the visible slice of the week as a
/// full-width strip (oldest left, newest right). Pinch anywhere to zoom
/// every strip together, drag sideways to pan, and the pinned day axis
/// follows. Tap a row for the hour-by-hour history.
struct CommunityActivityList: View {
    // MARK: Internal

    let activity: CommunityActivity
    let rows: [CommunityActivityRow]
    let favorites: Set<Int>

    @Binding var viewport: CommunityViewport

    var body: some View {
        GeometryReader { geo in
            List {
                Section {
                    ForEach(rows) { row in
                        NavigationLink(value: row.id) {
                            CommunityRowView(
                                viewport: viewport,
                                row: row,
                                isFavorite: row.noradID.map(favorites.contains) ?? false
                            )
                        }
                    }
                } header: {
                    CommunityTimelineAxis(viewport: viewport)
                        .frame(height: 16)
                        .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.plain)
            .simultaneousGesture(magnify(width: max(geo.size.width - 32, 1)))
            .simultaneousGesture(pan(width: max(geo.size.width - 32, 1)))
        }
    }

    // MARK: Private

    /// Viewport at the start of the current pinch (zoom is relative to it).
    @State private var pinchBase: CommunityViewport?
    /// Viewport at the start of the current drag, and whether the drag has
    /// committed to the horizontal axis (vertical drags scroll the list).
    @State private var panBase: CommunityViewport?
    @State private var panIsHorizontal: Bool?

    private func magnify(width: CGFloat) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.005)
            .onChanged { value in
                let base = pinchBase ?? viewport
                pinchBase = base
                // Keep the date under the pinch's centre fixed on screen.
                let anchor = min(1, max(0, Double((value.startLocation.x - 16) / width)))
                viewport = base.zoomed(by: value.magnification, anchor: anchor, activity: activity)
            }
            .onEnded { _ in
                pinchBase = nil
            }
    }

    private func pan(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if panIsHorizontal == nil {
                    panIsHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                }
                guard panIsHorizontal == true else {
                    return
                }
                let base = panBase ?? viewport
                panBase = base
                // Dragging right reveals earlier time.
                let fraction = -Double(value.translation.width / width)
                viewport = base.panned(byFraction: fraction, activity: activity)
            }
            .onEnded { _ in
                panBase = nil
                panIsHorizontal = nil
            }
    }
}

// MARK: - CommunityRowView

/// Name + capability + mode badge, the enrichment line, then the strip.
struct CommunityRowView: View {
    // MARK: Internal

    let viewport: CommunityViewport
    let row: CommunityActivityRow
    let isFavorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(row.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(row.inCatalog ? .primary : .secondary)
                if let capability = row.capability {
                    Text(capability)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                SatelliteModeBadge(mode: row.badgeMode)
            }
            Text(detailLine)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(row.nextPass != nil ? Color.orange : Color.secondary)
                .lineLimit(1)
            CommunityStripView(viewport: viewport, buckets: row.buckets)
                .frame(height: 26)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Private

    private var detailLine: String {
        var parts = [String]()
        if let pass = row.nextPass {
            parts.append("▲ \(CommunityFormat.countdown(to: pass.aos)) · \(Int(pass.peakElevationDeg.rounded()))°")
        } else if !row.inCatalog {
            parts.append("not in catalog")
        } else if row.transmitterActive == false {
            parts.append("SatNOGS: inactive")
        }
        if row.myQSOCount > 0 {
            parts.append("\(row.myQSOCount) QSO\(row.myQSOCount == 1 ? "" : "s")")
        }
        if let heard = row.lastHeardAt {
            parts.append("heard \(CommunityFormat.ago(from: heard))")
        } else if parts.isEmpty, let downlink = row.downlinkLow {
            parts.append(String(format: "%.3f MHz", Double(downlink) / 1_000_000))
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var text = row.displayName
        if let capability = row.capability {
            text += ", \(capability)"
        }
        text += row.heardInWindow ? ", heard this week" : ", not heard this week"
        if row.myQSOCount > 0 {
            text += ", \(row.myQSOCount) of your QSOs"
        }
        return text
    }
}

// MARK: - CommunityStripView

/// The visible slice of the week as a sparkline that always fits its
/// width: one stacked bar per engine bucket at its fractional position
/// (oldest left), height = report count against the row's busiest bucket
/// in the whole window (so zooming doesn't rescale bars), segments in the
/// legend colours. Quiet buckets leave a hairline baseline.
struct CommunityStripView: View {
    let viewport: CommunityViewport
    let buckets: [CommunityActivityBucket]

    var body: some View {
        Canvas { context, size in
            let span = viewport.span
            guard span > 0 else {
                return
            }
            let barWidth = CGFloat(viewport.bucketSeconds / span) * size.width
            let gap: CGFloat = barWidth > 8 ? 2 : (barWidth > 3 ? 1 : 0.5)
            let peak = CGFloat(max(1, buckets.map(\.total).max() ?? 1))
            let unit = (size.height - 2) / peak
            let baseline = CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)
            context.fill(Path(baseline), with: .color(Color(.systemGray5)))
            for bucket in buckets where bucket.total > 0 {
                let x = CGFloat(viewport.fraction(of: bucket.start)) * size.width + gap / 2
                let width = max(barWidth - gap, 0.5)
                guard x + width > 0, x < size.width else {
                    continue
                }
                var top = size.height - 1
                // Stack order bottom→top: heard, telemetry, not heard.
                let segments: [(Int, CommunityActivityStatus)] = [
                    (bucket.heard + bucket.crew + bucket.other, .heard),
                    (bucket.telemetry, .telemetryOnly),
                    (bucket.notHeard, .notHeard),
                ]
                for (value, status) in segments where value > 0 {
                    let height = max(CGFloat(value) * unit, 1.5)
                    let rect = CGRect(x: x, y: top - height, width: width, height: height)
                    context.fill(Path(rect), with: .color(status.color))
                    top -= height
                }
                if barWidth >= 22 {
                    let label = Text("\(bucket.total)")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    context.draw(label, at: CGPoint(x: x + width / 2, y: 5))
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - CommunityTimelineAxis

/// Day labels over the strips for the visible slice: a tick + "Oct 7" at
/// each UTC midnight (hour labels once zoomed in past two days), "now" at
/// the right edge when the newest bucket is on screen.
struct CommunityTimelineAxis: View {
    // MARK: Internal

    let viewport: CommunityViewport

    var body: some View {
        Canvas { context, size in
            let span = viewport.span
            guard span > 0 else {
                return
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            let hourly = span <= 2 * 86_400
            let stepHours = hourly ? (span <= 12 * 3_600 ? 1 : 6) : 24
            let formatter = DateFormatter()
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = hourly ? "HH'z'" : "MMM d"
            let minimumGap: CGFloat = hourly ? 30 : 40
            var lastX: CGFloat = -minimumGap
            var tick = calendar.startOfDay(for: viewport.start)
            while tick <= viewport.end {
                defer {
                    tick = calendar.date(byAdding: .hour, value: stepHours, to: tick)
                        ?? viewport.end.addingTimeInterval(1)
                }
                guard tick >= viewport.start else {
                    continue
                }
                let x = CGFloat(tick.timeIntervalSince(viewport.start) / span) * size.width
                var mark = Path()
                mark.move(to: CGPoint(x: x, y: size.height - 3))
                mark.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(mark, with: .color(.secondary), lineWidth: 1)
                guard x - lastX >= minimumGap, x < size.width - minimumGap else {
                    continue
                }
                lastX = x
                let isMidnight = calendar.component(.hour, from: tick) == 0
                let text = hourly && isMidnight
                    ? Self.dayFormatter.string(from: tick)
                    : formatter.string(from: tick)
                let label = Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                context.draw(label, at: CGPoint(x: x + 2, y: size.height / 2), anchor: .leading)
            }
            if viewport.showsNow {
                let now = Text("now")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                context.draw(now, at: CGPoint(x: size.width - 1, y: size.height / 2), anchor: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .background(.bar)
        .accessibilityHidden(true)
    }

    // MARK: Private

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

// MARK: - CommunityFormat

/// Small formatting helpers shared by the list and detail views.
enum CommunityFormat {
    /// "in 42m" / "in 3h 05m" / "now" when the pass is in progress.
    static func countdown(to date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 {
            return "now"
        }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return hours > 0 ? String(format: "in %dh %02dm", hours, minutes) : "in \(minutes)m"
    }

    /// "12m ago" / "3h ago" / "2d ago".
    static func ago(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 3_600 {
            return "\(max(1, seconds / 60))m ago"
        }
        if seconds < 48 * 3_600 {
            return "\(seconds / 3_600)h ago"
        }
        return "\(seconds / 86_400)d ago"
    }

    /// Frequency in MHz with kHz precision.
    static func mhz(_ hz: Int64) -> String {
        String(format: "%.3f MHz", Double(hz) / 1_000_000)
    }
}
