import MapKit
import SwiftUI

// MARK: - ContactMapEntry

/// Resolved contact grid with coordinate for map rendering.
struct ContactMapEntry {
    let grid: String
    let band: String
    let coord: CLLocationCoordinate2D
}

// MARK: - SessionBragSheetCard

/// Full brag sheet card for a completed session, displayed in the activity feed.
/// Renders map, stats, timeline, and equipment from ActivityDetails data.
/// Section views are in SessionBragSheetCard+Components.swift.
struct SessionBragSheetCard: View {
    // MARK: Internal

    let item: ActivityItem
    var onCallsignTap: ((String) -> Void)?
    var onShare: (() -> Void)?
    var onHide: (() -> Void)?
    var onDeleteFromServer: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            if !contactCoordinates.isEmpty, myCoordinate != nil {
                mapSection
            }
            sessionInfoSection
            statsSection
            if let timeline = item.details?.sessionTimeline, !timeline.isEmpty {
                SessionTimelineView(entries: timeline)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
            }
            if hasEquipment {
                equipmentSection
            }
            footerSection
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = false

    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.10, blue: 0.18),
                Color(red: 0.18, green: 0.12, blue: 0.25),
                Color(red: 0.12, green: 0.10, blue: 0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var headerSection: some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))

            if item.isOwn {
                Text(item.callsign)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text("You")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            } else if let onCallsignTap {
                Button {
                    onCallsignTap(item.callsign)
                } label: {
                    Text(item.callsign)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else {
                Text(item.callsign)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            Spacer()

            Text(item.timestamp, style: .relative)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - SessionTimelineView

/// Timeline view that works with compact TimelineEntry data instead of full QSO objects.
struct SessionTimelineView: View {
    // MARK: Internal

    let entries: [TimelineEntry]

    var body: some View {
        if entries.isEmpty {
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

    private var sortedEntries: [TimelineEntry] {
        entries.sorted { $0.timestamp < $1.timestamp }
    }

    private var uniqueBands: [String] {
        Array(Set(entries.map(\.band))).sorted()
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
            let barCenterY: CGFloat = 9
            let sorted = sortedEntries
            let positions = computePositions(sorted: sorted, width: width)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 3)
                    .position(x: width / 2, y: barCenterY)

                ForEach(Array(sorted.enumerated()), id: \.offset) { index, entry in
                    if let xPos = positions[index] {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(bandColor(entry.band))
                            .frame(width: 2, height: 14)
                            .position(x: xPos, y: barCenterY)
                    }
                }

                if let first = sorted.first, let last = sorted.last,
                   last.timestamp.timeIntervalSince(first.timestamp) > 60
                {
                    Text(Self.utcTimeFormatter.string(from: first.timestamp) + "z")
                        .font(.system(size: 8).monospaced())
                        .foregroundStyle(.white.opacity(0.5))
                        .position(x: 16, y: 24)

                    Text(Self.utcTimeFormatter.string(from: last.timestamp) + "z")
                        .font(.system(size: 8).monospaced())
                        .foregroundStyle(.white.opacity(0.5))
                        .position(x: width - 16, y: 24)
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

    private func computePositions(
        sorted: [TimelineEntry],
        width: CGFloat
    ) -> [Int: CGFloat] {
        guard sorted.count > 1,
              let first = sorted.first,
              let last = sorted.last
        else {
            if sorted.count == 1 {
                return [0: width / 2]
            }
            return [:]
        }

        let inset: CGFloat = 4
        let usable = width - inset * 2
        let totalDuration = last.timestamp.timeIntervalSince(first.timestamp)

        guard totalDuration > 0 else {
            return [0: width / 2]
        }

        var result: [Int: CGFloat] = [:]
        for (index, entry) in sorted.enumerated() {
            let fraction = entry.timestamp.timeIntervalSince(first.timestamp) / totalDuration
            result[index] = inset + CGFloat(fraction) * usable
        }
        return result
    }
}
