// External Data View - Equipment Catalog Section
//
// Shows download status and refresh controls for the
// equipment catalog cache from the activities server.

import CarrierWaveData
import SwiftUI

// MARK: - EquipmentCatalogCacheSection

/// Section showing equipment catalog cache status with refresh controls
struct EquipmentCatalogCacheSection: View {
    // MARK: Internal

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Equipment Catalog", systemImage: "wrench.and.screwdriver")
                        .font(.headline)

                    Spacer()

                    statusBadge
                }

                statusDetail

                if !catalogService.isLoading {
                    HStack {
                        Button {
                            Task { await refresh() }
                        } label: {
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            } else if entryCount > 0 {
                                Label("Refresh Now", systemImage: "arrow.clockwise")
                            } else {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRefreshing)

                        Spacer()
                    }
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text(
                "Equipment database from the Carrier Wave server used for "
                    + "catalog search when adding gear. Refreshed automatically every 24 hours."
            )
        }
        .task {
            await catalogService.loadAndRefresh()
            entryCount = catalogService.catalog.count
        }
    }

    // MARK: Private

    @State private var entryCount = 0
    @State private var isRefreshing = false

    private var catalogService = EquipmentCatalogService.shared

    @ViewBuilder
    private var statusBadge: some View {
        if catalogService.isLoading {
            ProgressView()
                .controlSize(.small)
        } else if entryCount > 0 {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        if catalogService.isLoading {
            Text("Downloading equipment catalog...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if entryCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entryCount) entries")
                    .font(.subheadline)

                if let date = catalogService.lastChecked {
                    HStack(spacing: 4) {
                        Text("Checked")
                        Text(date, style: .relative)
                        Text("ago")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if isStale(date) {
                        Text("Refresh recommended")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        } else {
            Text("Not downloaded")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func isStale(_ date: Date) -> Bool {
        let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        return date < oneDayAgo
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await catalogService.forceRefresh()
        entryCount = catalogService.catalog.count
    }
}
