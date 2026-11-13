import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    // MARK: Internal

    enum ConnectionCheckResult {
        case success(HealthResponse)
        case failure(String)
    }

    @EnvironmentObject var config: ServerConfig

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("https://your-server.example.com", text: $config.serverURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .fontDesign(.monospaced)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Admin Token")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("Admin token", text: $config.adminToken)
                            .fontDesign(.monospaced)
                    }
                } header: {
                    Text("Server Connection")
                } footer: {
                    Text("The admin token is required for managing clubs, challenges, and programs.")
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isChecking {
                                ProgressView()
                            } else if let result = checkResult {
                                switch result {
                                case .success:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                case .failure:
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    .disabled(!config.isConfigured || isChecking)

                    if case let .success(health) = checkResult {
                        LabeledContent("Status") {
                            Text(health.status)
                                .foregroundStyle(.green)
                        }
                        LabeledContent("Version") {
                            Text(health.version)
                                .fontDesign(.monospaced)
                        }
                    }

                    if case let .failure(message) = checkResult {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        config.disconnect()
                        checkResult = nil
                    } label: {
                        HStack {
                            Image(systemName: "power")
                            Text("Disconnect")
                        }
                    }
                    .disabled(!config.isConfigured)
                }

                Section {
                    LabeledContent("App") {
                        Text("Challenges Admin")
                    }
                    LabeledContent("Built for") {
                        Text("Challenges Server (Rust/Axum)")
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: Private

    @State private var health: HealthResponse?
    @State private var isChecking = false
    @State private var checkResult: ConnectionCheckResult?

    private func testConnection() async {
        isChecking = true
        checkResult = nil
        let api = APIClient(config: config)
        do {
            let health = try await api.getHealth()
            checkResult = .success(health)
        } catch {
            checkResult = .failure(error.localizedDescription)
        }
        isChecking = false
    }
}

// MARK: - ServerSetupView

struct ServerSetupView: View {
    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "server.rack")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Challenges Admin")
                    .font(.largeTitle.bold())

                Text(
                    "Connect to your Challenges Server to monitor health, view aggregator stats, " +
                        "and manage clubs and activities."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    TextField("Server URL", text: $config.serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fontDesign(.monospaced)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Admin Token", text: $config.adminToken)
                        .fontDesign(.monospaced)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 32)

                if let error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 32)
                }

                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        if isChecking {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Connect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(config.isConfigured ? Color.blue : Color.secondary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!config.isConfigured || isChecking)
                .padding(.horizontal, 32)

                Spacer()
                Spacer()
            }
        }
    }

    // MARK: Private

    @State private var isChecking = false
    @State private var error: String?

    private func connect() async {
        isChecking = true
        error = nil
        let api = APIClient(config: config)
        do {
            _ = try await api.getHealth()
            // Success - config is already saved, ContentView will switch to MainTabView
        } catch {
            self.error = error.localizedDescription
        }
        isChecking = false
    }
}
