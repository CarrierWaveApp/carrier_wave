import CarrierWaveCore
import Foundation

// MARK: - Pipeline breakdown

extension LoFiCLI {
    static func printPipelineBreakdown(result: LoFiDownloadResult) {
        let qsos = result.qsos
        let rawCount = result.rawFetchCount
        let dedupCount = qsos.count
        let dedupDropped = rawCount - dedupCount

        printInfo("")
        printInfo("Sync pipeline breakdown:")
        printInfo("  Step 1 — Raw API fetch:      \(rawCount) QSOs")
        printInfo("  Step 2 — After UUID dedup:    \(dedupCount) QSOs (-\(dedupDropped) duplicates)")

        // Step 3: simulate FetchedQSO.fromLoFi field validation
        let stats = countInvalidQsos(qsos)

        printInfo(
            "  Step 3 — After field check:   \(stats.valid) QSOs "
                + "(-\(stats.invalid) missing required fields)"
        )
        if stats.missingCall > 0 {
            printInfo("    - \(stats.missingCall) missing callsign (their.call)")
        }
        if stats.missingBand > 0 {
            printInfo("    - \(stats.missingBand) missing band")
        }
        if stats.missingMode > 0 {
            printInfo("    - \(stats.missingMode) missing mode")
        }
        if stats.missingTimestamp > 0 {
            printInfo("    - \(stats.missingTimestamp) missing timestamp")
        }
        if stats.deleted > 0 {
            printInfo("    - \(stats.deleted) marked as deleted")
        }

        // Step 4: simulate deduplication key grouping (matches app pipeline)
        let (uniqueKeys, duplicates) = findDeduplicationDuplicates(qsos)
        let keyDropped = stats.valid - uniqueKeys
        printInfo(
            "  Step 4 — After dedup key:     \(uniqueKeys) QSOs "
                + "(-\(keyDropped) cross-operation duplicates)"
        )
        printDedupDuplicates(duplicates)
    }

    private static func countInvalidQsos(
        _ qsos: [(LoFiQso, LoFiOperation)]
    ) -> FieldStats {
        var stats = FieldStats(total: qsos.count)

        for (qso, _) in qsos {
            if qso.deleted == 1 {
                stats.deleted += 1
            }
            let hasCall = qso.their?.call != nil
            let hasBand = qso.band != nil
            let hasMode = qso.mode != nil
            let hasTime = qso.startAtMillis != nil
            if !hasCall {
                stats.missingCall += 1
            }
            if !hasBand {
                stats.missingBand += 1
            }
            if !hasMode {
                stats.missingMode += 1
            }
            if !hasTime {
                stats.missingTimestamp += 1
            }
            if !hasCall || !hasBand || !hasMode || !hasTime {
                stats.invalid += 1
            }
        }

        return stats
    }

    static func printDedupDuplicates(
        _ duplicates: [(String, [(LoFiQso, LoFiOperation)])]
    ) {
        guard !duplicates.isEmpty else {
            return
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")

        for (key, group) in duplicates {
            let parts = key.split(separator: "|")
            let call = parts.first ?? "?"
            printInfo("    Dedup key: \(call) \(parts.dropFirst().prefix(2).joined(separator: "/"))")
            for (qso, op) in group {
                let ts = qso.startAtMillis.map {
                    fmt.string(from: Date(timeIntervalSince1970: $0 / 1_000.0))
                } ?? "?"
                let opTitle = op.title ?? op.uuid.prefix(8).description
                printInfo("      - \(ts) UTC  op: \(opTitle)  uuid: \(qso.uuid.prefix(8))")
            }
        }
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

// MARK: - FieldStats

private struct FieldStats {
    let total: Int
    var missingCall = 0
    var missingBand = 0
    var missingMode = 0
    var missingTimestamp = 0
    var deleted = 0
    var invalid = 0

    var valid: Int {
        total - invalid
    }
}
