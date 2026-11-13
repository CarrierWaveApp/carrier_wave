// External Data View - Contest Definitions Section
//
// Shows download status and refresh controls for the server-published
// contest definitions catalog fetched from `/v1/contests`.

import CarrierWaveData
import SwiftUI

// MARK: - ContestsCacheSection

struct ContestsCacheSection: View {
    // MARK: Internal

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Contests", systemImage: "trophy")
                        .font(.headline)
                    Spacer()
                    statusBadge
                }
                statusDetail
                if refresher.lastRefreshed != nil {
                    HStack {
                        Button {
                            Task { await refresher.refresh() }
                        } label: {
                            if refresher.isRefreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Refresh Now", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(refresher.isRefreshing)
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Contest Definitions")
        } footer: {
            Text(
                "Contest definitions (schedule, exchange, scoring, Cabrillo format) "
                    + "are downloaded from the activities server and refreshed automatically "
                    + "every 24 hours."
            )
        }
        .task {
            await refresher.loadFromCache()
            if refresher.summaries.isEmpty {
                await refresher.refresh()
            }
        }
    }

    // MARK: Private

    @State private var refresher = ContestDefinitionsRefresher()

    private var contestCount: Int {
        max(refresher.summaries.count, refresher.definitions.count)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if refresher.isRefreshing {
            ProgressView().controlSize(.small)
        } else if refresher.lastError != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if refresher.lastRefreshed != nil {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        if refresher.isRefreshing, refresher.lastRefreshed == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading contest catalog...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if let last = refresher.lastRefreshed {
            loadedDetail(lastRefreshed: last)
        } else if let error = refresher.lastError {
            failureDetail(error: error)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Not downloaded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Download Now") {
                    Task { await refresher.refresh() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
    }

    private func loadedDetail(lastRefreshed: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(contestCount.formatted()) contests")
                .font(.subheadline)
            HStack(spacing: 4) {
                Text("Downloaded")
                Text(lastRefreshed, style: .relative)
                Text("ago")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if isStale(lastRefreshed) {
                Text("Refresh recommended")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let error = refresher.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func failureDetail(error: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Download failed")
                .font(.subheadline)
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await refresher.refresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
    }

    private func isStale(_ date: Date) -> Bool {
        let cutoff = Date().addingTimeInterval(-ContestDefinitionsRefresher.automaticRefreshInterval)
        return date < cutoff
    }
}
