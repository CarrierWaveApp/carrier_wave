import CarrierWaveCore
import SwiftUI

// MARK: - ServiceDetailSheet

/// Sheet presenting detailed service information and actions
struct ServiceDetailSheet: View {
    // MARK: Internal

    let serviceId: ServiceIdentifier
    // Service-specific data passed in
    let isConfigured: Bool
    let callsign: String?
    let syncedCount: Int
    let pendingCount: Int
    let confirmedCount: Int?
    let lastSyncResult: String?
    let isSyncing: Bool
    let debugMode: Bool

    /// Maintenance (POTA only)
    let isInMaintenance: Bool

    // Session expiry (POTA only)
    let sessionExpiringSoon: Bool
    let sessionExpiryDate: Date?

    // iCloud specific
    let importedCount: Int?
    let pendingFiles: Int?
    let isMonitoring: Bool?

    // Actions
    let onSync: (() async -> Void)?
    let onClearData: (() async -> Void)?
    let onConfigure: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                // Status section
                Section {
                    statusRow
                    if let callsign {
                        HStack {
                            Text("Callsign")
                            Spacer()
                            Text(callsign)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Stats section
                if isConfigured || syncedCount > 0 {
                    Section("Statistics") {
                        statRow(label: "Synced", value: syncedCount, icon: "checkmark.circle")

                        if let confirmed = confirmedCount, confirmed > 0 {
                            statRow(
                                label: "QSLs Confirmed", value: confirmed, icon: "checkmark.seal"
                            )
                        }

                        if pendingCount > 0 {
                            statRow(
                                label: "Pending",
                                value: pendingCount,
                                icon: "clock",
                                color: .orange
                            )
                        }

                        if let imported = importedCount {
                            statRow(label: "Imported", value: imported, icon: "arrow.down.circle")
                        }

                        if let pending = pendingFiles, pending > 0 {
                            statRow(
                                label: "Files Pending",
                                value: pending,
                                icon: "doc.badge.clock",
                                color: .orange
                            )
                        }
                    }
                }

                // Warnings section
                if sessionExpiringSoon || isInMaintenance {
                    Section {
                        if sessionExpiringSoon, let expiry = sessionExpiryDate {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .foregroundStyle(.orange)
                                Text("Session expires \(expiry, style: .relative)")
                                    .foregroundStyle(.orange)
                            }
                        }

                        if isInMaintenance {
                            HStack(spacing: 8) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .foregroundStyle(.orange)
                                Text("POTA maintenance until 0400 UTC")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                // Last sync result
                if let result = lastSyncResult {
                    Section("Last Sync") {
                        Text(result)
                            .font(.subheadline)
                            .foregroundStyle(
                                result.starts(with: "Error") ? .red : .secondary
                            )
                    }
                }

                // Actions section
                Section {
                    if isConfigured {
                        if let onSync {
                            Button {
                                Task { await onSync() }
                            } label: {
                                HStack {
                                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                                    if isSyncing {
                                        Spacer()
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(isSyncing || isInMaintenance)
                        }

                        if debugMode, let onClearData {
                            Button(role: .destructive) {
                                Task { await onClearData() }
                            } label: {
                                Label("Clear Data", systemImage: "trash")
                            }
                            .disabled(isSyncing)
                        }
                    } else if let onConfigure {
                        Button {
                            onConfigure()
                        } label: {
                            Label("Configure", systemImage: "gear")
                        }
                    }
                }

                // Monitoring status (iCloud)
                if let monitoring = isMonitoring, monitoring {
                    Section {
                        HStack {
                            Image(systemName: "eye")
                                .foregroundStyle(.secondary)
                            Text("Monitoring for new files")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(serviceId.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private var statusRow: some View {
        HStack {
            Text("Status")
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(isConfigured ? Color.green : Color(.systemGray3))
                    .frame(width: 8, height: 8)
                Text(isConfigured ? "Connected" : "Not configured")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statRow(
        label: String,
        value: Int,
        icon: String,
        color: Color = .blue
    ) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(color)
            Spacer()
            Text("\(value)")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ServiceDetailSheet(
        serviceId: .service(.qrz),
        isConfigured: true,
        callsign: "W1AW",
        syncedCount: 312,
        pendingCount: 5,
        confirmedCount: 45,
        lastSyncResult: "Synced 5 new QSOs",
        isSyncing: false,
        debugMode: true,
        isInMaintenance: false,
        sessionExpiringSoon: false,
        sessionExpiryDate: nil,
        importedCount: nil,
        pendingFiles: nil,
        isMonitoring: nil,
        onSync: {},
        onClearData: {},
        onConfigure: nil
    )
}
