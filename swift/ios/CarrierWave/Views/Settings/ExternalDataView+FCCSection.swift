// External Data View - FCC Section
//
// Shows download status and refresh controls for the FCC
// amateur radio callsign database used for offline lookups.

import SwiftUI

// MARK: - FCCCacheSection

/// Section showing FCC callsign database cache status with download/refresh controls
struct FCCCacheSection: View {
    // MARK: Internal

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("FCC Callsigns", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)

                    Spacer()

                    statusBadge
                }

                statusDetail

                HStack {
                    Button {
                        Task { await downloadOrRefresh() }
                    } label: {
                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(
                                recordCount > 0 ? "Refresh Now" : "Download",
                                systemImage: recordCount > 0 ? "arrow.clockwise" : "arrow.down.circle"
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDownloading)

                    Spacer()
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text(
                "US amateur radio license database from the FCC for offline "
                    + "callsign lookups (name, location, grid, license class). "
                    + "Updated weekly."
            )
        }
        .task {
            await loadState()
        }
        .alert("FCC Download Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Private

    @State private var recordCount = 0
    @State private var isDownloading = false
    @State private var lastUpdated: Date?
    @State private var showingError = false
    @State private var errorMessage = ""

    @ViewBuilder
    private var statusBadge: some View {
        if isDownloading {
            ProgressView()
                .controlSize(.small)
        } else if recordCount > 0 {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        if isDownloading {
            Text("Downloading FCC callsign database...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if recordCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(recordCount.formatted()) callsigns")
                    .font(.subheadline)

                if let date = lastUpdated {
                    HStack(spacing: 4) {
                        Text("Updated")
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

    private func loadState() async {
        let service = FCCLookupService.shared
        await service.loadIfNeeded()
        recordCount = await service.recordCount
        lastUpdated = await service.lastUpdated
    }

    private func downloadOrRefresh() async {
        isDownloading = true
        defer { isDownloading = false }
        let service = FCCLookupService.shared
        await service.forceRefresh()
        recordCount = await service.recordCount
        lastUpdated = await service.lastUpdated
        if let error = await service.lastError {
            errorMessage = error
            showingError = true
        }
    }
}
