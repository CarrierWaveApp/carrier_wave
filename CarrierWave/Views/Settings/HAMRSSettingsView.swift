import CarrierWaveData
import SwiftUI

struct HAMRSSettingsView: View {
    // MARK: Internal

    var syncService: SyncService?

    var body: some View {
        List {
            if isConfigured {
                Section {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                    }
                } header: {
                    Text("Status")
                }

                Section {
                    Button("Logout", role: .destructive) {
                        logout()
                    }
                }
            } else {
                Section {
                    Text("Connect your HAMRS Pro account to import QSOs logged in HAMRS.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Setup")
                } footer: {
                    Text("Find your API key in your HAMRS account settings at hamrs.app")
                }

                Section {
                    Button {
                        Task { await validateAndSave() }
                    } label: {
                        if isValidating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect to HAMRS")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(apiKey.isEmpty || isValidating)
                }

                Section {
                    Link(destination: URL(string: "https://hamrs.app")!) {
                        Label("Get HAMRS Pro", systemImage: "arrow.up.right.square")
                    }
                } footer: {
                    Text("Requires HAMRS Pro subscription for cloud sync access.")
                }
            }

            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if debugMode, isConfigured, syncService != nil {
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
                        "Re-fetches all QSOs from HAMRS and updates existing records with fresh parsed values."
                    )
                }
            }
        }
        .navigationTitle("HAMRS Pro")
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            checkStatus()
        }
    }

    // MARK: Private

    @AppStorage("debugMode") private var debugMode = false
    @State private var apiKey = ""
    @State private var isConfigured = false
    @State private var isValidating = false
    @State private var isRedownloading = false
    @State private var redownloadResult: String?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var statusMessage = ""

    private let hamrsClient = HAMRSClient()

    private func checkStatus() {
        isConfigured = hamrsClient.isConfigured
    }

    private func validateAndSave() async {
        isValidating = true
        defer { isValidating = false }

        do {
            try await hamrsClient.configure(apiKey: apiKey)
            statusMessage = "Connected successfully"
            checkStatus()
        } catch HAMRSError.subscriptionInactive {
            errorMessage = "HAMRS Pro subscription is inactive. Visit hamrs.app to resubscribe."
            showingError = true
        } catch HAMRSError.invalidApiKey {
            errorMessage = "Invalid API key. Check your HAMRS account settings."
            showingError = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func logout() {
        hamrsClient.clearCredentials()
        apiKey = ""
        statusMessage = ""
        checkStatus()
    }

    private func forceRedownload() async {
        guard let syncService else {
            return
        }
        isRedownloading = true
        redownloadResult = nil
        defer { isRedownloading = false }

        do {
            let result = try await syncService.forceRedownloadFromHAMRS()
            redownloadResult = "Updated \(result.updated), Created \(result.created)"
        } catch {
            redownloadResult = "Error: \(error.localizedDescription)"
        }
    }
}
