import CarrierWaveCore
import SwiftUI

// MARK: - SatelliteCommunityReportSheet

/// File a status report with AMSAT: which transmitter, what you heard,
/// when, under your callsign and grid. Submits straight to
/// status.amsat.org on the Submit tap and nowhere else — AMSAT only wants
/// real, operator-initiated observations. The report shows up in the
/// community grid after the server's next sync (within half an hour).
struct SatelliteCommunityReportSheet: View {
    // MARK: Lifecycle

    init(model: SatelliteTrackerModel, rows: [CommunityActivityRow], initialName: String? = nil) {
        self.model = model
        self.rows = rows
        let preselected = rows.first { $0.amsatName == initialName } ?? rows.first
        _selectedName = State(initialValue: preselected?.amsatName ?? "")
    }

    // MARK: Internal

    let model: SatelliteTrackerModel
    /// The AMSAT transmitter rows the operator may report on.
    let rows: [CommunityActivityRow]

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    ContentUnavailableView {
                        Label("Not on AMSAT's List", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text("AMSAT's status page doesn't track this satellite, so there's nothing to report on.")
                    }
                } else {
                    form
                }
            }
            .navigationTitle("Report to AMSAT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .alert("Couldn't File Report", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Report Filed", isPresented: receiptPresented) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text(receiptMessage)
            }
        }
    }

    // MARK: Private

    private static let verdicts: [(value: String, label: String)] = [
        ("Heard", "Heard — satellite active"),
        ("Telemetry Only", "Telemetry or beacon only"),
        ("Not Heard", "Not heard"),
        ("Crew Active", "ISS crew voice active"),
    ]

    @Environment(\.dismiss) private var dismiss
    @AppStorage("loggerDefaultCallsign") private var defaultCallsign = ""
    @AppStorage("myGrid") private var myGrid = ""
    @AppStorage("loggerDefaultGrid") private var loggerDefaultGrid = ""

    @State private var selectedName: String
    @State private var verdict = "Heard"
    @State private var reportedAt = Date()
    @State private var callsign = ""
    @State private var grid = ""
    @State private var prefilled = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var receipt: CommunityReportReceipt?

    private var selectedRow: CommunityActivityRow? {
        rows.first { $0.amsatName == selectedName }
    }

    /// "Crew Active" only makes sense for the ISS crew row.
    private var verdicts: [(value: String, label: String)] {
        let crew = selectedName.localizedCaseInsensitiveContains("crew")
        return Self.verdicts.filter { crew || $0.value != "Crew Active" }
    }

    private var canSubmit: Bool {
        !isSubmitting && selectedRow != nil
            && !callsign.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: {
            if !$0 {
                errorMessage = nil
            }
        })
    }

    private var receiptPresented: Binding<Bool> {
        Binding(get: { receipt != nil }, set: {
            if !$0 {
                receipt = nil
            }
        })
    }

    private var receiptMessage: String {
        guard let receipt else {
            return ""
        }
        var message = "\(receipt.report) on \(receipt.amsatName) at "
            + receipt.reportedAt.formatted(.dateTime.hour().minute().timeZone()) + "."
        if receipt.replacedCount > 0 {
            message += " It replaced your earlier report for that quarter hour."
        }
        message += " It appears in the community grid after the next sync."
        return message
    }

    private var transmitterPicker: some View {
        Picker("Transmitter", selection: $selectedName) {
            ForEach(rows) { row in
                Text(row.displayName + (row.capability.map { " · \($0)" } ?? ""))
                    .tag(row.amsatName)
            }
        }
        .labelsHidden()
        .onChange(of: selectedName) { _, _ in
            if !verdicts.contains(where: { $0.value == verdict }) {
                verdict = "Heard"
            }
        }
    }

    private var form: some View {
        Form {
            Section("Satellite") {
                // A long list reads better as a menu; a handful inline.
                if rows.count > 4 {
                    transmitterPicker.pickerStyle(.menu)
                } else {
                    transmitterPicker.pickerStyle(.inline)
                }
            }
            Section("What you heard") {
                Picker("Report", selection: $verdict) {
                    ForEach(verdicts, id: \.value) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                DatePicker(
                    "When",
                    selection: $reportedAt,
                    in: Date().addingTimeInterval(-7 * 86_400) ... Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
            } footer: {
                Text("""
                The time you heard it, not now. AMSAT files reports by the hour; \
                a second report of yours in the same quarter hour replaces the first.
                """)
            }
            Section {
                TextField("Callsign", text: $callsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                TextField("Grid square (optional)", text: $grid)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("Your station")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("""
                    Only report what you heard yourself. Your callsign and grid are published \
                    on AMSAT's status page with the report.
                    """)
                    AmsatAttributionLabel()
                }
            }
        }
        .disabled(isSubmitting)
        .overlay {
            if isSubmitting {
                ProgressView("Filing with AMSAT…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear(perform: prefill)
    }

    private func prefill() {
        guard !prefilled else {
            return
        }
        prefilled = true
        callsign = defaultCallsign.uppercased()
        grid = (myGrid.isEmpty ? loggerDefaultGrid : myGrid).uppercased()
    }

    private func submit() async {
        guard let selectedRow, !isSubmitting else {
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let trimmedGrid = grid.trimmingCharacters(in: .whitespaces)
            receipt = try await model.submitCommunityReport(
                amsatName: selectedRow.amsatName,
                report: verdict,
                callsign: callsign,
                grid: trimmedGrid.isEmpty ? nil : trimmedGrid,
                at: reportedAt
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - AmsatAttributionLabel

/// The attribution AMSAT asks for wherever its report data is shown
/// (CC BY 4.0): "Satellite status data: AMSAT", linking to the status page.
struct AmsatAttributionLabel: View {
    var body: some View {
        Link(destination: URL(string: "https://status.amsat.org")!) {
            Label("Satellite status data: AMSAT", systemImage: "arrow.up.right.square")
                .labelStyle(.titleAndIcon)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Satellite status data from AMSAT, opens status.amsat.org")
    }
}
