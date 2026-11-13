import CarrierWaveData
import SwiftUI

// MARK: - PendingUploadRow

/// Row displaying a single pending QSO with its reason and affected services.
struct PendingUploadRow: View {
    // MARK: Internal

    let item: PendingUploadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerLine
            reasonLine
            if !item.detail.isEmpty {
                detailLine
            }
            servicesLine
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    private var headerLine: some View {
        HStack(spacing: 6) {
            Text(item.callsign)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(item.band)
                .font(.caption)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.15))
                .clipShape(Capsule())

            Text(item.mode)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(item.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var reasonLine: some View {
        Label(item.reason.title, systemImage: item.reason.iconName)
            .font(.caption)
            .foregroundStyle(item.reason.isActionable ? .orange : .secondary)
    }

    private var detailLine: some View {
        Text(item.detail)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.leading, 20)
    }

    private var servicesLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(item.services, id: \.self) { service in
                Text(service.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}
