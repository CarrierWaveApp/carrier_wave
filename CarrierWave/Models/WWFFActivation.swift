// WWFF Activation view model
//
// Groups QSOs by WWFF reference, UTC date, and callsign for display
// in activation progress views. Not persisted - computed from QSOs.
// Activation requires 44 QSOs per WWFF Global Rules V5.10.

import CarrierWaveCore
import Foundation

// MARK: - WWFFActivationStatus

enum WWFFActivationStatus: Sendable {
    case valid // 44+ QSOs logged
    case inProgress // 1-43 QSOs logged
    case incomplete // Previous visit, not yet 44 total across visits

    // MARK: Internal

    var iconName: String {
        switch self {
        case .valid: "checkmark.circle.fill"
        case .inProgress: "circle.lefthalf.filled"
        case .incomplete: "exclamationmark.circle"
        }
    }

    var label: String {
        switch self {
        case .valid: "Valid"
        case .inProgress: "In Progress"
        case .incomplete: "Incomplete"
        }
    }
}

// MARK: - WWFFActivation

struct WWFFActivation: Identifiable, Equatable, Hashable {
    // MARK: Internal

    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    let wwffReference: String
    let utcDate: Date
    let callsign: String
    let qsos: [QSO]

    var id: String {
        let dateString = Self.utcDateFormatter.string(from: utcDate)
        return "\(wwffReference)|\(callsign)|\(dateString)"
    }

    var utcDateString: String {
        Self.utcDateFormatter.string(from: utcDate)
    }

    var displayDate: String {
        Self.displayDateFormatter.string(from: utcDate)
    }

    var qsoCount: Int {
        qsos.count
    }

    /// Whether this single-day activation meets the 44-QSO threshold.
    var isValid: Bool {
        qsoCount >= WWFFRules.activationMinQSOs
    }

    /// Progress toward 44 QSOs (0.0 to 1.0+).
    var progress: Double {
        Double(qsoCount) / Double(WWFFRules.activationMinQSOs)
    }

    /// Progress string (e.g., "12/44 QSOs").
    var progressLabel: String {
        "\(qsoCount)/\(WWFFRules.activationMinQSOs) QSOs"
    }

    var status: WWFFActivationStatus {
        if isValid {
            return .valid
        }
        return .inProgress
    }

    /// Duration of the activation session.
    var duration: TimeInterval {
        guard !qsos.isEmpty else { return 0 }
        var sessionGroups: [UUID?: [QSO]] = [:]
        for qso in qsos {
            sessionGroups[qso.loggingSessionId, default: []].append(qso)
        }
        var total: TimeInterval = 0
        for (_, groupQSOs) in sessionGroups {
            guard let first = groupQSOs.min(by: { $0.timestamp < $1.timestamp }),
                  let last = groupQSOs.max(by: { $0.timestamp < $1.timestamp })
            else { continue }
            total += last.timestamp.timeIntervalSince(first.timestamp)
        }
        return total
    }

    var formattedDuration: String {
        let totalMinutes = Int(duration) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Unique bands worked during this activation.
    var uniqueBands: Set<String> {
        Set(qsos.map(\.band))
    }

    /// Unique modes used during this activation.
    var uniqueModes: [String] {
        ModeEquivalence.deduplicatedModes(qsos.map(\.mode))
    }

    static func == (lhs: WWFFActivation, rhs: WWFFActivation) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Grouping

    /// Group QSOs into activations by (wwffReference, UTC date, callsign).
    static func groupQSOs(_ qsos: [QSO]) -> [WWFFActivation] {
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!

        let wwffQSOs = qsos.filter {
            $0.wwffRef?.isEmpty == false
                && !metadataModes.contains($0.mode.uppercased())
        }

        var groups: [String: [QSO]] = [:]
        for qso in wwffQSOs {
            let ref = qso.wwffRef!.uppercased()
            let utcDate = calendar.startOfDay(for: qso.timestamp, in: utc)
            let callsign = qso.myCallsign.uppercased()
            let key = "\(ref)|\(callsign)|\(utcDateFormatter.string(from: utcDate))"
            groups[key, default: []].append(qso)
        }

        return groups.compactMap { key, qsos in
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { return nil }
            let ref = String(parts[0])
            let callsign = String(parts[1])
            let dateStr = String(parts[2])
            let utcDate = utcDateFormatter.date(from: dateStr) ?? Date()
            return WWFFActivation(
                wwffReference: ref,
                utcDate: utcDate,
                callsign: callsign,
                qsos: qsos.sorted { $0.timestamp < $1.timestamp }
            )
        }.sorted { $0.utcDate > $1.utcDate }
    }

    /// Group activations by reference for sectioning.
    static func groupByReference(
        _ activations: [WWFFActivation]
    ) -> [(reference: String, activations: [WWFFActivation])] {
        let grouped = Dictionary(grouping: activations) { $0.wwffReference }
        return grouped
            .map { (reference: $0.key, activations: $0.value.sorted { $0.utcDate > $1.utcDate }) }
            .sorted { $0.reference < $1.reference }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: Private

    private static let utcDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

// MARK: - WWFFActivationSummary

/// Aggregated activation stats across all visits to a reference.
/// WWFF allows combining QSOs across multiple visits to reach 44.
struct WWFFActivationSummary: Identifiable, Sendable {
    let reference: String
    let totalQSOs: Int
    let visitCount: Int
    let firstVisit: Date
    let lastVisit: Date
    let uniqueBands: Set<String>
    let uniqueModes: [String]

    var id: String { reference }

    /// Whether the cumulative QSO count meets the 44-QSO threshold.
    var isActivated: Bool {
        totalQSOs >= WWFFRules.activationMinQSOs
    }

    /// Progress toward activation (0.0 to 1.0+).
    var progress: Double {
        Double(totalQSOs) / Double(WWFFRules.activationMinQSOs)
    }

    /// Progress label (e.g., "32/44 QSOs across 2 visits").
    var progressLabel: String {
        if visitCount > 1 {
            return "\(totalQSOs)/\(WWFFRules.activationMinQSOs) QSOs across \(visitCount) visits"
        }
        return "\(totalQSOs)/\(WWFFRules.activationMinQSOs) QSOs"
    }

    /// Activator points earned from this reference (1 point per 44 QSOs, max 10/year).
    var activatorPoints: Int {
        min(totalQSOs / WWFFRules.qsosPerActivatorPoint, WWFFRules.maxPointsPerReferencePerYear)
    }

    /// Build summaries from grouped activations.
    static func summarize(_ activations: [WWFFActivation]) -> [WWFFActivationSummary] {
        let grouped = Dictionary(grouping: activations) { $0.wwffReference }
        return grouped.map { ref, acts in
            let allQSOs = acts.flatMap(\.qsos)
            let allBands = acts.reduce(into: Set<String>()) { $0.formUnion($1.uniqueBands) }
            let allModes = ModeEquivalence.deduplicatedModes(allQSOs.map(\.mode))
            return WWFFActivationSummary(
                reference: ref,
                totalQSOs: allQSOs.count,
                visitCount: acts.count,
                firstVisit: acts.map(\.utcDate).min() ?? Date(),
                lastVisit: acts.map(\.utcDate).max() ?? Date(),
                uniqueBands: allBands,
                uniqueModes: allModes
            )
        }.sorted { $0.reference < $1.reference }
    }
}

// MARK: - Calendar Extension

private extension Calendar {
    func startOfDay(for date: Date, in timeZone: TimeZone) -> Date {
        var cal = self
        cal.timeZone = timeZone
        return cal.startOfDay(for: date)
    }
}
