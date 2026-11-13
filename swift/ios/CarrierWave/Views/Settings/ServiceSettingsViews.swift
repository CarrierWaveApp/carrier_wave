import CarrierWaveData
import SwiftUI

// MARK: - QRZApiKeySheet

struct QRZApiKeySheet: View {
    // MARK: Internal

    var isPrimary: Bool = false
    var onMappingCreated: (QRZCallsignMapping) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter your QRZ Logbook API key from your QRZ logbook settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Link(destination: URL(string: "https://logbook.qrz.com/logbook")!) {
                        Label("Get API key from QRZ Logbook", systemImage: "arrow.up.right.square")
                    }

                    TextField("API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                if let validatedCallsign {
                    Section {
                        HStack {
                            Label(validatedCallsign, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Text("Verified").foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Callsign")
                    }
                }

                Section {
                    Button {
                        Task { await validateAndSave() }
                    } label: {
                        if isValidating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(apiKey.isEmpty || isValidating)
                }
            }
            .navigationTitle("QRZ API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var validatedCallsign: String?
    @State private var errorMessage = ""
    @State private var showingError = false

    private func validateAndSave() async {
        isValidating = true
        defer { isValidating = false }

        do {
            let client = QRZClient()
            let mapping = try await client.validateAndCreateMapping(
                apiKey, isPrimary: isPrimary
            )
            validatedCallsign = mapping.callsign
            try client.addCallsignMapping(mapping)

            // For primary mappings, also update legacy keys and profile
            if isPrimary {
                try client.saveApiKey(apiKey)
                try client.saveCallsign(mapping.callsign)
                if let bookId = mapping.bookId {
                    try client.saveBookId(bookId, for: mapping.callsign)
                }
                try UserProfileService.shared.applyDetectedCallsignChangeIfNeeded(
                    newCallsign: mapping.callsign
                )
            } else {
                // Ensure previous callsign is registered in aliases
                try CallsignAliasService.shared.addPreviousCallsign(mapping.callsign)
            }

            onMappingCreated(mapping)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - QRZSettingsView

struct QRZSettingsView: View {
    // MARK: Internal

    var syncService: SyncService?

    var body: some View {
        List {
            if let logbookMismatch {
                logbookMismatchSection(logbookMismatch)
            }
            connectedAccountsSection
            if !unlinkedCallsigns.isEmpty {
                unlinkedCallsignsSection
            }
            addAccountSection
            SetupGuideSection(pages: MiniTourContent.qrzSetup)
            Section {} footer: {
                Text(
                    "This syncs QSOs with your QRZ logbook. For QRZ name/address "
                        + "lookups, set up QRZ Callsign Lookup under "
                        + "Settings > Data & Tools."
                )
            }
            if debugMode, !mappings.isEmpty, syncService != nil {
                debugSection
            }
        }
        .navigationTitle("QRZ Logbook Sync")
        .sheet(isPresented: $showingAddSheet) {
            QRZApiKeySheet(isPrimary: mappings.isEmpty) { mapping in
                promoteIfCurrentCallsign(mapping)
                reloadMappings()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onAppear { reloadMappings() }
    }

    // MARK: Private

    @AppStorage("debugMode") private var debugMode = false
    @State private var mappings: [QRZCallsignMapping] = []
    @State private var unlinkedCallsigns: [String] = []
    @State private var logbookMismatch: QRZLogbookCallsignMismatch?
    @State private var showingAddSheet = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isRedownloading = false
    @State private var redownloadResult: String?

    private let qrzClient = QRZClient()

    private var connectedAccountsSection: some View {
        Section {
            if mappings.isEmpty {
                Text("No QRZ accounts connected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mappings) { mapping in
                    HStack {
                        Label(mapping.callsign, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if mapping.isPrimary {
                            Text("Primary")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue, in: Capsule())
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Remove", role: .destructive) {
                            removeMapping(mapping)
                        }
                        if !mapping.isPrimary {
                            Button("Set Primary") {
                                setPrimary(mapping)
                            }
                            .tint(.blue)
                        }
                    }
                    .contextMenu {
                        if !mapping.isPrimary {
                            Button {
                                setPrimary(mapping)
                            } label: {
                                Label("Set as Primary", systemImage: "star")
                            }
                        }
                        Button(role: .destructive) {
                            removeMapping(mapping)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("Connected Accounts")
        } footer: {
            Text(
                "Each QRZ API key maps to one callsign. QSOs are synced to the "
                    + "matching account. Swipe or long-press an account to change "
                    + "which one is primary."
            )
        }
    }

    private var unlinkedCallsignsSection: some View {
        Section {
            ForEach(unlinkedCallsigns, id: \.self) { callsign in
                HStack {
                    Text(callsign)
                    Spacer()
                    Text("No API key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Unlinked Previous Callsigns")
        } footer: {
            Text("QSOs logged under these callsigns won't sync to QRZ. Add an API key to enable.")
        }
    }

    private var addAccountSection: some View {
        Section {
            Button("Add Callsign API Key") { showingAddSheet = true }

            Link(
                destination: URL(
                    string: "https://shop.qrz.com/collections/subscriptions/products/"
                        + "xml-logbook-data-subscription-1-year"
                )!
            ) {
                Label("Get QRZ Subscription", systemImage: "arrow.up.right.square")
            }
        } footer: {
            Text("Requires QRZ XML Logbook Data subscription for each callsign.")
        }
    }

    private var debugSection: some View {
        Section {
            Button {
                Task { await forceRedownload() }
            } label: {
                if isRedownloading {
                    HStack {
                        ProgressView().padding(.trailing, 4)
                        Text("Re-downloading...")
                    }
                } else {
                    Text("Force Re-download All QSOs")
                }
            }
            .disabled(isRedownloading)

            if let result = redownloadResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Logout All", role: .destructive) { logoutAll() }
        } header: {
            Text("Debug")
        }
    }

    /// Shown when the operator's callsign has no connected QRZ key, so their
    /// new QSOs silently never reach QRZ.
    private func logbookMismatchSection(
        _ mismatch: QRZLogbookCallsignMismatch
    ) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No QRZ logbook for \(mismatch.currentCallsign)")
                        .font(.subheadline.weight(.medium))
                    Text(
                        "Your callsign is \(mismatch.currentCallsign), but the "
                            + "connected QRZ logbook belongs to "
                            + "\(mismatch.logbookCallsign). QSOs you log as "
                            + "\(mismatch.currentCallsign) won't sync to QRZ until "
                            + "you add the logbook API key for that callsign."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .accessibilityElement(children: .combine)

            Button("Add API Key for \(mismatch.currentCallsign)") {
                showingAddSheet = true
            }
        }
    }

    private func reloadMappings() {
        mappings = qrzClient.getCallsignMappings()
        let mappedCallsigns = Set(mappings.map(\.callsign))
        let allPrevious = CallsignAliasService.shared.getPreviousCallsigns()
        unlinkedCallsigns = allPrevious.filter { !mappedCallsigns.contains($0) }
        logbookMismatch = qrzClient.logbookMismatch()
    }

    /// A key added for the callsign the operator is logging under becomes the
    /// primary account, so the QRZ row and callsign sync follow the current
    /// callsign rather than a retired one.
    private func promoteIfCurrentCallsign(_ mapping: QRZCallsignMapping) {
        guard !mapping.isPrimary,
              let current = CallsignAliasService.shared.getCurrentCallsign()?.uppercased(),
              mapping.callsign == current
        else {
            return
        }
        try? qrzClient.setPrimaryMapping(for: mapping.callsign)
    }

    private func setPrimary(_ mapping: QRZCallsignMapping) {
        do {
            try qrzClient.setPrimaryMapping(for: mapping.callsign)
            reloadMappings()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func removeMapping(_ mapping: QRZCallsignMapping) {
        do {
            try qrzClient.removeCallsignMapping(for: mapping.callsign)
            reloadMappings()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func logoutAll() {
        qrzClient.logout()
        reloadMappings()
    }

    @MainActor
    private func forceRedownload() async {
        guard let syncService else {
            return
        }
        isRedownloading = true
        redownloadResult = nil
        do {
            let result = try await syncService.forceRedownloadFromQRZ()
            redownloadResult = "Updated \(result.updated), Created \(result.created)"
        } catch {
            redownloadResult = "Error: \(error.localizedDescription)"
        }
        isRedownloading = false
    }
}
