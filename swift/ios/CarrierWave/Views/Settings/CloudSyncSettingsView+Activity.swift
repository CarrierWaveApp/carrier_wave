import CarrierWaveData
import SwiftUI

extension CloudSyncSettingsView {
    var activitySummarySection: some View {
        Section {
            if syncService.syncSummary.lastFetchDate == nil,
               syncService.syncSummary.lastUploadDate == nil
            {
                Text("No sync activity yet")
                    .foregroundStyle(.secondary)
            }

            if let fetchDate = syncService.syncSummary.lastFetchDate {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Last Fetch")
                        Spacer()
                        Text(fetchDate, style: .relative)
                            .foregroundStyle(.secondary)
                        Text("ago")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        durationBadge(
                            syncService.syncSummary.lastFetchDuration
                        )
                        if let rc = syncService.syncSummary.lastFetchRecordCount {
                            Text("\(rc) records")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        sizeBadge(
                            syncService.syncSummary.lastFetchByteCount
                        )
                        if let tail = syncService.syncSummary.lastFetchJournalTailCount {
                            Text("\(tail) journal entries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let uploadDate = syncService.syncSummary.lastUploadDate {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Last Upload")
                        Spacer()
                        Text(uploadDate, style: .relative)
                            .foregroundStyle(.secondary)
                        Text("ago")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        durationBadge(
                            syncService.syncSummary.lastUploadDuration
                        )
                        if let rc = syncService.syncSummary
                            .lastUploadRecordCount
                        {
                            Text("\(rc) records")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        sizeBadge(
                            syncService.syncSummary.lastUploadByteCount
                        )
                    }
                }
            }

            HStack {
                Text("Today")
                Spacer()
                let cs = syncService.syncSummary.conflictsToday
                let es = syncService.syncSummary.errorsToday
                Text("\(cs) conflicts")
                    .foregroundStyle(cs > 0 ? .orange : .secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(es) errors")
                    .foregroundStyle(es > 0 ? .red : .secondary)
            }
            .font(.subheadline)

            NavigationLink {
                CloudSyncActivityView()
            } label: {
                Label("Sync Log", systemImage: "list.bullet.rectangle")
            }
        } header: {
            Text("Activity")
        }
    }

    func durationBadge(_ duration: TimeInterval?) -> some View {
        Group {
            if let dur = duration {
                Text(String(format: "%.1fs", dur))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
        }
    }

    func sizeBadge(_ byteCount: Int64?) -> some View {
        Group {
            if let bytes = byteCount, bytes > 0 {
                Text(ByteCountFormatter.string(
                    fromByteCount: bytes, countStyle: .file
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                )
            }
        }
    }
}
