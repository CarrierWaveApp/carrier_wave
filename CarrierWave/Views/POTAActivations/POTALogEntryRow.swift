// POTA log entry row view component
//
// Expandable row displaying upload attempt and job status with
// detailed request/response information when expanded.

import CarrierWaveData
import SwiftUI

struct POTALogEntryRow: View {
    // MARK: Internal

    let entry: POTALogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                collapsedContent
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    @State private var isExpanded = false

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }

    private var collapsedContent: some View {
        HStack(spacing: 8) {
            entryIcon
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.parkReference)
                        .fontWeight(.semibold)
                    Spacer()
                    statusBadge
                }

                HStack {
                    Text(dateFormatter.string(from: entry.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    qsoCountText
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var entryIcon: some View {
        switch entry {
        case .localAttempt:
            Image(systemName: "arrow.up.doc")
                .foregroundStyle(.blue)
        case .potaJob:
            Image(systemName: "cloud")
                .foregroundStyle(.purple)
        case .correlated:
            Image(systemName: "link")
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch entry {
        case let .localAttempt(attempt):
            if attempt.success {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("Failed", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        case let .potaJob(job):
            jobStatusBadge(job.status)

        case let .correlated(attempt, job):
            HStack(spacing: 4) {
                if attempt.success {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                Image(systemName: "arrow.right")
                    .font(.caption2)
                jobStatusBadge(job.status)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var qsoCountText: some View {
        switch entry {
        case let .localAttempt(attempt):
            Text("\(attempt.qsoCount) QSOs")

        case let .potaJob(job):
            if job.totalQsos >= 0 {
                Text("\(job.insertedQsos)/\(job.totalQsos) QSOs")
            } else {
                Text("QSOs: --")
            }

        case let .correlated(attempt, job):
            if job.insertedQsos >= 0 {
                Text("\(attempt.qsoCount) → \(job.insertedQsos) inserted")
            } else {
                Text("\(attempt.qsoCount) QSOs")
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch entry {
            case let .localAttempt(attempt):
                localAttemptDetails(attempt)

            case let .potaJob(job):
                jobDetails(job)

            case let .correlated(attempt, job):
                localAttemptDetails(attempt)
                Divider()
                jobDetails(job)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func jobStatusBadge(_ status: POTAJobStatus) -> some View {
        Text(status.displayName)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(jobStatusColor(status).opacity(0.2))
            .foregroundStyle(jobStatusColor(status))
            .clipShape(Capsule())
    }

    private func localAttemptDetails(_ attempt: POTAUploadAttempt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local Upload Attempt")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            attemptBasicInfo(attempt)
            attemptHeadersSection(attempt)
            attemptResponseSection(attempt)
            attemptADIFSection(attempt)
        }
    }

    private func attemptBasicInfo(_ attempt: POTAUploadAttempt) -> some View {
        Group {
            detailRow("Callsign", attempt.callsign)
            detailRow("Location", attempt.location)
            detailRow("Filename", attempt.filename)

            if let status = attempt.httpStatusCode {
                detailRow("HTTP Status", "\(status)")
            }
            if let duration = attempt.requestDurationMs {
                detailRow("Duration", "\(duration)ms")
            }
            if let error = attempt.errorMessage {
                detailRow("Error", error)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func attemptHeadersSection(_ attempt: POTAUploadAttempt) -> some View {
        if !attempt.requestHeaders.isEmpty {
            Text("Request Headers")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.top, 4)

            ForEach(attempt.requestHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                Text("\(key): \(value)")
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func attemptResponseSection(_ attempt: POTAUploadAttempt) -> some View {
        if let response = attempt.responseBody, !response.isEmpty {
            Text("Response")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.top, 4)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(response.prefix(1_000))
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 80)
        }
    }

    private func attemptADIFSection(_ attempt: POTAUploadAttempt) -> some View {
        DisclosureGroup("ADIF Content") {
            ScrollView {
                Text(attempt.adifContent)
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }
        .font(.caption2)
    }

    private func jobDetails(_ job: POTAJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("POTA Job #\(job.jobId)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            detailRow("Status", job.status.displayName)
            if let parkName = job.parkName {
                detailRow("Park", parkName)
            }
            if let location = job.location {
                detailRow("Location", location)
            }
            if let callsign = job.callsignUsed {
                detailRow("Callsign", callsign)
            }
            detailRow("Submitted", dateFormatter.string(from: job.submitted))
            if let processed = job.processed {
                detailRow("Processed", dateFormatter.string(from: processed))
            }
            if job.totalQsos >= 0 {
                detailRow("Total QSOs", "\(job.totalQsos)")
                detailRow("Inserted", "\(job.insertedQsos)")
            }
            if let comment = job.userComment, !comment.isEmpty {
                detailRow("Comment", comment)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption2)
                .textSelection(.enabled)
        }
    }

    private func jobStatusColor(_ status: POTAJobStatus) -> Color {
        switch status {
        case .pending,
             .processing: .orange
        case .completed: .green
        case .failed,
             .error: .red
        case .duplicate: .yellow
        }
    }
}
