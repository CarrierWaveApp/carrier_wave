// External Data View - SOTA Summits Section
//
// Shows download status and refresh controls for the SOTA
// summits database cache.

import SwiftUI

// MARK: - SOTACacheSection

/// Section showing SOTA summits cache status with refresh controls
struct SOTACacheSection: View {
    // MARK: Internal

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("SOTA Summits", systemImage: "mountain.2")
                        .font(.headline)

                    Spacer()

                    statusBadge
                }

                statusDetail

                if case .loaded = summitsStatus {
                    HStack {
                        Button {
                            Task { await refreshSummits() }
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
        } footer: {
            Text(
                "Summit data is downloaded from sotadata.org.uk and "
                    + "refreshed automatically every 30 days."
            )
        }
        .task {
            await loadStatus()
        }
    }

    // MARK: Private

    @State private var summitsStatus: SOTASummitsCacheStatus = .notLoaded
    @State private var isRefreshing = false

    @ViewBuilder
    private var statusBadge: some View {
        switch summitsStatus {
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
        switch summitsStatus {
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
                Text("Downloading summits database...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case let .loaded(summitCount, downloadedAt):
            VStack(alignment: .leading, spacing: 4) {
                Text("\(summitCount.formatted()) summits")
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
                    Task { await refreshSummits() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
    }

    private func isStale(_ date: Date) -> Bool {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        return date < thirtyDaysAgo
    }

    private func loadStatus() async {
        summitsStatus = await SOTASummitsCache.shared.getStatus()

        if case .notLoaded = summitsStatus {
            await SOTASummitsCache.shared.ensureLoaded()
            summitsStatus = await SOTASummitsCache.shared.getStatus()
        }
    }

    private func refreshSummits() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await SOTASummitsCache.shared.forceRefresh()
        } catch {
            // Status will be updated by the cache
        }

        summitsStatus = await SOTASummitsCache.shared.getStatus()
    }
}
