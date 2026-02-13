import CarrierWaveCore
import Foundation

// MARK: - Pipeline breakdown

extension LoFiCLI {
    static func printPipelineBreakdown(result: LoFiDownloadResult) {
        let qsos = result.qsos
        let stats = countInvalidQsos(qsos)
        let (uniqueKeys, duplicates) = findDeduplicationDuplicates(qsos)

        // Classify duplicates
        let twoFers = duplicates.filter { isTwoFer($0.1) }
        let trueDupes = duplicates.filter { !isTwoFer($0.1) }

        // Count merged QSOs (each group of N merges into 1, so N-1 are "absorbed")
        let twoFerMerged = twoFers.reduce(0) { $0 + $1.1.count - 1 }
        let dupeMerged = trueDupes.reduce(0) { $0 + $1.1.count - 1 }

        let report = ReportData(
            downloaded: qsos.count,
            stats: stats,
            finalCount: uniqueKeys,
            twoFers: twoFers,
            twoFerMerged: twoFerMerged,
            trueDupes: trueDupes,
            dupeMerged: dupeMerged
        )
        printReport(report)
    }

    // MARK: - Report output

    private static func printReport(_ report: ReportData) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")

        printInfo("")
        printInfo("========================================")
        printInfo("  LoFi Sync Report")
        printInfo("========================================")
        printInfo("")
        printInfo("Downloaded \(report.downloaded) contacts from LoFi.")
        printInfo("")

        // Skipped contacts
        if !report.stats.skipped.isEmpty {
            let word = report.stats.skipped.count == 1 ? "contact was" : "contacts were"
            printInfo(
                "\(report.stats.skipped.count) \(word) skipped (missing required info):"
            )
            printSkippedDetails(report.stats.skipped, fmt: fmt)
            printInfo("")
        }

        // Merged contacts
        let totalMerged = report.twoFerMerged + report.dupeMerged
        if totalMerged > 0 {
            let word = totalMerged == 1 ? "contact" : "contacts"
            printInfo(
                "\(totalMerged) \(word) merged into existing entries:"
            )
            printInfo("")

            if !report.twoFers.isEmpty {
                printTwoFerSection(report.twoFers, merged: report.twoFerMerged, fmt: fmt)
            }
            if !report.trueDupes.isEmpty {
                printDuplicateSection(report.trueDupes, merged: report.dupeMerged, fmt: fmt)
            }
        }

        // Final count
        printInfo("----------------------------------------")
        printInfo("Final count: \(report.finalCount) unique contacts")
        printInfo("----------------------------------------")

