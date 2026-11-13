// Tiles on the Air settings: API key entry + connectivity test + manual ADIF upload.
//
// TOTA's API has no documented "validate key" endpoint, so we use a lightweight
// `GET /spots` call carrying the key to confirm the request reaches the server.
// Real key validation happens on first activation create / ADIF upload.

import CarrierWaveData
import SwiftUI
import UniformTypeIdentifiers

struct TOTASettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            statusSection
            if isConfigured {
                actionsSection
                personalEffortSection
                logoutSection
            } else {
                setupSection
                connectButton
                personalEffortSection
                aboutSection
            }
            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("TOTA")
        .alert("TOTA", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: TOTASettingsView.adifTypes
        ) { result in
            handleFilePickResult(result)
        }
        .onAppear { refreshStatus() }
    }

    // MARK: Private

    private static let adifTypes: [UTType] = {
        var types: [UTType] = []
        if let adi = UTType(filenameExtension: "adi") {
            types.append(adi)
        }
        if let adif = UTType(filenameExtension: "adif") {
            types.append(adif)
        }
        if types.isEmpty {
            types.append(.plainText)
        }
        return types
    }()

    @State private var apiKey = ""
    @State private var isConfigured = false
    @State private var isWorking = false
    @State private var statusMessage = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingFilePicker = false
    @State private var lastUploadResult: String?
    /// Personal Effort Factor (1...10). 0 = not opted in. Copied onto each new
    /// TOTA session at start, then frozen on the session per the rules.
    @AppStorage("totaPersonalEffortFactor") private var personalEffortFactor: Int = 0

    private var client: TOTAClient {
        TOTAClient.shared
    }

    private var statusSection: some View {
        Section {
            HStack {
                if isConfigured {
                    Label("API key saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Not configured", systemImage: "key.slash")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        } header: {
            Text("Status")
        }
    }

    private var setupSection: some View {
        Section {
            Text(
                "Generate an API key in your tilesontheair.com profile, then paste it below. "
                    + "The key is stored in your iOS Keychain."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            SecureField("API Key", text: $apiKey)
                .textContentType(.password)
                .autocapitalization(.none)
                .autocorrectionDisabled()
        } header: {
            Text("Setup")
        }
    }

    private var connectButton: some View {
        Section {
            Button {
                Task { await saveAndTest() }
            } label: {
                if isWorking {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Save and Test")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
        }
    }

    private var aboutSection: some View {
        Section {
            Link(destination: URL(string: "https://tilesontheair.com")!) {
                Label("Open tilesontheair.com", systemImage: "arrow.up.right.square")
            }
        } footer: {
            Text(
                "Tiles on the Air is an outdoor radio program that scores activations of "
                    + "Maidenhead grid tiles."
            )
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await testConnection() }
            } label: {
                if isWorking {
                    ProgressView()
                } else {
                    Label("Test Connection", systemImage: "network")
                }
            }
            .disabled(isWorking)

            Button {
                showingFilePicker = true
            } label: {
                Label("Upload ADIF File…", systemImage: "arrow.up.doc")
            }
            .disabled(isWorking)

            if let lastUploadResult {
                Text(lastUploadResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Actions")
        } footer: {
            Text(
                "Upload sends a standard ADIF 3.x file to TOTA. Points are calculated "
                    + "server-side and the activation appears on the public spots feed."
            )
        }
    }

    private var personalEffortSection: some View {
        Section {
            Toggle(
                "Opt in to Personal Effort Factor",
                isOn: Binding(
                    get: { personalEffortFactor > 0 },
                    set: { newValue in
                        personalEffortFactor = newValue ? max(personalEffortFactor, 1) : 0
                    }
                )
            )
            if personalEffortFactor > 0 {
                Stepper(
                    "PEF: \(personalEffortFactor)",
                    value: $personalEffortFactor,
                    in: 1 ... 10
                )
            }
        } header: {
            Text("Personal Effort Factor")
        } footer: {
            Text(
                "PEF (1-10) scales the distance term of your TOTA score on the "
                    + "Personal Effort leaderboard only. Standard leaderboard ranking "
                    + "is unaffected. The value at the start of each session is frozen "
                    + "onto that session."
            )
        }
    }

    private var logoutSection: some View {
        Section {
            Button("Remove API Key", role: .destructive) {
                client.clearApiKey()
                apiKey = ""
                statusMessage = ""
                lastUploadResult = nil
                refreshStatus()
            }
        }
    }

    private func refreshStatus() {
        isConfigured = client.isConfigured
    }

    private func saveAndTest() async {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        isWorking = true
        defer { isWorking = false }

        do {
            try client.setApiKey(trimmed)
        } catch {
            present(error: "Could not save API key: \(error.localizedDescription)")
            return
        }
        refreshStatus()

        do {
            _ = try await client.fetchSpots(activeHours: 0.1, limit: 1)
            statusMessage = "Saved. Spot fetch with key returned successfully."
        } catch let error as TOTAError {
            present(error: error.localizedDescription)
        } catch {
            present(error: error.localizedDescription)
        }
    }

    private func testConnection() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let spots = try await client.fetchSpots(activeHours: 0.5, limit: 5)
            statusMessage = "Connected. Last 30 min returned \(spots.count) spot(s)."
        } catch let error as TOTAError {
            present(error: error.localizedDescription)
        } catch {
            present(error: error.localizedDescription)
        }
    }

    private func handleFilePickResult(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            Task { await uploadADIFFile(at: url) }
        case let .failure(error):
            present(error: "File picker failed: \(error.localizedDescription)")
        }
    }

    private func uploadADIFFile(at url: URL) async {
        isWorking = true
        defer { isWorking = false }

        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            guard let contents = String(data: data, encoding: .utf8) else {
                present(error: "ADIF file is not valid UTF-8 text.")
                return
            }
            let response = try await client.uploadADIF(contents, filename: url.lastPathComponent)
            if response.success, let detail = response.activation {
                let pointsText = detail.points.map { String(format: "%.1f", $0) } ?? "—"
                lastUploadResult =
                    "Uploaded \(url.lastPathComponent). Points: \(pointsText), grid: \(detail.maidenheadGrid ?? "—")."
            } else {
                lastUploadResult = "Upload returned success=false: \(response.error ?? "no detail")"
            }
        } catch let error as TOTAError {
            present(error: error.localizedDescription)
        } catch {
            present(error: "Upload failed: \(error.localizedDescription)")
        }
    }

    private func present(error message: String) {
        errorMessage = message
        showingError = true
    }
}
