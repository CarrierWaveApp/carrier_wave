// POTA Awards Actor — WAS 250 Computation
//
// Fetches 2026 QSOs with state data and computes America 250 WAS progress.

import CarrierWaveData
import Foundation
import SwiftData

// MARK: - WAS250

extension POTAAwardsActor {
    func computeWAS250(
        container: ModelContainer
    ) throws -> WAS250Progress {
        let qsos = try fetchWAS250QSOs(container: container)
        return computeWAS250Progress(from: qsos)
    }

    // MARK: - Fetching

    private func fetchWAS250QSOs(
        container: ModelContainer
    ) throws -> [QSO] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = cal.date(
            from: DateComponents(year: 2_026, month: 1, day: 1)
        )!
        let end = cal.date(
            from: DateComponents(year: 2_027, month: 1, day: 1)
        )!

        let context = ModelContext(container)
        context.autosaveEnabled = false
        let desc = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.timestamp >= start
                    && qso.timestamp < end
                    && qso.state != nil
                    && !qso.isHidden
            },
            limit: BoundedDescriptor<QSO>.maxLimit
        )
        return (try? context.boundedFetch(desc)) ?? []
    }

    // MARK: - Computation

    private func computeWAS250Progress(
        from qsos: [QSO]
    ) -> WAS250Progress {
        var allStates = Set<String>()
        var cwStates = Set<String>()
        var phoneStates = Set<String>()
        var digitalStates = Set<String>()
        var metadataCount = 0
        var withStateCount = 0
        var validStateCount = 0

        for qso in qsos {
            guard !QSOMode.isMetadata(qso.mode) else {
                metadataCount += 1
                continue
            }
            guard let rawState = qso.state else {
                continue
            }
            withStateCount += 1
            let state = USStates.normalizeAbbreviation(rawState)
            guard Self.validStates.contains(state) else {
                continue
            }
            validStateCount += 1
            allStates.insert(state)

            switch ModeEquivalence.family(for: qso.mode) {
            case .cw:
                cwStates.insert(state)
            case .phone:
                phoneStates.insert(state)
            case .digital:
                digitalStates.insert(state)
            case .other:
                break
            }
        }

        return WAS250Progress(
            statesWorked: allStates,
            cwStates: cwStates,
            phoneStates: phoneStates,
            digitalStates: digitalStates,
            totalQSOs2026: qsos.count,
            metadataExcluded: metadataCount,
            withStateField: withStateCount,
            withValidState: validStateCount
        )
    }
}
