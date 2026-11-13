import CarrierWaveData
import SwiftUI

// MARK: - CallsignChangePendingRow

/// Settings-root row label shown while a callsign change checklist is pending.
struct CallsignChangePendingRow: View {
    let pending: PendingCallsignChange

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Finish Callsign Change")
                    .font(.subheadline.weight(.medium))
                Text("\(pending.oldCallsign) → \(pending.newCallsign)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - CallsignChangeGuideView

/// Guided checklist shown after a callsign change. Lists every connected
/// service that still needs the new callsign, auto-verifying the ones the
/// app can check itself and deep-linking into the relevant settings screen
/// (or website) for the rest.
struct CallsignChangeGuideView: View {
    // MARK: Internal

    var syncService: SyncService?
    var tourState: TourState?

    var body: some View {
        List {
            if let change {
                headerSection(change)
                if steps.isEmpty {
                    noServicesSection
                } else {
                    stepsSection
                }
                dismissSection
            } else {
                Section {
                    Text("No callsign change in progress.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Callsign Change")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .confirmationDialog(
            "Some services haven't been updated yet. You can reopen this "
                + "checklist later from Settings.",
            isPresented: $showingDismissConfirmation,
            titleVisibility: .visible
        ) {
            Button("Dismiss Checklist", role: .destructive) {
                finish()
            }
            Button("Keep Checklist", role: .cancel) {}
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var change: PendingCallsignChange?
    @State private var steps: [CallsignChangeStep] = []
    @State private var showingDismissConfirmation = false

    private var guide: CallsignChangeGuide {
        .shared
    }

    private var allDone: Bool {
        steps.allSatisfy { guide.isDone($0) }
    }

    private var noServicesSection: some View {
        Section {
            Text("No connected services need updates.")
                .foregroundStyle(.secondary)
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach(steps) { step in
                stepRow(step)
            }
        } header: {
            Text("Connected Services")
        } footer: {
            Text(
                "Steps with a checkmark were verified automatically. Tap the "
                    + "circle to mark the others done as you complete them."
            )
        }
    }

    private var dismissSection: some View {
        Section {
            Button(allDone ? "Finish" : "Dismiss Checklist") {
                if allDone {
                    finish()
                } else {
                    showingDismissConfirmation = true
                }
            }
            .frame(maxWidth: .infinity)
        } footer: {
            if !allDone {
                Text("The checklist stays available in Settings until every step is handled.")
            }
        }
    }

    private func headerSection(_ change: PendingCallsignChange) -> some View {
        Section {
            HStack(spacing: 8) {
                Text(change.oldCallsign)
                    .font(.title3.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("changed to")
                Text(change.newCallsign)
                    .font(.title3.monospaced().weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        } footer: {
            Text(
                "Your profile, callsign aliases, logging defaults, and Carrier "
                    + "Wave account were updated automatically. \(change.oldCallsign) "
                    + "was kept as a previous callsign so your existing QSOs stay "
                    + "grouped. The services below still reference your callsign "
                    + "and need a quick check."
            )
        }
    }

    @ViewBuilder
    private func stepRow(_ step: CallsignChangeStep) -> some View {
        if let destination = step.destination {
            NavigationLink {
                destinationView(destination)
            } label: {
                stepRowContent(step)
            }
        } else {
            stepRowContent(step)
        }
    }

    private func stepRowContent(_ step: CallsignChangeStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                guide.toggleDone(step)
                reload()
            } label: {
                Image(systemName: guide.isDone(step) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(guide.isDone(step) ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(step.autoChecked)
            .accessibilityLabel(
                guide.isDone(step) ? "\(step.title) done" : "Mark \(step.title) done"
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: step.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(step.title)
                        .font(.subheadline.weight(.medium))
                }
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = step.externalURL {
                    Link(destination: url) {
                        Label(url.host() ?? "Open website", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func destinationView(_ destination: CallsignChangeDestination) -> some View {
        switch destination {
        case .qrzLogbook:
            QRZSettingsView(syncService: syncService)
        case .qrzLookup:
            QRZCallbookSettingsView()
        case .lotw:
            LoTWSettingsView(syncService: syncService)
        case .eqsl:
            EQSLSettingsView()
        case .clublog:
            ClubLogSettingsView()
        case .lofi:
            LoFiSettingsView(tourState: tourState ?? TourState(), syncService: syncService)
        }
    }

    private func reload() {
        change = guide.pending
        steps = guide.steps()
    }

    private func finish() {
        guide.dismiss()
        dismiss()
    }
}
