import CarrierWaveData
import Foundation

// MARK: - FilterTraceResult

/// Result of running a filter trace for a specific stat category/identifier.
struct FilterTraceResult {
    let matchingQSOs: [QSODiagnostic]
    let excludedQSOs: [QSODiagnostic]
    let trace: FilterTrace
    let categoryItems: [CategoryItemSnapshot]
}

// MARK: - StatsReportBuilder + Trace

extension StatsReportBuilder {
    /// Run a targeted filter trace for a specific category and optional identifier.
    /// For high-count categories, produces summarized traces.
    /// For excluded/borderline QSOs, produces per-QSO detail.
    func runFilterTrace(
        snapshots: [StatsQSOSnapshot],
        category: StatCategoryType,
        identifier: String?,
        flaggedCallsigns: [String]
    ) -> FilterTraceResult {
        let flaggedSet = Set(flaggedCallsigns.map { $0.uppercased() })
        var accumulator = TraceAccumulator()

        for qso in snapshots {
            processSnapshotForTrace(
                qso,
                category: category,
                identifier: identifier,
                flaggedSet: flaggedSet,
                accumulator: &accumulator
            )
        }

        return assembleTraceResult(
            accumulator: accumulator,
            category: category
        )
    }
}

// MARK: - TraceAccumulator

/// Mutable accumulator for filter trace processing.
private struct TraceAccumulator {
    var matching: [QSODiagnostic] = []
    var excluded: [QSODiagnostic] = []
    var traceEntries: [FilterTraceEntry] = []
    var reasonCounts: [String: Int] = [:]
}

// MARK: - EvaluationResult

private struct EvaluationResult {
    let matches: Bool
    let excluded: Bool
    let reason: String?
}

private extension StatsReportBuilder {
    func processSnapshotForTrace(
        _ qso: StatsQSOSnapshot,
        category: StatCategoryType,
        identifier: String?,
        flaggedSet: Set<String>,
        accumulator: inout TraceAccumulator
    ) {
        let result = evaluateQSO(qso, category: category, identifier: identifier)
        let diagnostic = makeDiagnostic(
            from: qso,
            exclusionReason: result.excluded ? result.reason : nil
        )

        if result.excluded {
            accumulator.excluded.append(diagnostic)
            accumulator.reasonCounts[result.reason ?? "unknown", default: 0] += 1
            accumulator.traceEntries.append(makeTraceEntry(
                qso: qso, decision: "EXCLUDED", reason: result.reason ?? "unknown"
            ))
        } else if result.matches {
            accumulator.matching.append(diagnostic)
        }

        // Trace flagged callsigns regardless of match status
        if flaggedSet.contains(qso.callsign.uppercased()), !result.excluded {
            let decision = result.matches ? "MATCHED" : "NOT_MATCHED"
            accumulator.traceEntries.append(makeTraceEntry(
                qso: qso,
                decision: decision,
                reason: result.reason ?? categoryMismatchReason(
                    qso, category: category, identifier: identifier
                )
            ))
        }
    }

    func assembleTraceResult(
        accumulator: TraceAccumulator,
        category: StatCategoryType
    ) -> FilterTraceResult {
        let summary = buildSummary(
            matched: accumulator.matching.count,
            excluded: accumulator.excluded.count,
            reasons: accumulator.reasonCounts
        )
        let categoryItems = buildCategoryItems(
            from: accumulator.matching, category: category
        )
        let trace = FilterTrace(
            summary: summary,
            totalMatched: accumulator.matching.count,
            totalExcluded: accumulator.excluded.count,
            excludedByReason: accumulator.reasonCounts,
            details: accumulator.traceEntries
        )
        return FilterTraceResult(
            matchingQSOs: accumulator.matching,
            excludedQSOs: accumulator.excluded,
            trace: trace,
            categoryItems: categoryItems
        )
    }

    func evaluateQSO(
        _ qso: StatsQSOSnapshot,
        category: StatCategoryType,
        identifier: String?
    ) -> EvaluationResult {
        // Check metadata exclusion first
        if QSOMode.isMetadata(qso.mode) {
            return EvaluationResult(
                matches: false, excluded: true, reason: "metadata mode: \(qso.mode)"
            )
        }

        // If no specific identifier, all real QSOs are relevant
        guard let identifier else {
            return EvaluationResult(matches: true, excluded: false, reason: nil)
        }

        let matches = qsoMatchesIdentifier(
            qso, category: category, identifier: identifier
        )
        return EvaluationResult(matches: matches, excluded: false, reason: nil)
    }

