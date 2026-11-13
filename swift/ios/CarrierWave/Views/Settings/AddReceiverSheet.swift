import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - AddReceiverSheet

/// Sheet for manually adding a private/unlisted receiver.
struct AddReceiverSheet: View {
    // MARK: Internal

    let onAdd: (String, String, String, String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "Host (e.g., sdr.example.com)",
                        text: $hostInput
                    )
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
