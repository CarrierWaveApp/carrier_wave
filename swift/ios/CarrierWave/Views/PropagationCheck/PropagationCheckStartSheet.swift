import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - PropagationCheckStartSheet

/// Configuration form for a new propagation check.
struct PropagationCheckStartSheet: View {
    // MARK: Lifecycle

    init(onStart: @escaping (PropagationCheckConfig) -> Void) {
        self.onStart = onStart

        let profile = UserProfileService.shared.getProfile()
        _callsign = State(initialValue: profile?.callsign ?? "")
        _userGrid = State(initialValue: profile?.grid ?? "")
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                callsignSection
                bandsSection
                durationSection
                gridSection
                advancedSection
            }
            .navigationTitle("New Propagation Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        startCheck()
                    }
                    .disabled(!canStart)
                }
            }
            .onChange(of: gridService.currentGrid) { _, newValue in
                if let grid = newValue {
                    userGrid = grid
                    persistGrid(grid)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var gridService = GridLocationService()

    @State private var callsign: String
    @State private var userGrid: String
    @State private var selectedBands: Set<String> = Set(BandUtilities.standardBands.filter { isHFBand($0) })
    @State private var durationMinutes: Int = 15
    @State private var hasDurationCap: Bool = true
    @State private var transmitMode: PropagationTransmitMode = .passive

    private let onStart: (PropagationCheckConfig) -> Void

    private var canStart: Bool {
        !callsign.trimmingCharacters(in: .whitespaces).isEmpty
            && MaidenheadConverter.isValid(userGrid)
            && !selectedBands.isEmpty
    }

    private var callsignSection: some View {
        Section {
            TextField("Callsign", text: $callsign)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
        } header: {
            Text("Your Callsign")
        } footer: {
            Text("Suffix variants like /P, /M, /MM, /QRP are matched automatically.")
        }
    }

    private var bandsSection: some View {
        Section {
            ForEach(BandUtilities.standardBands, id: \.self) { band in
                Toggle(isOn: bandBinding(band)) {
                    HStack {
                        Circle()
                            .fill(BandColors.color(for: band))
                            .frame(width: 14, height: 14)
                        Text(band)
                            .font(.body.monospaced())
                    }
                }
            }
        } header: {
            Text("Bands of Interest")
        } footer: {
            Text("Spots outside these bands are filtered out. Defaults to all HF bands.")
        }
    }

    private var durationSection: some View {
        Section {
            Toggle("Auto-stop after duration", isOn: $hasDurationCap)
            if hasDurationCap {
                Stepper(value: $durationMinutes, in: 5 ... 120, step: 5) {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text("\(durationMinutes) min")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        } header: {
            Text("Lifecycle")
        } footer: {
            Text("PSK Reporter has a 15 min minimum window — shorter FT8 sessions may show no spots.")
        }
    }

    private var gridSection: some View {
        Section {
            HStack {
                TextField("Grid (Maidenhead)", text: $userGrid)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button {
                    gridService.requestGrid()
                } label: {
                    if gridService.isLocating {
                        ProgressView()
                    } else {
                        Image(systemName: "location.fill")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(gridService.isLocating)
            }
            if !userGrid.isEmpty, !MaidenheadConverter.isValid(userGrid) {
                Text("Not a valid grid (e.g. CM87, FN42pr)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Your Location")
        } footer: {
            Text(
                "Used to compute distance to each skimmer. Stored on the artifact so the result stays accurate"
                    + " even if you move."
            )
        }
    }

    private var advancedSection: some View {
        Section {
            Picker("Transmit", selection: $transmitMode) {
                Text("Passive (I'll CQ myself)").tag(PropagationTransmitMode.passive)
                Text("Auto-CQ (CW)").tag(PropagationTransmitMode.autoCW)
                Text("Auto-CQ (FT8)").tag(PropagationTransmitMode.autoFT8)
            }
            .pickerStyle(.menu)
            if transmitMode == .autoCW {
                if let reason = PropagationAutoCQController.unavailableReason(for: .autoCW) {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label(
                        "We'll key \"CQ CQ DE \(callsign.uppercased()) K\" every 30 s. Stop kills TX immediately.",
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else if transmitMode == .autoFT8 {
                Label(
                    "FT8 Auto-CQ: start FT8 from your usual session view; this check will watch PSK Reporter"
                        + " in parallel.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Advanced")
        }
    }

    private func bandBinding(_ band: String) -> Binding<Bool> {
        Binding(
            get: { selectedBands.contains(band) },
            set: { isOn in
                if isOn {
                    selectedBands.insert(band)
                } else {
                    selectedBands.remove(band)
                }
            }
        )
    }

    private func startCheck() {
        let trimmedCallsign = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let bands = selectedBands.sorted { lhs, rhs in
            let order = BandUtilities.bandOrder
            return (order.firstIndex(of: lhs) ?? Int.max) < (order.firstIndex(of: rhs) ?? Int.max)
        }
        let cap: TimeInterval? = hasDurationCap ? TimeInterval(durationMinutes * 60) : nil
        let config = PropagationCheckConfig(
            callsign: trimmedCallsign,
            bands: bands,
            transmitMode: transmitMode,
            userGrid: userGrid.uppercased(),
            startedAt: Date(),
            durationCap: cap
        )
        // Persist the grid back to the user profile if they entered it manually.
        persistGrid(userGrid)
        dismiss()
        onStart(config)
    }

    private func persistGrid(_ grid: String) {
        let trimmed = grid.trimmingCharacters(in: .whitespaces).uppercased()
        guard MaidenheadConverter.isValid(trimmed) else {
            return
        }
        var profile = UserProfileService.shared.getProfile() ?? UserProfile(callsign: callsign.uppercased())
        if profile.grid != trimmed {
            profile.grid = trimmed
            try? UserProfileService.shared.saveProfile(profile)
        }
    }
}

// MARK: - HF helper

nonisolated private func isHFBand(_ band: String) -> Bool {
    let bands: Set = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m"]
    return bands.contains(band)
}
