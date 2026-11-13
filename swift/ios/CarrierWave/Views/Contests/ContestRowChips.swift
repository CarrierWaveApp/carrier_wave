import CarrierWaveData
import SwiftUI

// MARK: - ContestChip

/// Compact pill-style chip used to show contest metadata (mode, band,
/// duration, etc.). Sized to look right at `.caption2` font size.
struct ContestChip: View {
    let text: String
    var color: Color = .secondary
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .medium))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - ContestChipRow

/// Horizontal strip of chips extracted from a contest's enrichment.
struct ContestChipRow: View {
    // MARK: Internal

    let contest: Contest
    var showTemplateMatch: Bool = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if showTemplateMatch, contest.isActive, contest.enrichment.matchedTemplateId != nil {
                    ContestChip(
                        text: "Log Now",
                        color: .green,
                        systemImage: "record.circle"
                    )
                }

                if let popularity = contest.enrichment.popularity {
                    ContestChip(
                        text: String(repeating: "●", count: popularity),
                        color: popularityColor(popularity)
                    )
                }

                ForEach(contest.enrichment.modes, id: \.self) { mode in
                    ContestChip(
                        text: mode,
                        color: ModeColors.color(for: mode),
                        systemImage: "waveform"
                    )
                }

                if let summary = contest.enrichment.bandSummary {
                    ContestChip(
                        text: summary,
                        color: .blue,
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                } else if !contest.enrichment.bands.isEmpty {
                    ContestChip(
                        text: bandsCompact(contest.enrichment.bands),
                        color: .blue,
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                }

                ContestChip(
                    text: contest.durationLabel,
                    color: .purple,
                    systemImage: "clock"
                )

                if contest.enrichment.category != .unknown {
                    ContestChip(
                        text: contest.enrichment.category.displayLabel,
                        color: .orange
                    )
                }
            }
        }
    }

    // MARK: Private

    private func bandsCompact(_ bands: [String]) -> String {
        // Render all-HF lists as compact ranges: 80-10m etc.
        if bands.count >= 4 {
            return "\(bands.count) bands"
        }
        return bands.joined(separator: "·")
    }

    private func popularityColor(_ tier: Int) -> Color {
        switch tier {
        case 5: .red
        case 4: .orange
        case 3: .yellow
        case 2: .blue
        default: .gray
        }
    }
}

// MARK: - ContestCountdownLabel

/// Live-updating countdown label showing "Starts in 2h 14m" or
/// "3h 47m left". Ticks once per minute via a TimelineView.
struct ContestCountdownLabel: View {
    // MARK: Internal

    let contest: Contest

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(phrase(now: context.date))
                .font(.caption2)
                .foregroundStyle(color(now: context.date))
                .monospacedDigit()
        }
    }

    // MARK: Private

    private static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let mins = (total % 3_600) / 60
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    private func phrase(now: Date) -> String {
        if contest.isActive {
            let remaining = contest.endDate.timeIntervalSince(now)
            return "\(Self.format(remaining)) left"
        }
        if now < contest.startDate {
            let until = contest.startDate.timeIntervalSince(now)
            return "in \(Self.format(until))"
        }
        return "Ended \(contest.formattedEnd)"
    }

    private func color(now: Date) -> Color {
        if contest.isActive {
            let remaining = contest.endDate.timeIntervalSince(now)
            return remaining < 7_200 ? .orange : .green
        }
        if now < contest.startDate {
            let until = contest.startDate.timeIntervalSince(now)
            return until < 3_600 ? .orange : Color(.tertiaryLabel)
        }
        return Color(.tertiaryLabel)
    }
}

// MARK: - ContestProgressBar

/// Thin progress bar showing how much of an active contest is complete.
struct ContestProgressBar: View {
    // MARK: Internal

    let contest: Contest

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(barColor)
                        .frame(width: geo.size.width * (contest.progress ?? 0))
                }
            }
            .frame(height: 3)
        }
        .frame(height: 3)
    }

    // MARK: Private

    private var barColor: Color {
        guard let remaining = contest.timeRemaining else {
            return .green
        }
        return remaining < 7_200 ? .orange : .green
    }
}
