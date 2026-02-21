import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - HiddenQSOsSheet

/// Sheet showing hidden (deleted) QSOs for the current session with option to restore
struct HiddenQSOsSheet: View {
    // MARK: Internal

    let sessionId: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if hiddenQSOs.isEmpty {
                    ContentUnavailableView(
                        "No Deleted QSOs",
                        systemImage: "checkmark.circle",
                        description: Text("All QSOs in this session are visible")
                    )
                } else {
                    List {
                        ForEach(hiddenQSOs) { qso in
                            HiddenQSORow(
                                qso: qso,
                                onRestore: {
                                    restoreQSO(qso)
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Deleted QSOs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                fetchHiddenQSOs()
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Hidden QSOs for the current session (manually fetched to avoid full table scan)
    @State private var hiddenQSOs: [QSO] = []

    private func fetchHiddenQSOs() {
        guard let sessionId else {
            hiddenQSOs = []
            return
        }

        let predicate = #Predicate<QSO> { qso in
            qso.isHidden && qso.loggingSessionId == sessionId
        }

        let descriptor = FetchDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            hiddenQSOs = try modelContext.fetch(descriptor)
        } catch {
            hiddenQSOs = []
        }
    }

    private func restoreQSO(_ qso: QSO) {
        qso.isHidden = false
        try? modelContext.save()
        // Refresh the list after restoring
        fetchHiddenQSOs()
    }
}

// MARK: - HiddenQSORow

/// A row displaying a hidden QSO with restore button
struct HiddenQSORow: View {
    let qso: QSO
    let onRestore: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(qso.callsign)
                    .font(.headline.monospaced())

                HStack(spacing: 8) {
                    Text(qso.timestamp, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(qso.band)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())

                    Text(qso.mode)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            Button {
                onRestore()
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - DeleteSessionConfirmationSheet

/// Sheet requiring user to type "delete" to confirm session deletion
struct DeleteSessionConfirmationSheet: View {
    // MARK: Internal

    let qsoCount: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)

                VStack(spacing: 8) {
                    Text("Delete Session?")
                        .font(.title2.weight(.bold))

                    Text(
                        "This will hide \(qsoCount) QSO\(qsoCount == 1 ? "" : "s") permanently. "
                            + "They will not sync to any services."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Type \"delete\" to confirm:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("", text: $confirmationText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isConfirmationValid ? Color.red : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .focused($isTextFieldFocused)
                }

                VStack(spacing: 12) {
                    Button(role: .destructive) {
                        onConfirm()
                    } label: {
                        Text("Delete Session")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!isConfirmationValid)

                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                }

                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
            .onAppear {
                isTextFieldFocused = true
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
    }

    // MARK: Private

    @State private var confirmationText = ""
    @FocusState private var isTextFieldFocused: Bool

    private var isConfirmationValid: Bool {
        confirmationText.lowercased() == "delete"
    }
}

// MARK: - SessionBandEditSheet

/// Sheet for selecting a new band/frequency during an active session.
/// Shows live POTA/RBN spot data with recommended clear frequencies.
struct SessionBandEditSheet: View {
    // MARK: Internal

    let currentFrequency: Double?
    let currentMode: String
    let onSelectFrequency: (Double) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FrequencyBandView(
                        selectedMode: currentMode,
                        frequency: $frequencyText,
                        detailBand: $bandDetail
                    )
                } footer: {
                    Text("Tip: Type a frequency like 14.061 in the command box to set it directly.")
                }
            }
            .navigationTitle("Pick Frequency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onCancel() }
                }
            }
            .sheet(item: $bandDetail) { band in
                BandActivitySheet(
                    suggestion: band,
                    frequency: $frequencyText
                )
            }
            .onChange(of: frequencyText) { _, newValue in
                guard hasInitialized else {
                    return
                }
                if let freq = FrequencyFormatter.parse(newValue) {
                    onSelectFrequency(freq)
                }
            }
            .task {
                if let freq = currentFrequency {
                    frequencyText = FrequencyFormatter.format(freq)
                }
                hasInitialized = true
            }
        }
    }

    // MARK: Private

    @State private var frequencyText = ""
    @State private var bandDetail: BandSuggestion?
    @State private var hasInitialized = false
}

// MARK: - SessionModeEditSheet

/// Sheet for selecting a new mode during an active session
struct SessionModeEditSheet: View {
    // MARK: Internal

    let currentMode: String
    let onSelectMode: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(modeOptions, id: \.self) { mode in
                        Button {
                            onSelectMode(mode)
                        } label: {
                            HStack {
                                Text(mode)
                                    .font(.headline)

                                Spacer()

                                if currentMode.uppercased() == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Select Mode")
                }
            }
            .navigationTitle("Change Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }

    // MARK: Private

    private let modeOptions = ["CW", "SSB", "FT8", "FT4", "RTTY", "AM", "FM"]
}
