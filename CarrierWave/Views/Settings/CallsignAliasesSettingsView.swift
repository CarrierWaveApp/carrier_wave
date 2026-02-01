import SwiftData
import SwiftUI

// MARK: - CallsignAliasesSettingsView

struct CallsignAliasesSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            currentCallsignSection
            previousCallsignsSection
            addPreviousCallsignSection
            if !nonPrimaryQSOCounts.isEmpty {
                nonPrimaryQSOsSection
            }
        }
        .navigationTitle("Callsign Aliases")
        .task { await loadCallsigns() }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Delete QSOs?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteQSOsForCallsign(callsignToDelete) }
            }
        } message: {
            let count = nonPrimaryQSOCounts[callsignToDelete] ?? 0
            Text("Delete \(count) QSOs logged under \(callsignToDelete)? This cannot be undone.")
        }
    }

    // MARK: Private

    /// Batch size for computing QSO counts
    private static let batchSize = 500

    @Environment(\.modelContext) private var modelContext

    @State private var currentCallsign = ""
    @State private var previousCallsigns: [String] = []
    @State private var newPreviousCallsign = ""
    @State private var isLoading = true
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingDeleteConfirmation = false
    @State private var callsignToDelete = ""

    /// QSO counts grouped by non-primary callsigns (computed in background)
    @State private var nonPrimaryQSOCounts: [String: Int] = [:]
    @State private var isComputingCounts = false

    private let aliasService = CallsignAliasService.shared

    // MARK: - Sections

    private var currentCallsignSection: some View {
        Section {
            HStack {
                TextField("Current Callsign", text: $currentCallsign)
                    .autocapitalization(.allCharacters)
                    .autocorrectionDisabled()

                if !currentCallsign.isEmpty {
                    Button("Save") {
                        Task { await saveCurrentCallsign() }
                    }
                    .disabled(isLoading)
                }
            }
        } header: {
            Text("Current Callsign")
        } footer: {
            Text("Your current amateur radio callsign. Auto-populated from QRZ when you connect.")
        }
    }

    private var previousCallsignsSection: some View {
        Section {
            if previousCallsigns.isEmpty {
                Text("No previous callsigns")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(previousCallsigns, id: \.self) { callsign in
                    HStack {
                        Text(callsign)
                        Spacer()
                        Button {
                            Task { await removePreviousCallsign(callsign) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text("Previous Callsigns")
        } footer: {
            Text(
                """
                Add your previous callsigns so QSOs logged under old calls are properly matched \
                during sync. Note: QSOs from previous callsigns will not be uploaded to QRZ.
                """
            )
        }
    }

    private var addPreviousCallsignSection: some View {
        Section {
            HStack {
                TextField("Add Previous Callsign", text: $newPreviousCallsign)
                    .autocapitalization(.allCharacters)
                    .autocorrectionDisabled()

                Button("Add") {
                    Task { await addPreviousCallsign() }
                }
                .disabled(newPreviousCallsign.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var nonPrimaryQSOsSection: some View {
        Section {
            ForEach(nonPrimaryQSOCounts.keys.sorted(), id: \.self) { callsign in
                HStack {
                    VStack(alignment: .leading) {
                        Text(callsign)
                        Text("\(nonPrimaryQSOCounts[callsign] ?? 0) QSOs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Delete", role: .destructive) {
                        callsignToDelete = callsign
                        showingDeleteConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("QSOs from Other Callsigns")
        } footer: {
            Text(
                """
                These QSOs are logged under callsigns that don't match your current QRZ account \
                and won't be synced. Delete them if you no longer need them.
                """
            )
        }
    }

    private func loadCallsigns() async {
        isLoading = true
        defer { isLoading = false }

        currentCallsign = aliasService.getCurrentCallsign() ?? ""
        previousCallsigns = aliasService.getPreviousCallsigns()

        // Compute QSO counts in background
        await computeNonPrimaryQSOCounts()
    }

    /// Compute QSO counts by callsign in background with batch processing
    private func computeNonPrimaryQSOCounts() async {
        guard !currentCallsign.isEmpty else {
            nonPrimaryQSOCounts = [:]
            return
        }

        isComputingCounts = true
        defer { isComputingCounts = false }

        let primary = currentCallsign.uppercased()
        var counts: [String: Int] = [:]

        // Get total count first
        let countDescriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        let totalCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0

        // Process in batches
        var offset = 0
        while offset < totalCount {
            var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = Self.batchSize

            guard let batch = try? modelContext.fetch(descriptor) else {
                break
            }

            if batch.isEmpty {
                break
            }

            for qso in batch {
                let myCall = qso.myCallsign.uppercased()
                guard !myCall.isEmpty, myCall != primary else {
                    continue
                }
                counts[myCall, default: 0] += 1
            }

            offset += Self.batchSize
            await Task.yield()
        }

        nonPrimaryQSOCounts = counts
    }

    private func saveCurrentCallsign() async {
        do {
            let trimmed = currentCallsign.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                try aliasService.clearCurrentCallsign()
            } else {
                try aliasService.saveCurrentCallsign(trimmed)
            }
            currentCallsign = aliasService.getCurrentCallsign() ?? ""
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func addPreviousCallsign() async {
        let callsign = newPreviousCallsign.trimmingCharacters(in: .whitespaces)
        guard !callsign.isEmpty else {
            return
        }

        do {
            try aliasService.addPreviousCallsign(callsign)
            newPreviousCallsign = ""
            previousCallsigns = aliasService.getPreviousCallsigns()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func removePreviousCallsign(_ callsign: String) async {
        do {
            try aliasService.removePreviousCallsign(callsign)
            previousCallsigns = aliasService.getPreviousCallsigns()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func deleteQSOsForCallsign(_ callsign: String) async {
        let upperCallsign = callsign.uppercased()
        var deletedCount = 0

        // Fetch and delete in batches to avoid loading entire table
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = Self.batchSize

            guard let batch = try? modelContext.fetch(descriptor) else {
                break
            }

            if batch.isEmpty {
                break
            }

            // Filter and delete matching QSOs
            let matchingQSOs = batch.filter { $0.myCallsign.uppercased() == upperCallsign }
            for qso in matchingQSOs {
                modelContext.delete(qso)
                deletedCount += 1
            }

            offset += Self.batchSize
            await Task.yield()
        }

        do {
            try modelContext.save()
            SyncDebugLog.shared.info(
                "Deleted \(deletedCount) QSOs from callsign \(callsign)",
                service: nil
            )

            // Refresh counts after deletion
            await computeNonPrimaryQSOCounts()
        } catch {
            errorMessage = "Failed to delete QSOs: \(error.localizedDescription)"
            showingError = true
        }
    }
}

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
}
