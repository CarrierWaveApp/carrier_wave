import SwiftUI

// MARK: - CallsignAliasDetectionAlert

/// Helper view modifier to show callsign detection alerts
struct CallsignAliasDetectionAlert: ViewModifier {
    @Binding var unconfiguredCallsigns: Set<String>
    @Binding var showingAlert: Bool

    let onAccept: () async -> Void
    let onOpenSettings: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Multiple Callsigns Detected", isPresented: $showingAlert) {
                Button("Add as Previous") {
                    Task { await onAccept() }
                }
                Button("Open Settings") {
                    onOpenSettings()
                }
                Button("Dismiss", role: .cancel) {}
            } message: {
                let callsignList = unconfiguredCallsigns.sorted().joined(separator: ", ")
                Text(
                    """
                    Found QSOs logged under callsigns that aren't configured: \(callsignList). \
                    Add these as your previous callsigns?
                    """
                )
            }
    }
}

extension View {
    func callsignAliasDetectionAlert(
        unconfiguredCallsigns: Binding<Set<String>>,
        showingAlert: Binding<Bool>,
        onAccept: @escaping () async -> Void,
        onOpenSettings: @escaping () -> Void
    ) -> some View {
        modifier(
            CallsignAliasDetectionAlert(
                unconfiguredCallsigns: unconfiguredCallsigns,
                showingAlert: showingAlert,
                onAccept: onAccept,
                onOpenSettings: onOpenSettings
            )
        )
    }
}

// MARK: - POTAPresenceRepairAlert

/// Helper view modifier to show POTA presence repair alerts
struct POTAPresenceRepairAlert: ViewModifier {
    @Binding var mismarkedCount: Int
    @Binding var showingAlert: Bool

    let onRepair: () async -> Void

    func body(content: Content) -> some View {
        content
            .alert("POTA Upload Queue Issue", isPresented: $showingAlert) {
                Button("Fix Now") {
                    Task { await onRepair() }
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text(
                    """
                    Found \(mismarkedCount) QSOs incorrectly marked for POTA upload. \
                    These QSOs don't have a park reference and shouldn't be uploaded to POTA.

                    Tap "Fix Now" to correct this. If you skip this, the POTA upload count \
                    will be inflated and these QSOs will fail to upload.
                    """
                )
            }
    }
}

extension View {
    func potaPresenceRepairAlert(
        mismarkedCount: Binding<Int>,
        showingAlert: Binding<Bool>,
        onRepair: @escaping () async -> Void
    ) -> some View {
        modifier(
            POTAPresenceRepairAlert(
                mismarkedCount: mismarkedCount,
                showingAlert: showingAlert,
                onRepair: onRepair
            )
        )
    }

    func twoferDuplicateRepairAlert(
        duplicateCount: Binding<Int>,
        showingAlert: Binding<Bool>,
        onRepair: @escaping () async -> Void
    ) -> some View {
        modifier(
            TwoferDuplicateRepairAlert(
                duplicateCount: duplicateCount,
                showingAlert: showingAlert,
                onRepair: onRepair
            )
        )
    }

    func phoneSSBDuplicateRepairAlert(
        duplicateCount: Binding<Int>,
        showingAlert: Binding<Bool>,
        onRepair: @escaping () async -> Void
    ) -> some View {
        modifier(
            PhoneSSBDuplicateRepairAlert(
                duplicateCount: duplicateCount,
                showingAlert: showingAlert,
                onRepair: onRepair
            )
        )
    }

    func syncImportConfirmationAlert(syncService: SyncService) -> some View {
        modifier(SyncImportConfirmationAlert(syncService: syncService))
    }

    func syncExportConfirmationAlert(syncService: SyncService) -> some View {
        modifier(SyncExportConfirmationAlert(syncService: syncService))
    }
}

// MARK: - PhoneSSBDuplicateRepairAlert

struct PhoneSSBDuplicateRepairAlert: ViewModifier {
    @Binding var duplicateCount: Int
    @Binding var showingAlert: Bool

    let onRepair: () async -> Void

    func body(content: Content) -> some View {
        content
            .alert("PHONE/SSB Duplicates Found", isPresented: $showingAlert) {
                Button("Merge Duplicates") {
                    Task { await onRepair() }
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text(
                    """
                    Found \(duplicateCount) duplicate QSO pair(s) where POTA recorded \
                    the mode as "PHONE" and QRZ recorded it as "SSB".

                    Tap "Merge Duplicates" to combine them and preserve all sync status.
                    """
                )
            }
    }
}

// MARK: - SyncImportConfirmationAlert

struct SyncImportConfirmationAlert: ViewModifier {
    @ObservedObject var syncService: SyncService

    func body(content: Content) -> some View {
        content
            .alert(
                "Large Sync Detected",
                isPresented: Binding(
                    get: { syncService.importConfirmation != nil },
                    set: {
                        if !$0 {
                            syncService.resolveImportConfirmation(proceed: false)
                        }
                    }
                )
            ) {
                Button("Import") {
                    syncService.resolveImportConfirmation(proceed: true)
                }
                Button("Cancel", role: .cancel) {
                    syncService.resolveImportConfirmation(proceed: false)
                }
            } message: {
                if let confirmation = syncService.importConfirmation {
                    Text(
                        """
                        Downloaded \(confirmation.totalDownloaded) QSOs \
                        (\(confirmation.summary)).

                        Do you want to import them?
                        """
                    )
                }
            }
    }
}

// MARK: - SyncExportConfirmationAlert

struct SyncExportConfirmationAlert: ViewModifier {
    @ObservedObject var syncService: SyncService

    func body(content: Content) -> some View {
        content
            .alert(
                "Large Upload Detected",
                isPresented: Binding(
                    get: { syncService.exportConfirmation != nil },
                    set: {
                        if !$0 {
                            syncService.resolveExportConfirmation(proceed: false)
                        }
                    }
                )
            ) {
                Button("Upload") {
                    syncService.resolveExportConfirmation(proceed: true)
                }
                Button("Cancel", role: .cancel) {
                    syncService.resolveExportConfirmation(proceed: false)
                }
            } message: {
                if let confirmation = syncService.exportConfirmation {
                    Text(
                        """
                        \(confirmation.totalToUpload) QSOs are queued for upload \
                        (\(confirmation.summary)).

                        Do you want to upload them?
                        """
                    )
                }
            }
    }
}

// MARK: - TwoferDuplicateRepairAlert

struct TwoferDuplicateRepairAlert: ViewModifier {
    @Binding var duplicateCount: Int
    @Binding var showingAlert: Bool

    let onRepair: () async -> Void

    func body(content: Content) -> some View {
        content
            .alert("Duplicate QSOs Found", isPresented: $showingAlert) {
                Button("Merge Duplicates") {
                    Task { await onRepair() }
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text(
                    """
                    Found \(duplicateCount) duplicate QSO group(s) from two-fer activations. \
                    These appear to be the same contacts imported from different sources \
                    with different park reference formats.

                    Tap "Merge Duplicates" to combine them and preserve all sync status.
                    """
                )
            }
    }
}
