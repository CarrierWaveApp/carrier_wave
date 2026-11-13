import Foundation

// MARK: - Filter Pipeline Builder

extension AsyncQSOStatistics {
    /// Build a filter pipeline showing how data flows from total QSOs
    /// to the final displayed number for a given stat category.
    func filterPipeline(
        for category: StatCategoryType
    ) -> [StatFilterStage] {
        let total = totalQSOs + metadataExcludedCount
        let real = totalQSOs

        switch category {
        case .qsls:
            return qslsPipeline(total: total, real: real)
        case .entities:
            return entitiesPipeline(total: total, real: real)
        case .grids:
            return gridsPipeline(total: total, real: real)
        case .bands:
            return bandsPipeline(total: total, real: real)
        case .parks:
            return parksPipeline(total: total, real: real)
        case .frequencies:
            return frequenciesPipeline(total: total, real: real)
        case .bestFriends:
            return bestFriendsPipeline(total: total, real: real)
        case .bestHunters:
            return bestHuntersPipeline(total: total, real: real)
        }
    }

    // MARK: - Per-Category Pipelines

    private func qslsPipeline(
        total: Int, real: Int
    ) -> [StatFilterStage] {
        var stages = startingStages(total: total, real: real)
        let qrz = qrzConfirmedCount
        let lotw = lotwConfirmedCount
        let confirmed = confirmedQSLs ?? 0
        if lotw > 0 || qrz > 0 {
            stages.append(StatFilterStage(
                "Confirmed by LoTW: \(lotw), by QRZ: \(qrz)"
                    + " (with overlap)",
                count: confirmed
            ))
        }
        stages.append(StatFilterStage(
            "Confirmed QSLs", count: confirmed, isResult: true
        ))
        return stages
    }

    private func entitiesPipeline(
        total: Int, real: Int
    ) -> [StatFilterStage] {
        var stages = startingStages(total: total, real: real)
        let noDXCC = real - qsosWithDXCC
        if noDXCC > 0 {
            stages.append(StatFilterStage(
                "QSOs with recognized DXCC prefix",
                count: qsosWithDXCC
            ))
        }
        stages.append(StatFilterStage(
            "Unique DXCC entities",
            count: uniqueEntities ?? 0,
            isResult: true
        ))
        return stages
    }

    private func gridsPipeline(
        total: Int, real: Int
    ) -> [StatFilterStage] {
        var stages = startingStages(total: total, real: real)
        let noGrid = real - qsosWithGrid
        if noGrid > 0 {
            stages.append(StatFilterStage(
                "QSOs with a grid square reported",
                count: qsosWithGrid
            ))
        }
        stages.append(StatFilterStage(
            "Unique grid squares",
            count: uniqueGrids,
            isResult: true
        ))
        return stages
    }

    private func bandsPipeline(
        total: Int, real: Int
    ) -> [StatFilterStage] {
        var stages = startingStages(total: total, real: real)
        stages.append(StatFilterStage(
            "Unique bands", count: uniqueBands, isResult: true
        ))
        return stages
    }

    private func parksPipeline(
        total: Int, real: Int
    ) -> [StatFilterStage] {
        var stages = startingStages(total: total, real: real)
        stages.append(StatFilterStage(
            "QSOs with a park reference", count: qsosWithParkRef
        ))
        stages.append(StatFilterStage(
            "Activation attempts (park + UTC day)",
            count: totalActivationGroups
        ))
        let attempted = attemptedActivations ?? 0
        let successful = successfulActivations ?? 0
        if attempted > 0 {
            stages.append(StatFilterStage(
                "Attempts with < 10 QSOs (not counted)",
                count: attempted
            ))
        }
        stages.append(StatFilterStage(
            "Successful activations (10+ QSOs)",
            count: successful,
            isResult: true
        ))
        return stages
    }

    private func frequenciesPipeline(
        total: Int, real: Int
    ) -> [StatFilterStage] {
        var stages = startingStages(total: total, real: real)
        let noFreq = real - qsosWithFrequency
        if noFreq > 0 {
            stages.append(StatFilterStage(
                "QSOs with frequency data",
                count: qsosWithFrequency
            ))
        }
        stages.append(StatFilterStage(
            "Unique frequencies (rounded to 100 Hz)",
            count: uniqueFrequencyGroupCount,
            isResult: true
        ))
        return stages
    }

    private func bestFriendsPipeline(
        total: Int, real: Int
    ) -> [StatFilterStage] {
        var stages = startingStages(total: total, real: real)
        stages.append(StatFilterStage(
            "Unique callsigns contacted",
            count: uniqueCallsignCount,
            isResult: true
        ))
        return stages
    }

    private func bestHuntersPipeline(
        total: Int, real: Int
    ) -> [StatFilterStage] {
        var stages = startingStages(total: total, real: real)
        stages.append(StatFilterStage(
            "QSOs while you were activating a park",
            count: qsosWithParkRef
        ))
        stages.append(StatFilterStage(
            "Unique hunter callsigns",
            count: uniqueHunterCallsignCount,
            isResult: true
        ))
        return stages
    }

    // MARK: - Helpers

    private func startingStages(
        total: Int, real: Int
    ) -> [StatFilterStage] {
        var stages: [StatFilterStage] = []
        stages.append(StatFilterStage(
            "Total QSOs in log", count: total
        ))
        if metadataExcludedCount > 0 {
            stages.append(StatFilterStage(
                "After excluding metadata entries",
                count: real
            ))
        }
        return stages
    }
}
