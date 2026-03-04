import CarrierWaveData
import SwiftUI

struct StatItemRow: View {
    // MARK: Internal

    let item: StatCategoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row - tappable
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                    if !isExpanded {
                        visibleQSOCount = batchSize
                    }
                }
            } label: {
                headerRow
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
        .task {
            if let parkRef = item.parkReference {
                parkName = await POTAParksCache.shared.name(for: parkRef)
            }
        }
    }

    // MARK: Private

    @State private var isExpanded = false
    @State private var visibleQSOCount = 5
    @State private var parkName: String?

    private let batchSize = 5

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.identifier)
                    .font(.headline)
                Spacer()
                Text("\(item.count)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let name = parkName {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !item.description.isEmpty {
                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.top, 8)

            ForEach(item.qsos.prefix(visibleQSOCount)) { qso in
                qsoRow(qso)
            }

            if visibleQSOCount < item.qsos.count {
                HStack(spacing: 16) {
                    Button {
                        withAnimation {
                            visibleQSOCount += batchSize
                        }
                    } label: {
                        HStack {
                            Image(systemName: "ellipsis")
                            Text("Show more")
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }

                    Button {
                        withAnimation {
                            visibleQSOCount = item.qsos.count
                        }
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("Show all (\(item.qsos.count - visibleQSOCount))")
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.leading, 16)
    }

    private func qsoRow(_ qso: QSO) -> some View {
        HStack {
            Text(qso.callsign)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Text(qso.band)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .clipShape(Capsule())

            Text(qso.mode)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(qso.timestamp, style: .date)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
