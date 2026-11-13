import CarrierWaveData
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

    private static let submittedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

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
        Self.submittedFormatter.string(from: job.submitted) + " UTC"
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
                    // Errors section — parsed semantically
                    if !details.errors.isEmpty {
                        parsedErrorsSection(details.errors)
                    }

                    // Warnings section — parsed semantically
                    if !details.warnings.isEmpty {
                        parsedWarningsSection(details.warnings)
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

                    // QSO summary — extracted from error/warning ADIF records
                    qsoSummarySection(details)

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

                // Related jobs for the same park
                if !relatedJobs.isEmpty {
                    relatedJobsSection
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

    private static let jobDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingDetails = false
    @State private var jobDetails: POTAJobDetails?
    @State private var detailsError: String?
    @State private var relatedJobs: [POTAJob] = []

    /// Related jobs for the same park reference.
    private var relatedJobsSection: some View {
        Section {
            ForEach(relatedJobs) { related in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            relatedStatusBadge(related)
                            Text(
                                Self.jobDateFormatter.string(from: related.submitted)
                                    + " UTC"
                            )
                            .font(.caption)
                        }
                        Text(
                            "\(related.insertedQsos)/\(related.totalQsos) QSOs inserted"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("#\(related.jobId)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            let dateStr = job.utcDateString ?? "this activation"
            Text("Other Uploads for \(job.reference) on \(dateStr)")
        }
    }

    /// QSO summary table extracted from error/warning ADIF records.
    @ViewBuilder
    private func qsoSummarySection(_ details: POTAJobDetails) -> some View {
        let allMessages = details.errors + details.warnings
        let summaries = allMessages.compactMap { POTAJobErrorParser.parse($0).qsoSummary }
        if !summaries.isEmpty {
            // Deduplicate (same QSO can appear in both errors and warnings)
            let unique = Array(Set(summaries))
                .sorted { $0.callsign < $1.callsign }
            Section {
                ForEach(Array(unique.enumerated()), id: \.offset) { _, qso in
                    HStack(spacing: 12) {
                        Text(qso.callsign)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .fontDesign(.monospaced)
                        Spacer()
                        Text(qso.band)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                        Text(qso.mode)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12))
                            .foregroundStyle(.purple)
                            .cornerRadius(4)
                    }
                }
            } header: {
                Text("QSOs in This Job (\(unique.count))")
            }
        }
    }

    private func relatedStatusBadge(_ job: POTAJob) -> some View {
        let color: Color = switch job.status {
        case .completed where job.insertedQsos > 0: .green
        case .completed: .red
        case .pending,
             .processing: .orange
        case .duplicate: .yellow
        case .failed,
             .error: .red
        }
        let label = if job.status == .completed, job.insertedQsos > 0 {
            "Uploaded"
        } else {
            job.status.displayName
        }
        return Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .cornerRadius(4)
    }

    private func formattedDate(_ date: Date) -> String {
        Self.jobDateFormatter.string(from: date) + " UTC"
    }

    private func loadDetails() async {
        guard let potaClient, jobDetails == nil else {
            return
        }

        isLoadingDetails = true
        defer { isLoadingDetails = false }

        do {
            async let detailsFetch = potaClient.fetchJobDetails(jobId: job.jobId)
            async let jobsFetch = potaClient.fetchJobs()
            let (details, allJobs) = try await (detailsFetch, jobsFetch)
            jobDetails = details
            // Scope to same activation: park + UTC date (not all jobs for the park)
            let jobDate = job.utcDateString
            relatedJobs = allJobs.filter {
                $0.reference == job.reference
                    && $0.jobId != job.jobId
                    && $0.utcDateString == jobDate
            }.sorted { $0.submitted > $1.submitted }
        } catch {
            detailsError = error.localizedDescription
        }
    }
}

// MARK: - GroupedMessage

struct GroupedMessage: Hashable {
    let message: String
    let count: Int
    let qsoIndices: [Int]
}

// MARK: - POTAJobDetailSheet+MessageSections

extension POTAJobDetailSheet {
    /// Parsed and grouped POTA errors section.
    func parsedErrorsSection(_ messages: [String]) -> some View {
        parsedMessagesSection(
            messages, color: .red, icon: "xmark.circle.fill",
            label: "Error", showDiscordGuidance: true
        )
    }

    /// Parsed and grouped POTA warnings section.
    func parsedWarningsSection(_ messages: [String]) -> some View {
        parsedMessagesSection(
            messages, color: .orange,
            icon: "exclamationmark.triangle.fill", label: "Warning",
            showDiscordGuidance: false
        )
    }

    /// Shared section builder for parsed POTA error/warning messages.
    @ViewBuilder
    func parsedMessagesSection(
        _ messages: [String], color: Color, icon: String,
        label: String, showDiscordGuidance: Bool
    ) -> some View {
        let grouped = groupMessages(messages)
        Section {
            ForEach(grouped, id: \.message) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(color)
                        Text(item.message)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if item.count > 1 {
                            Text("×\(item.count)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(color.opacity(0.15))
                                .foregroundStyle(color)
                                .cornerRadius(4)
                        }
                    }
                    if !item.qsoIndices.isEmpty {
                        Text("QSO \(item.qsoIndices.map(String.init).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if showDiscordGuidance {
                Text(
                    "If you see upload errors, please reach out on the "
                        + "Carrier Wave Discord before contacting POTA directly."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        } header: {
            let plural = messages.count == 1 ? "" : "s"
            Label("\(messages.count) \(label)\(plural)", systemImage: icon)
                .foregroundStyle(color)
        }
    }

    func groupMessages(_ raw: [String]) -> [GroupedMessage] {
        var buckets: [(message: String, indices: [Int])] = []
        var seen: [String: Int] = [:]
        for str in raw {
            let parsed = POTAJobErrorParser.parse(str)
            if let idx = seen[parsed.message] {
                if let qsoIdx = parsed.qsoIndex {
                    buckets[idx].indices.append(qsoIdx)
                }
            } else {
                seen[parsed.message] = buckets.count
                let indices = parsed.qsoIndex.map { [$0] } ?? []
                buckets.append((parsed.message, indices))
            }
        }
        return buckets.map {
            GroupedMessage(
                message: $0.message, count: max(1, $0.indices.count),
                qsoIndices: $0.indices
            )
        }
    }
}
