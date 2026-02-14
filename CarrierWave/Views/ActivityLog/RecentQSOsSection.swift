import SwiftData
import SwiftUI

// MARK: - RecentQSOsSection

/// Shows the last few QSOs logged today from the activity log.
/// Uses pre-fetched QSOs (no @Query — performance rules).
struct RecentQSOsSection: View {
    // MARK: Internal

    let recentQSOs: [QSO]
    var manager: ActivityLogManager?
    var onQSOChanged: (() -> Void)?

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
            .padding(.horizontal)
            .padding(.top)

            if recentQSOs.isEmpty {
                Text("No QSOs logged today")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .padding(.horizontal)
            } else {
                qsoListContent
            }
        }
        .padding(.bottom)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(item: $editingQSO) { qso in
            QSOEditSheet(qso: qso) {
                onQSOChanged?()
            }
        }
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @Environment(\.modelContext) private var modelContext

    @State private var editingQSO: QSO?

    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 44

    private var qsoListContent: some View {
        List {
            ForEach(recentQSOs) { qso in
                Button {
                    editingQSO = qso
                } label: {
                    recentQSORow(qso)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(.secondary.opacity(0.3))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteQSO(qso)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .frame(height: rowHeight * CGFloat(recentQSOs.count))
    }

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
        .frame(minHeight: rowHeight)
        .contentShape(Rectangle())
    }

    private func formattedTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func deleteQSO(_ qso: QSO) {
        qso.isHidden = true
        try? modelContext.save()
        onQSOChanged?()
    }
}
