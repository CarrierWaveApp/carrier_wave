import SwiftUI

// MARK: - RecentQSOsSection

/// Shows the last few QSOs logged today from the activity log.
/// Uses pre-fetched QSOs (no @Query — performance rules).
struct RecentQSOsSection: View {
    // MARK: Internal

    let recentQSOs: [QSO]
    var manager: ActivityLogManager?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent QSOs")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !recentQSOs.isEmpty, let manager {
                    NavigationLink("See All") {
                        DailySummaryView(manager: manager)
                    }
                    .font(.caption)
                }
            }

            if recentQSOs.isEmpty {
                Text("No QSOs logged today")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(recentQSOs) { qso in
                    recentQSORow(qso)
                    if qso.id != recentQSOs.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private func recentQSORow(_ qso: QSO) -> some View {
        HStack(spacing: 8) {
            // Time (UTC)
            Text(formattedTime(qso.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            // Callsign
            Text(qso.callsign)
                .font(.subheadline.weight(.semibold).monospaced())
                .lineLimit(1)

            Spacer()

            // Band + Mode badge
            Text("\(qso.band) \(qso.mode)")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())

            // Their park reference if present
            if let park = qso.theirParkReference, !park.isEmpty {
                Text(park)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // RST sent
            Text(qso.rstSent ?? "599")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func formattedTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}
