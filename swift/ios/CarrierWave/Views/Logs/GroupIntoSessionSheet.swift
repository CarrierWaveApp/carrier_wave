import CarrierWaveData
import SwiftUI

// MARK: - GroupIntoSessionResult

/// Result produced by `GroupIntoSessionSheet` when the user confirms.
struct GroupIntoSessionResult {
    let title: String?
    let myCallsign: String
    let activationType: ActivationType
    let parkReference: String?
    let sotaReference: String?
    let wwffReference: String?
    let notes: String?
    /// When `true`, QSOs already linked to another session should be
    /// unlinked and moved into the new session.
    let unlinkFromExistingSessions: Bool
}

// MARK: - GroupIntoSessionSheet

/// Sheet for creating a new completed `LoggingSession` from a set of already-logged QSOs.
///
/// Unlike `SessionStartSheet`, this does not start an active session — it just groups
/// existing QSOs under a single session record for organization and stats.
struct GroupIntoSessionSheet: View {
    // MARK: Lifecycle

    init(
        summary: Summary,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (GroupIntoSessionResult) -> Void
    ) {
        self.summary = summary
        self.onCancel = onCancel
        self.onCreate = onCreate
        _myCallsign = State(initialValue: summary.suggestedCallsign)
        _activationType = State(initialValue: summary.suggestedActivationType)
        _parkReference = State(initialValue: summary.suggestedParkReference ?? "")
        _sotaReference = State(initialValue: summary.suggestedSOTAReference ?? "")
        _wwffReference = State(initialValue: summary.suggestedWWFFReference ?? "")
    }

    // MARK: Internal

    /// Pre-computed summary of the selected QSOs used to pre-fill fields and
    /// describe the grouping to the user.
    struct Summary: Identifiable {
        let id = UUID()
        let totalSelected: Int
        let eligibleCount: Int
        let skippedAlreadyInSession: Int
        let existingSessions: [ExistingSession]
        let orphanedSessionRefs: Int
        let dateRange: ClosedRange<Date>?
        let uniqueStations: Int
        let suggestedCallsign: String
        let suggestedActivationType: ActivationType
        let suggestedParkReference: String?
        let suggestedSOTAReference: String?
        let suggestedWWFFReference: String?
    }

    /// A real `LoggingSession` that one or more selected QSOs already live in.
    struct ExistingSession: Identifiable {
        let id: UUID
        let title: String
        let qsoCount: Int
    }

    let summary: Summary
    let onCancel: () -> Void
    let onCreate: (GroupIntoSessionResult) -> Void

    var body: some View {
        NavigationStack {
            Form {
                summarySection
                existingSessionsSection
                orphanedSection
                callsignSection
                activationSection
                referencesSection
                titleNotesSection
            }
            .navigationTitle("Group into Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { submit() }
                        .disabled(!canSubmit)
                }
            }
        }
    }

    // MARK: Private

    @State private var title = ""
    @State private var myCallsign: String
    @State private var activationType: ActivationType
    @State private var parkReference: String
    @State private var sotaReference: String
    @State private var wwffReference: String
    @State private var notes = ""
    @State private var unlinkFromExistingSessions = false

    private var effectiveEligibleCount: Int {
        if unlinkFromExistingSessions {
            return summary.eligibleCount + summary.skippedAlreadyInSession
        }
        return summary.eligibleCount
    }

    private var canSubmit: Bool {
        effectiveEligibleCount > 0 && !trimmedCallsign.isEmpty
    }

    private var trimmedCallsign: String {
        myCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var summarySection: some View {
        Section("Selected QSOs") {
            LabeledContent("Eligible") {
                Text("\(effectiveEligibleCount)")
                    .monospacedDigit()
                    .foregroundStyle(effectiveEligibleCount > 0 ? .primary : .secondary)
            }
            if summary.skippedAlreadyInSession > 0 {
                LabeledContent("Already in a session") {
                    Text("\(summary.skippedAlreadyInSession)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let range = summary.dateRange {
                LabeledContent("Date range") {
                    Text(dateRangeLabel(range))
                        .font(.caption)
                }
            }
            LabeledContent("Unique stations") {
                Text("\(summary.uniqueStations)")
                    .monospacedDigit()
            }
        }
    }

    /// Shows each session that blocks one or more selected QSOs, and lets
    /// the user opt into unlinking them so grouping can proceed.
    @ViewBuilder
    private var existingSessionsSection: some View {
        if !summary.existingSessions.isEmpty {
            Section {
                ForEach(summary.existingSessions) { session in
                    LabeledContent {
                        Text("\(session.qsoCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(session.title, systemImage: "rectangle.stack")
                            .lineLimit(2)
                    }
                }
                Toggle(isOn: $unlinkFromExistingSessions) {
                    Text("Unlink these QSOs and regroup")
                        .font(.callout)
                }
            } header: {
                Text("Blocked by existing sessions")
            } footer: {
                Text(
                    unlinkFromExistingSessions
                        ? "All \(summary.totalSelected) selected QSOs will be "
                        + "moved into the new session."
                        : "\(summary.skippedAlreadyInSession) QSO"
                        + (summary.skippedAlreadyInSession == 1 ? "" : "s")
                        + " will be skipped. Toggle on to override and move them."
                )
            }
        }
    }

    /// Explains a common footgun: `loggingSessionId` that points at nothing
    /// ("orphaned"). Those QSOs are eligible automatically — surface why.
    @ViewBuilder
    private var orphanedSection: some View {
        if summary.orphanedSessionRefs > 0 {
            Section {
                Label {
                    Text(
                        "\(summary.orphanedSessionRefs) QSO"
                            + (summary.orphanedSessionRefs == 1 ? "" : "s")
                            + " reference a deleted session and will be "
                            + "regrouped automatically."
                    )
                    .font(.caption)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var callsignSection: some View {
        Section("Operator") {
            TextField("My callsign", text: $myCallsign)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
    }

    private var activationSection: some View {
        Section("Activation Type") {
            Picker("Type", selection: $activationType) {
                ForEach(ActivationType.allCases, id: \.rawValue) { type in
                    Label(type.displayName, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var referencesSection: some View {
        switch activationType {
        case .pota:
            Section("POTA") {
                TextField("Park reference (e.g. US-0001)", text: $parkReference)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
        case .sota:
            Section("SOTA") {
                TextField("Summit reference (e.g. W6/NC-001)", text: $sotaReference)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
        case .wwff:
            Section("WWFF") {
                TextField("Reference", text: $wwffReference)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
        case .tota:
            Section("TOTA") {
                Text("TOTA activations key off your operating grid square — no separate reference needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .casual,
             .aoa:
            EmptyView()
        }
    }

    private var titleNotesSection: some View {
        Section("Details") {
            TextField("Title (optional)", text: $title)
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(3 ... 6)
        }
    }

    private func submit() {
        let result = GroupIntoSessionResult(
            title: trimmed(title),
            myCallsign: trimmedCallsign,
            activationType: activationType,
            parkReference: trimmedReference(parkReference, for: .pota),
            sotaReference: trimmedReference(sotaReference, for: .sota),
            wwffReference: trimmedReference(wwffReference, for: .wwff),
            notes: trimmed(notes),
            unlinkFromExistingSessions: unlinkFromExistingSessions
        )
        onCreate(result)
    }

    private func trimmed(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func trimmedReference(_ text: String, for type: ActivationType) -> String? {
        guard activationType == type else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private func dateRangeLabel(_ range: ClosedRange<Date>) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let start = formatter.string(from: range.lowerBound)
        let end = formatter.string(from: range.upperBound)
        return start == end ? start : "\(start) – \(end)"
    }
}
