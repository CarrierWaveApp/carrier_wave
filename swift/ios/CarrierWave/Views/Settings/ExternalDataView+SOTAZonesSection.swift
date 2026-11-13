// External Data View - SOTA Activation Zones Section
//
// Bulk-prefetch status and refresh controls for the SOTA activation-zone
// cache (Rust reference-data core). Mirrors SOTACacheSection's layout;
// surfaces the "still computing on server" counter so users know when to
// refresh again.

import CarrierWaveData
import SwiftUI

// MARK: - SOTAZonesCacheSection

struct SOTAZonesCacheSection: View {
    // MARK: Internal

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("SOTA Activation Zones", systemImage: "triangle.fill")
                        .font(.headline)

                    Spacer()

                    statusBadge
                }

                statusDetail

                if case .loaded = zonesStatus {
                    refreshRow
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text(
                "Zones are computed server-side from open DEM data and cached "
                    + "on device. Refreshes only request summits without a "
                    + "cached zone, so repeat the refresh until nothing is "
                    + "still computing."
            )
        }
        .task {
            await loadStatus()
        }
    }

    // MARK: Private

    @State private var zonesStatus: ReferenceCacheStatus = .notLoaded
    @State private var isRefreshing = false
    @State private var pendingCount = 0

    @ViewBuilder
    private var statusBadge: some View {
        switch zonesStatus {
        case .notLoaded:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .loading,
             .downloading:
            ProgressView()
                .controlSize(.small)
        case .loaded:
            if pendingCount > 0 {
                Image(systemName: "ellipsis.circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch zonesStatus {
        case .notLoaded:
            VStack(alignment: .leading, spacing: 8) {
                Text("Not downloaded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await refreshZones() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Download Now", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
            }

        case .loading:
            Text("Loading from cache...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .downloading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading zones...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case let .loaded(zoneCount, downloadedAt):
            loadedDetail(zoneCount: zoneCount, downloadedAt: downloadedAt)

        case let .failed(error):
            failedDetail(error: error)
        }
    }

    private var refreshRow: some View {
        HStack {
            Button {
                Task { await refreshZones() }
            } label: {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Refresh Now", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)

            Spacer()
        }
    }

    private func loadedDetail(zoneCount: Int, downloadedAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(zoneCount.formatted()) zones")
                .font(.subheadline)

            if let date = downloadedAt {
                HStack(spacing: 4) {
                    Text("Downloaded")
                    Text(date, style: .relative)
                    Text("ago")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if pendingCount > 0 {
                Text(
                    "\(pendingCount.formatted()) still computing on server "
                        + "— tap Refresh again later."
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private func failedDetail(error: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Refresh failed")
                .font(.subheadline)
                .foregroundStyle(.orange)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Retry") {
                Task { await refreshZones() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
    }

    private func loadStatus() async {
        await SOTAZonesCache.shared.ensureLoaded()
        zonesStatus = await SOTAZonesCache.shared.getStatus()
        pendingCount = await SOTAZonesCache.shared.getPendingCount()
    }

    private func refreshZones() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await SOTAZonesCache.shared.forceRefresh()
        } catch {
            // Status reflects the failure.
        }

        zonesStatus = await SOTAZonesCache.shared.getStatus()
        pendingCount = await SOTAZonesCache.shared.getPendingCount()
    }
}
