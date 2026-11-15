import UIKit

// MARK: - Job Index

extension POTAJob {
    /// Group jobs by the activation they belong to (keyed by activation id).
    /// Jobs that report their first QSO match on park, callsign and UTC date.
    /// A job POTA has not processed yet has no first QSO, so it goes to the
    /// newest otherwise-unmatched activation for that park and callsign that
    /// predates the upload; that keeps a fresh upload visible while it is still
    /// queued, without old jobs leaking onto newer activations.
    static func indexByActivation(
        jobs: [POTAJob], activations: [POTAActivation]
    ) -> [String: [POTAJob]] {
        var index: [String: [POTAJob]] = [:]
        var matchedJobIds = Set<Int>()
        for activation in activations {
            let matching = activation.matchingJobs(from: jobs)
            if !matching.isEmpty {
                index[activation.id] = matching
                matchedJobIds.formUnion(matching.map(\.jobId))
            }
        }

        let undated = jobs.filter { $0.firstQSO == nil && !matchedJobIds.contains($0.jobId) }
        let unmatched = activations.filter { index[$0.id] == nil }
        guard !undated.isEmpty, !unmatched.isEmpty else {
            return index
        }

        var fuzzyIndex: [String: [POTAJob]] = [:]
        for job in undated {
            let candidates = unmatched.filter {
                job.matchesParkAndCallsign(
                    parkReference: $0.parkReference, callsign: $0.callsign
                ) && $0.utcDate <= job.submitted
            }
            guard let best = candidates.max(by: { $0.utcDate < $1.utcDate }) else {
                continue
            }
            fuzzyIndex[best.id, default: []].append(job)
        }
        for (activationId, matched) in fuzzyIndex {
            index[activationId] = matched.sorted { $0.submitted > $1.submitted }
        }
        return index
    }
}
