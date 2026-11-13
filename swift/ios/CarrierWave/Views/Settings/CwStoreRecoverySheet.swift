// cw-store Recovery Sheet
//
// Offline passphrase entry to recover an orphaned encrypted store: unwraps the
// cached recovery envelope with the sync passphrase, restores the at-rest key,
// and re-opens the store. No network. See CwStoreKeyRecovery.

import SwiftUI

// MARK: - CwStoreRecoverySheet

struct CwStoreRecoverySheet: View {
    // MARK: Internal

    /// Called with `true` when the store was recovered and re-opened.
    let onFinished: (Bool) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Sync passphrase", text: $passphrase)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text(
                        "Enter your sync passphrase to unlock the on-device database. "
                            + "This happens entirely offline — no internet required."
                    )
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await recover() }
                    } label: {
                        HStack {
                            Spacer()
                            if isRecovering {
                                ProgressView()
                            } else {
                                Text("Recover Database")
                            }
                            Spacer()
                        }
                    }
                    .disabled(passphrase.isEmpty || isRecovering)
                }
            }
            .navigationTitle("Recover Database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinished(false) }
                        .disabled(isRecovering)
                }
            }
        }
        .interactiveDismissDisabled(isRecovering)
    }

    // MARK: Private

    @State private var passphrase = ""
    @State private var isRecovering = false
    @State private var errorMessage: String?

    private func recover() async {
        isRecovering = true
        errorMessage = nil
        defer { isRecovering = false }

        let recovered = await CwStoreKeyRecovery.recover(passphrase: passphrase)
        if recovered {
            onFinished(true)
        } else {
            errorMessage = "Couldn't unlock the database with that passphrase. Check it and try again."
        }
    }
}
