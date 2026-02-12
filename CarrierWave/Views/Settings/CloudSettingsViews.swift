import CarrierWaveCore
import SwiftUI

// MARK: - ICloudSettingsView

struct ICloudSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            Section {
                if let url = monitor.iCloudContainerURL {
                    VStack(alignment: .leading) {
                        Text("Import Folder")
                            .font(.headline)
                        Text(url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Create Folder") {
                        monitor.createImportFolderIfNeeded()
                    }
                } else {
                    Text("iCloud is not available")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Place ADIF files in this folder to import them")
            }

            Section {
                Toggle("Monitor for new files", isOn: .constant(monitor.isMonitoring))
                    .disabled(true)
            }
        }
        .navigationTitle("iCloud")
    }

    // MARK: Private

    @StateObject private var monitor = ICloudMonitor()
}

// MARK: - LoFiSettingsView

struct LoFiSettingsView: View {
    // MARK: Internal

    let tourState: TourState
    var syncService: SyncService?

    var body: some View {
        List {
            if isConfigured {
                configuredSection
            } else {
                setupSection
            }

            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if debugMode, isLinked, syncService != nil {
                Section {
                    Button {
                        Task { await forceRedownload() }
                    } label: {
                        if isRedownloading {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
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
                } header: {
                    Text("Debug")
                } footer: {
                    Text(
                        "Re-fetches all QSOs from LoFi and updates existing records with fresh parsed values."
                    )
                }
            }
        }
        .navigationTitle("Ham2K LoFi")
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            checkStatus()
        }
        .miniTour(.lofiSetup, tourState: tourState)
    }

    // MARK: Private

    @AppStorage("debugMode") private var debugMode = false
    @State private var callsign = ""
    @State private var email = ""
    @State private var isConfigured = false
    @State private var isLinked = false
    @State private var isLoading = false
    @State private var isRedownloading = false
    @State private var redownloadResult: String?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var statusMessage = ""

    private let lofiClient = LoFiClient.appDefault()

    @ViewBuilder
    private var configuredSection: some View {
        Section {
            HStack {
                Label(
                    isLinked ? "Connected" : "Pending",
                    systemImage: isLinked ? "checkmark.circle.fill" : "clock"
                )
                .foregroundStyle(isLinked ? .green : .orange)
                Spacer()
                if let call = lofiClient.getCallsign() {
                    Text(call)
                        .foregroundStyle(.secondary)
                }
            }

            if !isLinked {
                Text("Check your email to confirm the device link")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("I've confirmed the email") {
                    confirmLinked()
                }

                Button("Resend confirmation email") {
                    Task { await resendLinkEmail() }
                }
            }
        } header: {
            Text("Status")
        }

        Section {
            Button("Logout", role: .destructive) {
                logout()
            }
        }
    }

    @ViewBuilder
    private var setupSection: some View {
        Section {
            HStack {
                Text("Callsign")
                Spacer()
                Text(callsign)
                    .foregroundStyle(.secondary)
            }

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
        } header: {
            Text("Setup")
        } footer: {
            Text(
                "Your callsign is used to access your LoFi account. Email is for device verification."
            )
        }

        Section {
            Button {
                Task { await setupAndRegister() }
            } label: {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Connect to LoFi")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(email.isEmpty || isLoading)
        }

        Section {
            Text("Download access must be enabled by Ham2K staff.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Link(
                destination: URL(string: "https://discord.gg/K29T3Njh4U")!
            ) {
                Label("Request on Discord (contact KI2D)", systemImage: "arrow.up.right.square")
            }
        } header: {
            Text("Download Permission")
        } footer: {
            Text("If you see 0 QSOs downloaded after syncing, you may need to request access.")
        }
    }

    private func checkStatus() {
        isConfigured = lofiClient.isConfigured
        isLinked = lofiClient.isLinked

        // Always use profile callsign (non-editable)
        if let profile = UserProfileService.shared.getProfile() {
            callsign = profile.callsign
        }
        if let existingEmail = lofiClient.getEmail() {
            email = existingEmail
        }
    }

    private func setupAndRegister() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try lofiClient.configure(callsign: callsign, email: email)
            let registration = try await lofiClient.register()
            statusMessage = "Registered as \(registration.account.call)"

            try await lofiClient.linkDevice(email: email)
            statusMessage = "Check your email to confirm the device"

            checkStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func confirmLinked() {
        do {
            try lofiClient.markAsLinked()
            checkStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func resendLinkEmail() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await lofiClient.linkDevice(email: email)
            statusMessage = "Confirmation email sent"
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func logout() {
        try? lofiClient.clearCredentials()
        checkStatus()
    }

    @MainActor
    private func forceRedownload() async {
        guard let syncService else {
            return
        }
        isRedownloading = true
        redownloadResult = nil

        do {
            let result = try await syncService.forceRedownloadFromLoFi()
            redownloadResult = "Updated \(result.updated), Created \(result.created)"
        } catch {
            redownloadResult = "Error: \(error.localizedDescription)"
        }

        isRedownloading = false
    }
}
