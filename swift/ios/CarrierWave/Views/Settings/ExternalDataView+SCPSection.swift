// External Data View - SCP Section
//
// Shows download status and refresh controls for the Super
// Check Partial callsign database cache.

import CarrierWaveData
import SwiftUI

// MARK: - SCPCacheSection

/// Section showing SCP database cache status with refresh controls
struct SCPCacheSection: View {
    // MARK: Internal

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Super Check Partial", systemImage: "magnifyingglass")
                        .font(.headline)

                    Spacer()

                    statusBadge
                }

                statusDetail

                if callsignCount > 0, !scpService.isLoading {
                    HStack {
                        Button {
                            Task { await refresh() }
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
                "Callsign database from supercheckpartial.com used for "
                    + "real-time suggestions while logging. Refreshed automatically every 7 days."
            )
        }
        .task {
            callsignCount = scpService.database.count
        }
    }

    // MARK: Private

    @State private var callsignCount = 0
    @State private var isRefreshing = false

    private var scpService = SCPService.shared

    @ViewBuilder
    private var statusBadge: some View {
        if scpService.isLoading {
            ProgressView()
                .controlSize(.small)
        } else if callsignCount > 0 {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        if scpService.isLoading {
            Text("Downloading callsign database...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if callsignCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(callsignCount.formatted()) callsigns")
                    .font(.subheadline)

                if let date = scpService.lastChecked {
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
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return date < sevenDaysAgo
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await scpService.forceRefresh()
        callsignCount = scpService.database.count
    }
}
