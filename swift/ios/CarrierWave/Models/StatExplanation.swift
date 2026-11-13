import Foundation

// MARK: - StatExplanation

/// Lightweight breakdown of how a stat count was derived.
/// Computed alongside normal stats for "explain this number" popovers.
struct StatExplanation {
    let totalConsidered: Int
    let counted: Int
    let hiddenExcluded: Int
    let metadataExcluded: Int
    let deduplicatedExcluded: Int

    var summary: String {
        var parts: [String] = []
        if hiddenExcluded > 0 {
            parts.append("\(hiddenExcluded) hidden")
        }
        if metadataExcluded > 0 {
            parts.append("\(metadataExcluded) metadata")
        }
        if deduplicatedExcluded > 0 {
            parts.append("\(deduplicatedExcluded) deduplicated")
        }
        if parts.isEmpty {
            return "\(counted) QSOs"
        }
        let excluded = parts.joined(separator: " · ")
        return "\(counted) QSOs — \(excluded) excluded"
    }
}

// MARK: - ActivationExplanation

/// Breakdown for a specific park activation's QSO count vs threshold.
struct ActivationExplanation {
    let parkReference: String
    let date: Date
    let totalQSOs: Int
    let countedQSOs: Int
    let metadataExcluded: Int
    let hiddenExcluded: Int
    let threshold: Int
    let isSuccessful: Bool

    var summary: String {
        let status = isSuccessful ? "Valid" : "\(countedQSOs)/\(threshold)"
        var parts = ["\(countedQSOs) QSOs (\(status))"]
        if metadataExcluded > 0 {
            parts.append("\(metadataExcluded) metadata excluded")
        }
        if hiddenExcluded > 0 {
            parts.append("\(hiddenExcluded) hidden excluded")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - StatsExplanations

/// Container for all stat explanations, computed during stats pass.
struct StatsExplanations {
    var overall = StatExplanation(
        totalConsidered: 0,
        counted: 0,
        hiddenExcluded: 0,
        metadataExcluded: 0,
        deduplicatedExcluded: 0
    )

    /// Per-category top-level explanation
    var byCategory: [String: StatExplanation] = [:]

    /// Per-activation breakdown (keyed by "park|utcDate")
    var activations: [String: ActivationExplanation] = [:]
}

// MARK: - StatFilterStage

/// One step in a filter pipeline, showing a label and count.
/// Displayed in the "What's This?" sheet to ground generic
/// explanations in the user's actual data.
nonisolated struct StatFilterStage: Identifiable {
    // MARK: Lifecycle

    init(_ label: String, count: Int, isResult: Bool = false) {
        id = UUID()
        self.label = label
        self.count = count
        self.isResult = isResult
    }

    // MARK: Internal

    let id: UUID
    let label: String
    let count: Int
    /// True for the final result row (displayed with emphasis)
    let isResult: Bool
}

// MARK: - StatMethodology

/// Structured description of how a statistic is calculated.
/// Used for the "What's This?" sheet so users understand what
/// was included, excluded, and any edge cases.
struct StatMethodology {
    let title: String
    let summary: String
    let included: [String]
    let excluded: [String]
    let edgeCases: [String]
    let methodology: String?
}
