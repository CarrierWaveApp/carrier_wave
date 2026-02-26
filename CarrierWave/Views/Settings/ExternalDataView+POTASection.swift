// External Data View - POTA Parks Section
//
// Shows download status and refresh controls for the POTA
// parks database cache.

import SwiftUI

// MARK: - POTACacheSection

/// Section showing POTA parks cache status with refresh controls
struct POTACacheSection: View {
    // MARK: Internal

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("POTA Parks", systemImage: "tree")
                        .font(.headline)

                    Spacer()

                    statusBadge
                }

                statusDetail

                if case .loaded = parksStatus {
                    HStack {
                        Button {
                            Task { await refreshParks() }
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
            }
            .padding(.vertical, 4)
        } header: {
            Text("Cached Data")
        } footer: {
            Text(
                "Park names are downloaded from pota.app and "
                    + "refreshed automatically every two weeks."
            )
        }
        .task {
            await loadStatus()
        }
    }

    // MARK: Private

    @State private var parksStatus: POTAParksCacheStatus = .notLoaded
    @State private var isRefreshing = false

    @ViewBuilder
    private var statusBadge: some View {
        switch parksStatus {
        case .notLoaded:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .loading,
             .downloading:
            ProgressView()
                .controlSize(.small)
        case .loaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch parksStatus {
        case .notLoaded:
            Text("Not downloaded")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .loading:
            Text("Loading from cache...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .downloading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading parks database...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case let .loaded(parkCount, downloadedAt):
            VStack(alignment: .leading, spacing: 4) {
                Text("\(parkCount.formatted()) parks")
                    .font(.subheadline)

                if let date = downloadedAt {
                    HStack(spacing: 4) {
                        Text("Downloaded")
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

        case let .failed(error):
            VStack(alignment: .leading, spacing: 4) {
                Text("Download failed")
                    .font(.subheadline)
                    .foregroundStyle(.orange)

                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Retry") {
                    Task { await refreshParks() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
    }

    private func isStale(_ date: Date) -> Bool {
        let twoWeeksAgo = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        return date < twoWeeksAgo
    }

    private func loadStatus() async {
        parksStatus = await POTAParksCache.shared.getStatus()

        if case .notLoaded = parksStatus {
            await POTAParksCache.shared.ensureLoaded()
            parksStatus = await POTAParksCache.shared.getStatus()
        }
    }

    private func refreshParks() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await POTAParksCache.shared.forceRefresh()
        } catch {
            // Status will be updated by the cache
        }

        parksStatus = await POTAParksCache.shared.getStatus()
    }
}
