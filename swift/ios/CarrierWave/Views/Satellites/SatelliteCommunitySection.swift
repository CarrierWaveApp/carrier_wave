import SwiftUI

// MARK: - SatelliteCommunitySection

/// The community block on the selected satellite's info card: a week
/// sparkline per AMSAT capability (tap for the hour-by-hour page), last
/// heard, what the community saw on the previous orbit, and a Report
/// button that files the operator's own observation with AMSAT. Untracked
/// birds say so instead of showing nothing.
struct SatelliteCommunitySection: View {
    // MARK: Internal

    let amsatStatus: AmsatSatelliteStatus?
    let activity: CommunityActivity?
    let rows: [CommunityActivityRow]
    let reports: CommunityReports?
    let onOpen: (String) -> Void
    /// Opens the AMSAT report sheet for this bird (hidden when AMSAT
    /// doesn't track it).
    var onReport: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                CommunityDot(status: amsatStatus, size: 7)
                Text("Community")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let heard = amsatStatus?.lastHeardAt {
                    Text("heard \(CommunityFormat.ago(from: heard))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let onReport, !rows.isEmpty {
                    Button(action: onReport) {
                        Label("Report", systemImage: "square.and.pencil")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .accessibilityLabel("Report this satellite's status to AMSAT")
                }
            }
            if let activity, !rows.isEmpty {
                ForEach(rows) { row in
                    Button {
                        onOpen(row.id)
                    } label: {
                        capabilityRow(row, viewport: CommunityViewport(activity: activity))
                    }
                    .buttonStyle(.plain)
                }
            } else if amsatStatus == nil {
                Text("Not tracked on AMSAT's status page")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Loading this week's reports…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let orbit = reports?.previousOrbit {
                HStack(spacing: 4) {
                    Circle()
                        .fill(orbit.status.color)
                        .frame(width: 6, height: 6)
                    Text(orbit.line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 2)
    }

    // MARK: Private

    private func capabilityRow(_ row: CommunityActivityRow, viewport: CommunityViewport) -> some View {
        HStack(spacing: 6) {
            Text(row.capability ?? "—")
                .font(.caption2.weight(.medium).monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
                .lineLimit(1)
            CommunityStripView(viewport: viewport, buckets: row.buckets)
                .frame(height: 18)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(row.capability ?? "transmitter"): " + (row.heardInWindow ? "heard this week" : "not heard this week")
        )
        .accessibilityHint("Opens the hour-by-hour community history")
    }
}
