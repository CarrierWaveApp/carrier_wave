// Activation Metadata Edit Sheet
//
// Form for editing activation metadata (title, park reference, watts)
// after an activation is completed.

import CarrierWaveCore
import SwiftUI

// MARK: - ActivationMetadataEditResult

/// Result of editing activation metadata
struct ActivationMetadataEditResult {
    let title: String?
    let watts: Int?
    let radio: String?
    /// New park reference, if changed (nil means no change)
    let newParkReference: String?
}

// MARK: - ActivationMetadataEditSheet

struct ActivationMetadataEditSheet: View {
    // MARK: Lifecycle

    init(
        activation: POTAActivation,
        metadata: ActivationMetadata?,
        userGrid: String?,
        onSave: @escaping (ActivationMetadataEditResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.activation = activation
        self.userGrid = userGrid
        self.onSave = onSave
        self.onCancel = onCancel

        _title = State(initialValue: metadata?.title ?? "")
        _wattsText = State(initialValue: metadata?.watts.map { String($0) } ?? "")
        _radio = State(initialValue: activation.qsos.compactMap(\.myRig).first)
        _parkReference = State(initialValue: activation.parkReference)
        originalParkReference = activation.parkReference
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Activation title", text: $title)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Title")
                } footer: {
                    Text("Optional name for this activation (e.g., \"Field Day at Blue Ridge\")")
                }

                Section {
                    TextField("Watts", text: $wattsText)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Power")
                } footer: {
                    Text("Typical transmit power in watts during this activation")
                }

                Section {
                    Button {
                        showRadioPicker = true
                    } label: {
                        HStack {
                            Text("Radio")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(radio ?? "None")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Radio")
                }

                Section {
                    ParkEntryField(
                        parkReference: $parkReference,
                        label: "Park Reference",
                        placeholder: "K-1234",
                        userGrid: userGrid,
                        defaultCountry: "US"
                    )
                } header: {
                    Text("Park")
                } footer: {
                    if parkChanged {
                        Label(
                            "Changing the park will update all QSOs and clear POTA upload status.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Edit Activation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .confirmationDialog(
                "Change Park Reference",
                isPresented: $showParkChangeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Change Park", role: .destructive) {
                    commitSave(confirmParkChange: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    """
                    This will update all \(activation.qsoCount) QSO(s) from \
                    \(originalParkReference) to \(normalizedParkReference) \
                    and clear their POTA upload status.
                    """
                )
            }
        }
        .sheet(isPresented: $showRadioPicker) {
            RadioPickerSheet(selection: $radio)
                .presentationDetents([.medium])
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Private

    @State private var title: String
    @State private var wattsText: String
    @State private var radio: String?
    @State private var parkReference: String
    @State private var showParkChangeConfirmation = false
    @State private var showRadioPicker = false

    private let activation: POTAActivation
    private let userGrid: String?
    private let onSave: (ActivationMetadataEditResult) -> Void
    private let onCancel: () -> Void
    private let originalParkReference: String

    private var parsedWatts: Int? {
        guard !wattsText.isEmpty else {
            return nil
        }
        return Int(wattsText)
    }

    private var normalizedParkReference: String {
        ParkReference.sanitizeMulti(parkReference) ?? parkReference.uppercased()
    }

    private var parkChanged: Bool {
        normalizedParkReference != originalParkReference
    }

    private func save() {
        if parkChanged {
            showParkChangeConfirmation = true
        } else {
            commitSave(confirmParkChange: false)
        }
    }

    private func commitSave(confirmParkChange: Bool) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let result = ActivationMetadataEditResult(
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            watts: parsedWatts,
            radio: radio,
            newParkReference: confirmParkChange ? normalizedParkReference : nil
        )
        onSave(result)
    }
}
