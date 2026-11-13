import SwiftUI

// MARK: - SessionOperationType

/// The kind of operating the wizard is being opened for. Each case drives a
/// tailored `SessionStartSheet` layout — different sections, prominence, and
/// niceties — so contests, activations, and casual ops no longer share one
/// undifferentiated form.
///
/// `.activation` is the full-featured default (programs front-and-centre,
/// pack checklist, contest still reachable as an optional add-on), so generic
/// entry points (logger "+", map park selection) keep their existing behaviour.
enum SessionOperationType: String, CaseIterable, Identifiable {
    /// POTA / SOTA / WWFF / TOTA — portable program operating.
    case activation
    /// Ragchew and random QSOs — the simplest, no-program flow.
    case casual
    /// Scored contest operating with exchange and Cabrillo export.
    case contest

    // MARK: Internal

    var id: String {
        rawValue
    }

    /// Navigation bar title for the wizard.
    var navigationTitle: String {
        switch self {
        case .activation: "Activate"
        case .casual: "Casual Session"
        case .contest: "Contest"
        }
    }

    /// Label for the pinned Start button.
    var startButtonTitle: String {
        switch self {
        case .activation: "Start Activation"
        case .casual: "Start Session"
        case .contest: "Start Contest"
        }
    }

    /// Summary of what hides behind the collapsed "More Options" row.
    var moreOptionsSummary: String {
        switch self {
        case .activation: "Station · People · Contest · WebSDR · Pack Checklist · Notes"
        case .casual: "Station · WebSDR · Notes"
        case .contest: "Station · Operators · WebSDR · Notes"
        }
    }
}

// MARK: - SessionStartSheet Per-Type Wizards

extension SessionStartSheet {
    /// The body sections that follow the shared hero / loadouts / station
    /// block, dispatched by `operationType`. Mode and frequency are common to
    /// all three but their placement (relative to the "what" — program or
    /// contest) differs, so each builder lists them explicitly for clarity.
    @ViewBuilder
    var wizardSections: some View {
        switch operationType {
        case .activation:
            activationWizardSections
        case .casual:
            casualWizardSections
        case .contest:
            contestWizardSections
        }
    }

    // MARK: - Activation

    /// Portable program operating. Two essential blocks — *what am I
    /// activating* and *radio* — then everything optional (station tweaks,
    /// people, contest add-on, WebSDR, pack checklist, notes) behind one
    /// collapsed "More Options" row.
    @ViewBuilder
    private var activationWizardSections: some View {
        radioSection
        activationSection
        gearSection
        if showMoreOptions {
            callsignSection
            peopleSection
            contestSection
            sdrSection
            gearRemindersSection
            notesSection
        } else {
            moreOptionsRow
        }
    }

    // MARK: - Casual

    /// Ragchew & random QSOs. Radio is the only essential; no program picker,
    /// no contest, no pack checklist, no multi-op.
    @ViewBuilder
    private var casualWizardSections: some View {
        radioSection
        gearSection
        if showMoreOptions {
            callsignSection
            sdrSection
            notesSection
        } else {
            moreOptionsRow
        }
    }

    // MARK: - Contest

    /// Scored contest operating. The contest picker leads (*which contest?*)
    /// and stays visible with the radio essentials; station, operators,
    /// WebSDR, and notes fold into "More Options".
    @ViewBuilder
    private var contestWizardSections: some View {
        radioSection
        contestSection
        gearSection
        if showMoreOptions {
            callsignSection
            operatorsSection
            sdrSection
            notesSection
        } else {
            moreOptionsRow
        }
    }

    // MARK: - More Options

    /// Collapsed placeholder for the optional tail. One tap swaps it for the
    /// full sections; there's no re-collapse — once you're in the weeds you
    /// stay there for this presentation.
    private var moreOptionsRow: some View {
        Section {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showMoreOptions = true
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("More Options", systemImage: "ellipsis.circle")
                        Text(operationType.moreOptionsSummary)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }
}
