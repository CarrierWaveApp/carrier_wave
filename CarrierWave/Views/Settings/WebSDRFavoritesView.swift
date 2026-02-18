import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - WebSDRFavoritesView

/// Settings view for managing WebSDR favorites.
struct WebSDRFavoritesView: View {
    // MARK: Internal

    var body: some View {
        List {
            if favorites.isEmpty {
                emptyState
            } else {
                favoritesSection
            }

            if advancedMode {
                addSection
            }

            advancedToggle
        }
        .navigationTitle("WebSDR Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
        .sheet(isPresented: $showAddSheet) {
            AddReceiverSheet { hostPort, name, location, antenna in
                addFavorite(
                    hostPort: hostPort, name: name,
                    location: location, antenna: antenna
                )
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @AppStorage("webSDRAdvancedMode") private var advancedMode = false
    @State private var favorites: [WebSDRFavorite] = []
    @State private var enrichments: [String: KiwiSDRStatusFetcher.ReceiverStatus] = [:]
    @State private var showAddSheet = false

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "star")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No Favorites")
                    .font(.headline)
                Text("Star receivers in the WebSDR picker to add favorites.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var favoritesSection: some View {
        Section {
            ForEach(favorites) { favorite in
                favoriteRow(favorite)
            }
            .onDelete(perform: deleteFavorites)
        } header: {
            Text("\(favorites.count) favorite\(favorites.count == 1 ? "" : "s")")
        }
    }

    private var addSection: some View {
        Section {
            Button {
                showAddSheet = true
            } label: {
                Label("Add by Address", systemImage: "plus")
            }
        } header: {
            Text("Manual")
        } footer: {
            Text("Add a private or unlisted KiwiSDR by entering its host and port.")
        }
    }

    private var advancedToggle: some View {
        Section {
            Toggle("Advanced Mode", isOn: $advancedMode)
        } footer: {
            Text(
                "Advanced mode allows manually adding private or unlisted receivers by address."
            )
        }
    }

    private func favoriteRow(_ favorite: WebSDRFavorite) -> some View {
        let enrichment = enrichments[favorite.hostPort]
        return VStack(alignment: .leading, spacing: 4) {
            Text(favorite.displayName)
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 4) {
                Text(favorite.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let grid = enrichment?.grid {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(grid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                if let parsed = enrichment?.parsedAntenna {
                    if let type = parsed.type {
                        badgeCapsule(type.rawValue, color: .blue)
                    }
                    ForEach(parsed.bands.prefix(3), id: \.self) { band in
                        badgeCapsule(band, color: .green)
                    }
                } else if let antenna = favorite.antenna {
                    Text(antenna)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let snr = enrichment?.snrHF ?? enrichment?.snrAll {
                    snrLabel(snr)
                }
            }

            Text("\(favorite.host):\(favorite.port)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func badgeCapsule(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
    }

    private func snrLabel(_ snr: Int) -> some View {
        let color: Color = snr < 15 ? .red : snr < 25 ? .yellow : .green
        return HStack(spacing: 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("SNR \(snr)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func loadData() async {
        loadFavorites()
        await enrichFavorites()
    }

    private func loadFavorites() {
        let descriptor = FetchDescriptor<WebSDRFavorite>(
            sortBy: [SortDescriptor(\.addedDate, order: .reverse)]
        )
        favorites = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func enrichFavorites() async {
        // Convert favorites to minimal receivers for fetching
        for favorite in favorites {
            if let status = await KiwiSDRStatusFetcher.shared.fetchStatus(
                host: favorite.host, port: favorite.port
            ) {
                enrichments[favorite.hostPort] = status
            }
        }
    }

    private func deleteFavorites(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(favorites[index])
        }
        try? modelContext.save()
        loadFavorites()
    }

    private func addFavorite(
        hostPort: String, name: String, location: String, antenna: String?
    ) {
        let favorite = WebSDRFavorite(
            hostPort: hostPort,
            displayName: name,
            location: location,
            antenna: antenna
        )
        modelContext.insert(favorite)
        try? modelContext.save()
        loadFavorites()
    }
}

// MARK: - AddReceiverSheet

/// Sheet for manually adding a private/unlisted receiver.
struct AddReceiverSheet: View {
    // MARK: Internal

    let onAdd: (String, String, String, String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Host (e.g., sdr.example.com)", text: $hostInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $portInput)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Receiver Address")
                }

                if let name = fetchedName {
                    Section("Receiver Info") {
                        LabeledContent("Name", value: name)
                        if let loc = fetchedLocation {
                            LabeledContent("Location", value: loc)
                        }
                        if let ant = fetchedAntenna {
                            LabeledContent("Antenna", value: ant)
                        }
                    }
                }

                if let error = validationError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        Task { await validate() }
                    } label: {
                        if isValidating {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Checking...")
                            }
                        } else {
                            Text("Check Connection")
                        }
                    }
                    .disabled(hostInput.isEmpty || isValidating)
                }
            }
            .navigationTitle("Add Receiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let hp = "\(hostInput):\(portInput)"
                        onAdd(
                            hp,
                            fetchedName ?? hostInput,
                            fetchedLocation ?? "",
                            fetchedAntenna
                        )
                        dismiss()
                    }
                    .disabled(fetchedName == nil)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var hostInput = ""
    @State private var portInput = "8073"
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var fetchedName: String?
    @State private var fetchedLocation: String?
    @State private var fetchedAntenna: String?

    private func validate() async {
        isValidating = true
        validationError = nil
        fetchedName = nil
        fetchedLocation = nil
        fetchedAntenna = nil
        defer { isValidating = false }

        let port = Int(portInput) ?? 8_073
        let status = await KiwiSDRStatusFetcher.shared.fetchStatus(
            host: hostInput, port: port
        )

        if let status {
            fetchedName = status.antenna.isEmpty
                ? hostInput : "\(hostInput) KiwiSDR"
            fetchedLocation = status.grid ?? ""
            fetchedAntenna = status.antenna.isEmpty ? nil : status.antenna
            // Use software version to confirm it's a real KiwiSDR
            if status.softwareVersion != nil {
                fetchedName = "\(hostInput) KiwiSDR"
            }
        } else {
            validationError =
                "Could not connect to \(hostInput):\(port). "
                    + "Check the address and ensure the receiver is online."
        }
    }
}