    func qsoMatchesIdentifier(
        _ qso: StatsQSOSnapshot,
        category: StatCategoryType,
        identifier: String
    ) -> Bool {
        switch category {
        case .entities:
            if let dxcc = qso.dxcc {
                let entity = DescriptionLookup.dxccEntity(forNumber: dxcc)
                return entity?.name == identifier
            }
            return false
        case .bands:
            return qso.band.lowercased() == identifier.lowercased()
        case .grids:
            return qso.theirGrid == identifier
        case .parks:
            // Parks identifier format: "K-1234 - Mar 15, 2026"
            let park = qso.parkReference ?? ""
            return identifier.hasPrefix(park)
        case .frequencies:
            guard let freq = qso.frequency, freq > 0 else {
                return false
            }
            return identifier.hasPrefix(
                String(format: "%.3f", freq)
            )
        case .bestFriends:
            return qso.callsign.uppercased() == identifier.uppercased()
        case .bestHunters:
            let hasMyPark = qso.parkReference != nil && !qso.parkReference!.isEmpty
            return hasMyPark && qso.callsign.uppercased() == identifier.uppercased()
        case .qsls:
            let isConfirmed = qso.lotwConfirmed || qso.qrzConfirmed
            if let dxcc = qso.dxcc {
                let entity = DescriptionLookup.dxccEntity(forNumber: dxcc)
                return isConfirmed && entity?.name == identifier
            }
            return false
        }
    }
}

// MARK: - Diagnostic Builders

private extension StatsReportBuilder {
    func makeDiagnostic(
        from qso: StatsQSOSnapshot,
        exclusionReason: String?
    ) -> QSODiagnostic {
        let entityName: String? = if let dxcc = qso.dxcc {
            DescriptionLookup.dxccEntity(forNumber: dxcc)?.name
        } else {
            nil
        }

        return QSODiagnostic(
            id: qso.id.uuidString,
            callsign: qso.callsign,
            mode: qso.mode,
            band: qso.band,
            frequency: qso.frequency,
            timestamp: qso.timestamp,
            parkReference: qso.parkReference,
            gridSquare: qso.theirGrid,
            isHidden: false,
            isMetadata: QSOMode.isMetadata(qso.mode),
            qrzConfirmed: qso.qrzConfirmed,
            lotwConfirmed: qso.lotwConfirmed,
            dxccNumber: qso.dxcc,
            dxccEntity: entityName,
            loggingSessionId: qso.loggingSessionId?.uuidString,
            importSource: qso.importSource.rawValue,
            exclusionReason: exclusionReason
        )
    }

    func makeTraceEntry(
        qso: StatsQSOSnapshot,
        decision: String,
        reason: String
    ) -> FilterTraceEntry {
        FilterTraceEntry(
            qsoId: qso.id.uuidString,
            callsign: qso.callsign,
            timestamp: qso.timestamp,
            decision: decision,
            reason: reason
        )
    }

    func categoryMismatchReason(
        _ qso: StatsQSOSnapshot,
        category: StatCategoryType,
        identifier: String?
    ) -> String {
        guard let identifier else {
            return "no identifier filter"
        }

        switch category {
        case .entities:
            if let dxcc = qso.dxcc {
                let entity = DescriptionLookup.dxccEntity(forNumber: dxcc)
                return "entity=\(entity?.name ?? "unknown") (expected \(identifier))"
            }
            return "no DXCC entity assigned"
        case .bands:
            return "band=\(qso.band) (expected \(identifier))"
        case .parks:
            return "park=\(qso.parkReference ?? "none") (expected \(identifier))"
        default:
            return "does not match \(category.title) identifier \(identifier)"
        }
    }

    func buildSummary(
        matched: Int,
        excluded: Int,
        reasons: [String: Int]
    ) -> String {
        if reasons.isEmpty {
            return "\(matched) matched, \(excluded) excluded"
        }
        let reasonList = reasons
            .sorted { $0.value > $1.value }
            .map { "\($0.value) \($0.key)" }
            .joined(separator: ", ")
        return "\(matched) matched, \(excluded) excluded (\(reasonList))"
    }

    func buildCategoryItems(
        from diagnostics: [QSODiagnostic],
        category: StatCategoryType
    ) -> [CategoryItemSnapshot] {
        // Group matching QSOs by their natural grouping key
        let grouped = Dictionary(
            grouping: diagnostics,
            by: { groupingKey(for: $0, category: category) }
        )
        return grouped.map { key, qsos in
            CategoryItemSnapshot(
                identifier: key,
                description: "\(qsos.count) QSOs",
                count: qsos.count,
                qsoIds: qsos.map(\.id)
            )
        }
    }

    private func groupingKey(
        for qso: QSODiagnostic,
        category: StatCategoryType
    ) -> String {
        switch category {
        case .entities: qso.dxccEntity ?? "Unknown"
        case .bands: qso.band.lowercased()
        case .grids: qso.gridSquare ?? "Unknown"
        case .parks: qso.parkReference ?? "Unknown"
        case .frequencies:
            if let freq = qso.frequency {
                String(format: "%.3f MHz", freq)
            } else {
                "Unknown"
            }
        case .bestFriends: qso.callsign.uppercased()
        case .bestHunters: qso.callsign.uppercased()
        case .qsls: qso.dxccEntity ?? "Unknown"
        }
    }
}