        // Deleted contacts note
        if report.stats.deleted > 0 {
            printInfo("")
            printInfo(
                "Note: \(report.stats.deleted) of these contacts are marked as"
                    + " deleted in LoFi."
            )
        }
    }

    private static func printSkippedDetails(
        _ skipped: [SkippedQSO], fmt: DateFormatter
    ) {
        for entry in skipped {
            let missing = entry.missingFields.joined(separator: ", ")
            let call = entry.callsign ?? "unknown"
            let band = entry.band ?? "?"
            let mode = entry.mode ?? "?"
            let ts = entry.timestamp.map { fmt.string(from: $0) + " UTC" }
                ?? "unknown time"
            let op = entry.operationTitle
            printInfo("  - \(call) \(band) \(mode) \(ts) (\(op))")
            printInfo("    Missing: \(missing)")
        }
    }

    private static func printTwoFerSection(
        _ twoFers: [(String, [(LoFiQso, LoFiOperation)])],
        merged: Int,
        fmt: DateFormatter
    ) {
        let word = merged == 1 ? "contact appears" : "contacts appear"
        printInfo(
            "  Two-fer activations (\(merged) \(word) in"
                + " multiple parks):"
        )
        printInfo(
            "  These are the same over-the-air contact logged at"
        )
        printInfo(
            "  multiple parks. Both park references are kept."
        )
        printInfo("")
        for (key, group) in twoFers {
            printMergeGroup(key: key, group: group, fmt: fmt)
        }
        printInfo("")
    }

    private static func printDuplicateSection(
        _ trueDupes: [(String, [(LoFiQso, LoFiOperation)])],
        merged: Int,
        fmt: DateFormatter
    ) {
        let word = merged == 1 ? "contact appears" : "contacts appear"
        printInfo(
            "  Duplicates (\(merged) \(word) more than once"
                + " in the same park):"
        )
        printInfo("")
        for (key, group) in trueDupes {
            printMergeGroup(key: key, group: group, fmt: fmt)
        }
        printInfo("")
    }

    private static func printMergeGroup(
        key: String,
        group: [(LoFiQso, LoFiOperation)],
        fmt: DateFormatter
    ) {
        let parts = key.split(separator: "|")
        let call = parts.first ?? "?"
        let bandMode = parts.dropFirst().prefix(2).joined(separator: " ")
        printInfo("    \(call) on \(bandMode):")
        for (qso, op) in group {
            let ts = qso.startAtMillis.map {
                fmt.string(from: Date(timeIntervalSince1970: $0 / 1_000.0))
            } ?? "unknown time"
            let opTitle = op.title ?? "unknown"
            printInfo("      \(ts) UTC — \(opTitle)")
        }
    }

    // MARK: - Analysis helpers

    private static func countInvalidQsos(
        _ qsos: [(LoFiQso, LoFiOperation)]
    ) -> FieldStats {
        var stats = FieldStats(total: qsos.count)

        for (qso, op) in qsos {
            if qso.deleted == 1 {
                stats.deleted += 1
            }
            let hasCall = qso.their?.call != nil
            let hasBand = qso.band != nil
            let hasMode = qso.mode != nil
            let hasTime = qso.startAtMillis != nil
            if !hasCall || !hasBand || !hasMode || !hasTime {
                var missing: [String] = []
                if !hasCall {
                    missing.append("callsign")
                }
                if !hasBand {
                    missing.append("band")
                }
                if !hasMode {
                    missing.append("mode")
                }
                if !hasTime {
                    missing.append("date/time")
                }
                let ts = qso.startAtMillis.map {
                    Date(timeIntervalSince1970: $0 / 1_000.0)
                }
                stats.skipped.append(SkippedQSO(
                    callsign: qso.their?.call,
                    band: qso.band,
                    mode: qso.mode,
                    timestamp: ts,
                    operationTitle: op.title ?? String(op.uuid.prefix(8)),
                    missingFields: missing
                ))
            }
        }

        return stats
    }

    /// Check if a dedup group is a two-fer (same QSO across different parks).
    static func isTwoFer(_ group: [(LoFiQso, LoFiOperation)]) -> Bool {
        let uniqueOps = Set(group.map(\.1.uuid))
        return uniqueOps.count > 1
    }

    /// Find QSOs that share dedup keys (same callsign+band+mode in 2-min window).
    static func findDeduplicationDuplicates(
        _ qsos: [(LoFiQso, LoFiOperation)]
    ) -> (Int, [(String, [(LoFiQso, LoFiOperation)])]) {
        var byKey: [String: [(LoFiQso, LoFiOperation)]] = [:]
        for (qso, op) in qsos {
            guard let call = qso.their?.call,
                  let band = qso.band,
                  let mode = qso.mode,
                  let startAtMillis = qso.startAtMillis
            else {
                continue
            }
            let timestamp = startAtMillis / 1_000.0
            let rounded = Int(timestamp / 120) * 120
            let key = "\(call.uppercased())|\(band.uppercased())"
                + "|\(mode.uppercased())|\(rounded)"
            byKey[key, default: []].append((qso, op))
        }
        let duplicates = byKey.filter { $0.value.count > 1 }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
        return (byKey.count, duplicates)
    }
}

// MARK: - ReportData

private struct ReportData {
    let downloaded: Int
    let stats: FieldStats
    let finalCount: Int
    let twoFers: [(String, [(LoFiQso, LoFiOperation)])]
    let twoFerMerged: Int
    let trueDupes: [(String, [(LoFiQso, LoFiOperation)])]
    let dupeMerged: Int
}

// MARK: - FieldStats

private struct FieldStats {
    let total: Int
    var deleted = 0
    var skipped: [SkippedQSO] = []

    var valid: Int {
        total - skipped.count
    }
}

// MARK: - SkippedQSO

private struct SkippedQSO {
    let callsign: String?
    let band: String?
    let mode: String?
    let timestamp: Date?
    let operationTitle: String
    let missingFields: [String]
}
