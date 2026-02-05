// POTA unified log entry for timeline display
//
// Merges local upload attempts with remote POTA job status into a single
// timeline view, correlating by park reference, callsign, and timestamp.

import CarrierWaveCore
import Foundation

enum POTALogEntry: Identifiable {
    case localAttempt(POTAUploadAttempt)
    case potaJob(POTAJob)
    case correlated(attempt: POTAUploadAttempt, job: POTAJob)

    // MARK: Internal

    var id: String {
        switch self {
        case let .localAttempt(attempt):
            "local-\(attempt.id.uuidString)"
        case let .potaJob(job):
            "job-\(job.jobId)"
        case let .correlated(attempt, _):
            "correlated-\(attempt.id.uuidString)"
        }
    }

    var timestamp: Date {
        switch self {
        case let .localAttempt(attempt):
            attempt.timestamp
        case let .potaJob(job):
            job.submitted
        case let .correlated(attempt, _):
            attempt.timestamp
        }
    }

    var parkReference: String {
        switch self {
        case let .localAttempt(attempt):
            attempt.parkReference
        case let .potaJob(job):
            job.reference
        case let .correlated(attempt, _):
            attempt.parkReference
        }
    }

    /// Merge local attempts with POTA jobs, correlating by park reference and time
    static func merge(attempts: [POTAUploadAttempt], jobs: [POTAJob]) -> [POTALogEntry] {
        var entries: [POTALogEntry] = []
        var usedJobIds = Set<Int>()
        var usedAttemptIds = Set<UUID>()

        // First, find correlations
        for attempt in attempts {
            // Look for a matching job within 5 minutes
            let matchingJob = jobs.first { job in
                job.reference.uppercased() == attempt.parkReference.uppercased() &&
                    abs(job.submitted.timeIntervalSince(attempt.timestamp)) < 300 // 5 minutes
            }

            if let job = matchingJob {
                entries.append(.correlated(attempt: attempt, job: job))
                usedJobIds.insert(job.jobId)
                usedAttemptIds.insert(attempt.id)
            }
        }

        // Add uncorrelated attempts
        for attempt in attempts where !usedAttemptIds.contains(attempt.id) {
            entries.append(.localAttempt(attempt))
        }

        // Add uncorrelated jobs
        for job in jobs where !usedJobIds.contains(job.jobId) {
            entries.append(.potaJob(job))
        }

        // Sort by timestamp descending (most recent first)
        return entries.sorted { $0.timestamp > $1.timestamp }
    }
}
