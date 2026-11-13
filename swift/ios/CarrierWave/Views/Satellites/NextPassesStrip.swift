import SwiftUI

// MARK: - NextPassesStrip

/// The primary planning unit, per the satellite-workflow research: the next
/// few workable passes (favorites first), leading the bottom overlay above
/// the exploration-candy time scrubber. Tap a chip to select that bird.
struct NextPassesStrip: View {
    // MARK: Internal

    /// Already filtered/ordered by the root view (favorites, ≥20°, soonest).
    let passes: [UpcomingSatellitePass]
    let onSelect: (Int) -> Void

    var body: some View {
        if !passes.isEmpty {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                HStack(spacing: 8) {
                    ForEach(passes) { item in
                        chip(item, now: timeline.date)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Private

    private func chip(_ item: UpcomingSatellitePass, now: Date) -> some View {
        Button {
            onSelect(item.noradID)
        } label: {
            HStack(spacing: 6) {
                Text(item.name)
                    .font(.caption.weight(.semibold).monospaced())
                    .lineLimit(1)
                Text(countdown(for: item, now: now))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(item.pass.isInProgress(at: now) ? .green : .secondary)
                Text(String(format: "%.0f°", item.pass.peakElevationDeg))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(item.name), \(countdown(for: item, now: now)), "
                + "peaks \(Int(item.pass.peakElevationDeg)) degrees"
        )
    }

    private func countdown(for item: UpcomingSatellitePass, now: Date) -> String {
        if item.pass.isInProgress(at: now) {
            return "now"
        }
        let minutes = max(Int(item.pass.aos.timeIntervalSince(now) / 60), 1)
        if minutes < 60 {
            return "in \(minutes)m"
        }
        return "in \(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }
}
