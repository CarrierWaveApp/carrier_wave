// POTA Job Views - Row and detail sheet for displaying POTA upload jobs

import SwiftUI

// MARK: - POTAJobRow

struct POTAJobRow: View {
    // MARK: Internal

    let job: POTAJob
    var potaClient: POTAClient?

    var body: some View {
        Button {
            showingDetailSheet = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        statusBadge
                        Text(submittedString)
                            .font(.subheadline)
                    }
                    Text(qsoSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetailSheet) {
            POTAJobDetailSheet(job: job, potaClient: potaClient)
        }
    }

    // MARK: Private

    @State private var showingDetailSheet = false

    private var statusColor: Color {
        switch job.status {
        case .pending,
             .processing:
            .orange
        case .completed: .green
        case .failed,
             .error:
            .red
        case .duplicate: .yellow
        }
    }

    private var submittedString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: job.submitted) + " UTC"
    }

    private var qsoSummary: String {
        if job.insertedQsos >= 0, job.totalQsos >= 0 {
            return "\(job.insertedQsos)/\(job.totalQsos) QSOs inserted"
        } else if job.totalQsos >= 0 {
            return "\(job.totalQsos) QSOs"
        }
        return "Job #\(job.jobId)"
    }

    private var statusBadge: some View {
        Text(job.status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .cornerRadius(4)
    }
}

// MARK: - POTAJobDetailSheet

struct POTAJobDetailSheet: View {
    // MARK: Internal

    let job: POTAJob
    var potaClient: POTAClient?

    var body: some View {
        NavigationStack {
            List {
                // Job info section
                Section("Job Information") {
                    LabeledContent("Job ID", value: "#\(job.jobId)")
                    LabeledContent("Status", value: job.status.displayName)
                    LabeledContent("Submitted", value: formattedDate(job.submitted))
                    if let processed = job.processed {
                        LabeledContent("Processed", value: formattedDate(processed))
                    }
                }

                // Activation info section
                Section("Activation") {
                    LabeledContent("Park", value: job.reference)
                    if let parkName = job.parkName {
                        LabeledContent("Name", value: parkName)
                    }
                    if let callsign = job.callsignUsed {
                        LabeledContent("Callsign", value: callsign)
                    }
                    if let location = job.location {
                        LabeledContent("Location", value: location)
                    }
                }

                // QSO counts section
                Section("QSO Counts") {
                    LabeledContent("Total", value: "\(job.totalQsos)")
                    LabeledContent("Inserted", value: "\(job.insertedQsos)")
                    if let firstQSO = job.firstQSO {
                        LabeledContent("First QSO", value: formattedDate(firstQSO))
                    }
                    if let lastQSO = job.lastQSO {
                        LabeledContent("Last QSO", value: formattedDate(lastQSO))
                    }
                }

                // Details section (loaded on demand)
                if isLoadingDetails {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if let details = jobDetails {
                    // Errors section
                    if !details.errors.isEmpty {
                        Section {
                            ForEach(details.errors, id: \.self) { error in
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                            }
                        } header: {
                            Label("Errors", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    // Warnings section
                    if !details.warnings.isEmpty {
                        Section {
                            ForEach(details.warnings, id: \.self) { warning in
                                Text(warning)
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            }
                        } header: {
                            Label("Warnings", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }

                    // Header errors/warnings
                    if let header = details.header {
                        if !header.errors.isEmpty {
                            Section {
                                ForEach(header.errors, id: \.self) { error in
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundStyle(.red)
                                }
                            } header: {
                                Label("Header Errors", systemImage: "doc.badge.ellipsis")
                            }
                        }

                        if !header.warnings.isEmpty {
                            Section {
                                ForEach(header.warnings, id: \.self) { warning in
                                    Text(warning)
                                        .font(.subheadline)
                                        .foregroundStyle(.orange)
                                }
                            } header: {
                                Label("Header Warnings", systemImage: "doc.badge.ellipsis")
                            }
                        }
                    }

                    // Totals breakdown (if multiple activations in one upload)
                    if let totals = details.totals, totals.count > 1 {
                        Section("QSO Breakdown") {
                            ForEach(totals.sorted(by: { $0.key < $1.key }), id: \.key) {
                                key, value in
                                VStack(alignment: .leading, spacing: 2) {
                                    if let park = value.activationPark,
                                       let date = value.activationDate
                                    {
                                        Text("\(park) - \(date)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    } else {
                                        Text(key)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    HStack(spacing: 12) {
                                        Text("CW: \(value.cw)")
                                        Text("Data: \(value.data)")
                                        Text("Phone: \(value.phone)")
                                        Text("Total: \(value.total)")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // No issues message
                    if details.errors.isEmpty, details.warnings.isEmpty,
                       details.header?.errors.isEmpty ?? true,
                       details.header?.warnings.isEmpty ?? true
                    {
                        Section {
                            Label("No errors or warnings", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                } else if let error = detailsError {
                    Section {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } header: {
                        Label("Could not load details", systemImage: "exclamationmark.triangle")
                    }
                }
            }
            .navigationTitle("Job Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadDetails()
            }
        }
        .landscapeAdaptiveDetents(portrait: [.large])
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingDetails = false
    @State private var jobDetails: POTAJobDetails?
    @State private var detailsError: String?

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date) + " UTC"
    }

    private func loadDetails() async {
        guard let potaClient, jobDetails == nil else {
            return
        }

        isLoadingDetails = true
        defer { isLoadingDetails = false }

        do {
            jobDetails = try await potaClient.fetchJobDetails(jobId: job.jobId)
        } catch {
            detailsError = error.localizedDescription
        }
    }
}
