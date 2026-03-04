import CarrierWaveData
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
                if showingRespotPhase {
                    respotCommentSection
                    respotActionSection
                } else {
                    spotInfoSection
                    rstSection
                    moreFieldsSection
                    logButton
                    profileInfoFooter
                }
            }
            .navigationTitle(showingRespotPhase ? "Respot" : "Log QSO from Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(showingRespotPhase ? "Skip" : "Cancel") { dismiss() }
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @AppStorage("potaHunterRespotEnabled") private var respotEnabled = true
    @AppStorage("potaHunterRespotCustomMessage") private var respotCustomMessage = false
    @AppStorage("potaHunterRespotDefaultMessage") private var respotDefaultMessage = "tnx"

    @State private var rstSent = ""
    @State private var rstReceived = ""
    @State private var theirGrid = ""
    @State private var state = ""
    @State private var notes = ""
    @State private var showMoreFields = false
    @State private var showingRespotPhase = false
    @State private var respotComment = ""

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

    // MARK: - Respot Logic

    private var canRespot: Bool {
        guard respotEnabled else {
            return false
        }
        guard spot.spot.source == .pota else {
            return false
        }
        guard spot.spot.parkRef != nil else {
            return false
        }
        guard let callsign = manager.activeLog?.myCallsign, !callsign.isEmpty else {
            return false
        }
        guard POTAAuthService().hasStoredCredentials() else {
            return false
        }
        return true
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

    // MARK: - Respot Sections

    private var respotCommentSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(spot.spot.callsign)
                    .font(.title3.monospaced().weight(.bold))
                if let parkRef = spot.spot.parkRef {
                    Text(parkRef)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Comment", text: $respotComment)
        } header: {
            Text("Respot Comment")
        } footer: {
            Text("QSO logged. Post a respot to help other hunters find this station.")
        }
    }

    private var respotActionSection: some View {
        Section {
            Button {
                fireRespot(comment: respotComment)
                dismiss()
            } label: {
                Text("Send Respot")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private func fireRespot(comment: String) {
        guard let parkRef = spot.spot.parkRef,
              let myCallsign = manager.activeLog?.myCallsign
        else {
            return
        }

        let activator = spot.spot.callsign
        let frequency = spot.spot.frequencyKHz
        let mode = spot.spot.mode
        let trimmedComment = comment.trimmingCharacters(in: .whitespaces)
        let finalComment = trimmedComment.isEmpty ? nil : trimmedComment

        Task {
            do {
                let client = POTAClient(authService: POTAAuthService())
                _ = try await client.postRespot(
                    activator: activator,
                    spotter: myCallsign,
                    reference: parkRef,
                    frequency: frequency,
                    mode: mode,
                    comments: finalComment
                )
            } catch {
                SyncDebugLog.shared.error(
                    "Respot failed: \(error.localizedDescription)", service: .pota
                )
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

        guard let qso else {
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onLogged()

        // Background lookup to detect callsign changes and fill metadata
        let context = modelContext
        Task {
            let service = CallsignLookupService(modelContext: context)
            guard let info = await service.lookup(qso.callsign) else {
                return
            }
            if qso.name == nil { qso.name = info.name }
            if qso.theirGrid == nil { qso.theirGrid = info.grid }
            if qso.state == nil { qso.state = info.state }
            if qso.country == nil { qso.country = info.country }
            if qso.qth == nil { qso.qth = info.qth }
            if qso.theirLicenseClass == nil { qso.theirLicenseClass = info.licenseClass }
            qso.callsignChangeNote = info.callsignChangeNote
            try? context.save()
        }

        if canRespot {
            if respotCustomMessage {
                respotComment = respotDefaultMessage
                showingRespotPhase = true
            } else {
                fireRespot(comment: respotDefaultMessage)
                dismiss()
            }
        } else {
            dismiss()
        }
    }
}
