// External Data View - WWFF References Section
//
// Shows download status and refresh controls for the WWFF
// directory reference database cache.

import CarrierWaveData
import SwiftUI

// MARK: - WWFFCacheSection

/// Section showing WWFF references cache status with refresh controls
struct WWFFCacheSection: View {
    // MARK: Internal

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("WWFF Directory", systemImage: "leaf.fill")
                        .font(.headline)

                    Spacer()

                    statusBadge
                }

                statusDetail

                if case .loaded = wwffStatus {
                    HStack {
                        Button {
                            Task { await refreshReferences() }
                        } label: {
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label(
                                    "Refresh Now",
                                    systemImage: "arrow.clockwise"
                                )
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
                "WWFF reference data is downloaded from wwff.co and "
                    + "refreshed automatically every 30 days."
            )
        }
        .task {
            await loadStatus()
        }
    }

    // MARK: Private

    @State private var wwffStatus: WWFFReferencesCacheStatus = .notLoaded
    @State private var isRefreshing = false

    @ViewBuilder
    private var statusBadge: some View {
        switch wwffStatus {
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
        switch wwffStatus {
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
                Text("Downloading WWFF directory...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case let .loaded(referenceCount, downloadedAt):
            VStack(alignment: .leading, spacing: 4) {
                Text("\(referenceCount.formatted()) references")
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
                    Task { await refreshReferences() }
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
        wwffStatus = await WWFFReferencesCache.shared.getStatus()

        if case .notLoaded = wwffStatus {
            await WWFFReferencesCache.shared.ensureLoaded()
            wwffStatus = await WWFFReferencesCache.shared.getStatus()
        }
    }

    private func refreshReferences() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await WWFFReferencesCache.shared.forceRefresh()
        } catch {
            // Status will be updated by the cache
        }

        wwffStatus = await WWFFReferencesCache.shared.getStatus()
    }
}
