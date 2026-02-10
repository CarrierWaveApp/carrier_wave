import CarrierWaveCore
import SwiftUI
import UIKit

// MARK: - SpotLogSheet

/// Half-sheet for logging a QSO from a tapped spot.
/// Pre-fills callsign, frequency, mode, and park reference from the spot data.
struct SpotLogSheet: View {
    // MARK: Internal

    let spot: EnrichedSpot
    let manager: ActivityLogManager
    let onLogged: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                spotInfoSection
                rstSection
                moreFieldsSection
                logButton
                profileInfoFooter
            }
            .navigationTitle("Log QSO from Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var rstSent = ""
    @State private var rstReceived = ""
    @State private var theirGrid = ""
    @State private var state = ""
    @State private var notes = ""
    @State private var showMoreFields = false

    private var defaultRST: String {
        let mode = spot.spot.mode.uppercased()
        if mode == "SSB" || mode == "USB" || mode == "LSB"
            || mode == "FM" || mode == "AM"
        {
            return "59"
        }
        return "599"
    }

    private var effectiveRSTSent: String {
        rstSent.isEmpty ? defaultRST : rstSent
    }

    private var effectiveRSTReceived: String {
        rstReceived.isEmpty ? defaultRST : rstReceived
    }

    // MARK: - Sections

    private var spotInfoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(spot.spot.callsign)
                    .font(.title3.monospaced().weight(.bold))

                HStack(spacing: 4) {
                    Text(FrequencyFormatter.format(spot.spot.frequencyMHz))
                        .font(.subheadline.monospaced())
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(spot.spot.band) \(spot.spot.mode)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let parkRef = spot.spot.parkRef {
                    HStack(spacing: 4) {
                        Image(systemName: "tree.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(parkRef)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let parkName = spot.spot.parkName {
                            Text("- \(parkName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var rstSection: some View {
        Section {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RST Sent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(defaultRST, text: $rstSent)
                        .font(.body.monospaced())
                        .keyboardType(.numberPad)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("RST Rcvd")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(defaultRST, text: $rstReceived)
                        .font(.body.monospaced())
                        .keyboardType(.numberPad)
                }
            }
        }
    }

    private var moreFieldsSection: some View {
        Section {
            DisclosureGroup("More Fields", isExpanded: $showMoreFields) {
                TextField("Their Grid", text: $theirGrid)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("State/Province", text: $state)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("Notes", text: $notes)
            }
        }
    }

    private var logButton: some View {
        Section {
            Button {
                logQSO()
            } label: {
                Text("Log QSO")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var profileInfoFooter: some View {
        Section {
            if let profile = manager.currentProfile {
                Text(
                    "Logging as \(manager.activeLog?.myCallsign ?? "?")"
                        + " · \(profile.name)"
                        + (profile.power.map { " · \($0)W" } ?? "")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func logQSO() {
        let qso = manager.logQSO(
            callsign: spot.spot.callsign,
            band: spot.spot.band,
            mode: spot.spot.mode,
            frequency: spot.spot.frequencyMHz,
            rstSent: effectiveRSTSent,
            rstReceived: effectiveRSTReceived,
            theirGrid: theirGrid.isEmpty ? nil : theirGrid,
            theirParkReference: spot.spot.parkRef,
            notes: notes.isEmpty ? nil : notes,
            state: state.isEmpty ? nil : state
        )

        if qso != nil {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onLogged()
            dismiss()
        }
    }
}
