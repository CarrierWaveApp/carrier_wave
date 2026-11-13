// Needs Widget
//
// Home screen widget showing operator needs currently on the air.
// Displays matched spots from the latest fetch cycle.

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - NeedsWidgetEntry

struct NeedsWidgetEntry: TimelineEntry {
    let date: Date
    let matchedSpots: [NeedsWidgetSpot]
    let summaryText: String
    let totalMatches: Int
}

// MARK: - NeedsWidgetSpot

struct NeedsWidgetSpot: Identifiable {
    let id: String
    let callsign: String
    let frequencyMHz: Double
    let mode: String
    let needLabel: String
    let priorityRaw: Int
    let timeAgo: String
}

// MARK: - NeedsTimelineProvider

struct NeedsTimelineProvider: TimelineProvider {
    // MARK: Internal

    func placeholder(in _: Context) -> NeedsWidgetEntry {
        NeedsWidgetEntry(
            date: Date(),
            matchedSpots: [],
            summaryText: "Checking for needs...",
            totalMatches: 0
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NeedsWidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<NeedsWidgetEntry>) -> Void) {
        // Widget reads from shared UserDefaults written by the app
        let spots = loadCachedNeedsSpots()
        let summary = spots.isEmpty
            ? "No needs on the air"
            : "\(spots.count) spot\(spots.count == 1 ? "" : "s") matching your needs"

        let entry = NeedsWidgetEntry(
            date: Date(),
            matchedSpots: Array(spots.prefix(8)),
            summaryText: summary,
            totalMatches: spots.count
        )

        let nextUpdate = Date().addingTimeInterval(5 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    // MARK: Private

    private func loadCachedNeedsSpots() -> [NeedsWidgetSpot] {
        guard let defaults = UserDefaults(suiteName: WidgetShared.appGroupID),
              let data = defaults.data(forKey: "needsWidgetSpots"),
              let decoded = try? JSONDecoder().decode(
                  [NeedsWidgetSpotData].self, from: data
              )
        else {
            return []
        }

        let now = Date()
        return decoded.map { spot in
            let age = now.timeIntervalSince(spot.timestamp)
            let timeAgo = if age < 60 {
                "<1m"
            } else if age < 3_600 {
                "\(Int(age / 60))m"
            } else {
                "\(Int(age / 3_600))h"
            }

            return NeedsWidgetSpot(
                id: spot.id,
                callsign: spot.callsign,
                frequencyMHz: spot.frequencyMHz,
                mode: spot.mode,
                needLabel: spot.needLabel,
                priorityRaw: spot.priority,
                timeAgo: timeAgo
            )
        }
    }
}

// MARK: - NeedsWidgetSpotData

/// Codable transport for sharing between app and widget.
struct NeedsWidgetSpotData: Codable {
    let id: String
    let callsign: String
    let frequencyMHz: Double
    let mode: String
    let needLabel: String
    let priority: Int
    let timestamp: Date
}

// MARK: - NeedsWidgetView

struct NeedsWidgetView: View {
    // MARK: Internal

    let entry: NeedsWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            if entry.matchedSpots.isEmpty {
                emptyState
            } else {
                spotList
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    private var headerRow: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(.yellow)
            Text("Needs On Air")
                .font(.caption2.weight(.semibold))
            Spacer()
            if entry.totalMatches > 0 {
                Text("\(entry.totalMatches)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No needs on the air")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var spotList: some View {
        VStack(spacing: 2) {
            ForEach(entry.matchedSpots) { spot in
                HStack(spacing: 6) {
                    priorityDot(spot.priorityRaw)
                    Text(spot.callsign)
                        .font(.caption.weight(.semibold).monospaced())
                        .lineLimit(1)
                    Text(spot.needLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(spot.timeAgo)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func priorityDot(_ priority: Int) -> some View {
        Circle()
            .fill(priority >= 2 ? .blue : priority >= 1 ? .purple : .teal)
            .frame(width: 6, height: 6)
    }
}

// MARK: - NeedsWidget

struct NeedsWidget: Widget {
    let kind = "NeedsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: NeedsTimelineProvider()
        ) { entry in
            NeedsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: WidgetShared.DeepLink.activityLog))
        }
        .configurationDisplayName("Needs On Air")
        .description("Spots matching your DXCC, WAS, POTA, and custom needs.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
