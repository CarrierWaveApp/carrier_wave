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
        .alert(
            "Delete QSO",
            isPresented: Binding(
                get: { qsoToDelete != nil },
                set: { newValue in
                    if !newValue {
                        qsoToDelete = nil
                    }
                }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let qso = qsoToDelete {
                    deleteQSO(qso)
                }
                qsoToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                qsoToDelete = nil
            }
        } message: {
            if let qso = qsoToDelete {
                Text("Delete QSO with \(qso.callsign)?")
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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    @State private var editingQSO: QSO?
    @State private var qsoToDelete: QSO?

    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var dividerHeight: CGFloat = 28

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var dividerCount: Int {
        recentQSOs.indices.filter { shouldShowDivider(at: $0) }.count
    }

    private var qsoListContent: some View {
        List {
            ForEach(Array(recentQSOs.enumerated()), id: \.element.id) { index, qso in
                Button {
                    editingQSO = qso
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        if shouldShowDivider(at: index) {
                            stationGridDivider(for: qso)
                        }
                        recentQSORow(qso)
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(.secondary.opacity(0.3))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        qsoToDelete = qso
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .frame(
            height: rowHeight * CGFloat(recentQSOs.count)
                + dividerHeight * CGFloat(dividerCount)
        )
    }

    private func stationGridDivider(for qso: QSO) -> some View {
        let profileName = qso.stationProfileName ?? manager?.currentProfile?.name
        return HStack(spacing: 4) {
            Image(systemName: "location.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let name = profileName {
                Text(name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if profileName != nil, qso.myGrid != nil {
                Text("\u{00B7}")
                    .foregroundStyle(.tertiary)
            }
            if let grid = qso.myGrid {
                Text(grid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: dividerHeight)
        .accessibilityElement(children: .combine)
    }

    private func recentQSORow(_ qso: QSO) -> some View {
        HStack(spacing: 8) {
            // Time (UTC)
            Text(formattedTime(qso.timestamp))
                .font(isRegularWidth ? .subheadline.monospaced() : .caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: isRegularWidth ? 56 : 42, alignment: .leading)

            // Callsign
            Text(qso.callsign)
                .font(
                    isRegularWidth
                        ? .headline.weight(.semibold).monospaced()
                        : .subheadline.weight(.semibold).monospaced()
                )
                .lineLimit(1)

            Spacer()

            // Band + Mode badge
            Text("\(qso.band) \(qso.mode)")
                .font(isRegularWidth ? .subheadline.weight(.medium) : .caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())

            // Their park reference if present
            if let park = qso.theirParkReference, !park.isEmpty {
                Text(park)
                    .font(isRegularWidth ? .subheadline.monospaced() : .caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // RST sent
            Text(qso.rstSent ?? "599")
                .font(isRegularWidth ? .caption.monospaced() : .caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: rowHeight)
        .contentShape(Rectangle())
    }

    private func shouldShowDivider(at index: Int) -> Bool {
        let qso = recentQSOs[index]
        guard qso.stationProfileName != nil || qso.myGrid != nil else {
            return false
        }
        // Always show for newest (top) and oldest (bottom) QSO
        if index == 0 || index == recentQSOs.count - 1 {
            return true
        }
        let prev = recentQSOs[index - 1]
        return qso.stationProfileName != prev.stationProfileName
            || qso.myGrid != prev.myGrid
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
