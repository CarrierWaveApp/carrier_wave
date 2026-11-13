import CarrierWaveCore
import SwiftUI

/// Confirmation sheet for qsy://log URIs — shows pre-filled QSO data for review.
struct QSYLogConfirmationSheet: View {
    // MARK: Internal

    let confirmation: QSYLogConfirmation
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Callsign", confirmation.callsign)
                    row("Frequency", FrequencyFormatter.formatWithUnit(confirmation.frequencyMHz))
                    row("Mode", confirmation.mode)
                }

                if hasSignalInfo {
                    Section("Signal") {
                        if let rst = confirmation.rstSent {
                            row("RST Sent", rst)
                        }
                        if let rst = confirmation.rstReceived {
                            row("RST Received", rst)
                        }
                    }
                }

                if hasStationInfo {
                    Section("Station") {
                        if let grid = confirmation.grid {
                            row("Grid", grid)
                        }
                        if let ref = confirmation.ref {
                            let label = confirmation.refType?.uppercased() ?? "Ref"
                            row(label, ref)
                        }
                    }
                }

                if hasExchangeInfo {
                    Section("Exchange") {
                        if let contest = confirmation.contest {
                            row("Contest", contest)
                        }
                        if let srx = confirmation.srx {
                            row("SRX", srx)
                        }
                        if let stx = confirmation.stx {
                            row("STX", stx)
                        }
                    }
                }

                if let comment = confirmation.comment {
                    Section("Notes") {
                        Text(comment)
                            .font(.subheadline)
                    }
                }

                if let source = confirmation.source {
                    Section {
                        row("Source", source)
                    }
                }
            }
            .navigationTitle("Log QSO?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log QSO", action: onConfirm)
                        .bold()
                }
            }
        }
    }

    // MARK: Private

    private var hasSignalInfo: Bool {
        confirmation.rstSent != nil || confirmation.rstReceived != nil
    }

    private var hasStationInfo: Bool {
        confirmation.grid != nil || confirmation.ref != nil
    }

    private var hasExchangeInfo: Bool {
        confirmation.contest != nil || confirmation.srx != nil || confirmation.stx != nil
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
