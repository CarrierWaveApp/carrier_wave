// POTA Award Category — Detailed Methodology
//
// Structured explanations for the "What's This?" sheet
// on POTA award stats.

// MARK: - POTAAwardCategory + Methodology

nonisolated extension POTAAwardCategory {
    var uniqueParksMethodology: StatMethodology {
        StatMethodology(
            title: "Unique Parks Activated",
            summary: "Total unique park references you've activated "
                + "(10+ QSOs in one UTC day). Each park counts once.",
            included: [
                "Parks where you logged 10+ QSOs in a single UTC day",
                "Each unique park reference counted once",
            ],
            excluded: [
                "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                "Hidden/deleted QSOs",
                "Parks with fewer than 10 QSOs in any single UTC day",
            ],
            edgeCases: [
                "A park activated on multiple days still counts as one unique park",
                "UTC day boundaries apply — a session spanning midnight UTC "
                    + "splits into two activation attempts",
                "Two-fer parks count each park reference separately",
            ],
            methodology: "Groups QSOs by park reference + UTC date, "
                + "filters to groups with ≥10 QSOs, "
                + "counts unique park references"
        )
    }

    var dxEntitiesMethodology: StatMethodology {
        StatMethodology(
            title: "DX Entities Activated From",
            summary: "Unique DXCC entities from which you've completed "
                + "a valid activation.",
            included: [
                "DXCC entities where you completed a valid activation "
                    + "(10+ QSOs from a park in that entity)",
                "Entity determined from the park's DXCC location",
            ],
            excluded: [
                "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                "Hidden/deleted QSOs",
                "Entities where you operated but didn't reach 10 QSOs",
            ],
            edgeCases: [
                "Entity is based on the park's location, not your callsign prefix",
                "Multiple parks in the same entity still count as one entity",
                "Tiers increase in increments of 5 entities",
            ],
            methodology: "Finds valid activations (≥10 QSOs per park/UTC day), "
                + "counts unique DXCC entities across those activations"
        )
    }

    var workedAllStatesMethodology: StatMethodology {
        StatMethodology(
            title: "Activator Worked All States",
            summary: "Activate at least one park in each of the 50 US states.",
            included: [
                "Valid activations (10+ QSOs) from parks in US states",
                "Each state counts once you have one valid activation there",
            ],
            excluded: [
                "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                "Hidden/deleted QSOs",
                "US territories (PR, VI, GU, etc.) — only the 50 states",
                "Parks where you didn't reach 10 QSOs",
            ],
            edgeCases: [
                "State is determined from the park reference prefix "
                    + "(e.g. K-1234 maps to a state)",
                "A park on a state border counts for the state "
                    + "listed in the POTA database",
                "Progress shows X/50 states completed",
            ],
            methodology: "Finds valid activations, extracts US state "
                + "from park reference, counts unique states"
        )
    }

    var roverMethodology: StatMethodology {
        StatMethodology(
            title: "Rover",
            summary: "Most parks activated in a single UTC day. "
                + "Each park needs 10+ QSOs.",
            included: [
                "Valid activations (10+ QSOs) grouped by UTC date",
                "Counts the maximum number of different parks "
                    + "activated in one UTC day",
            ],
            excluded: [
                "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                "Hidden/deleted QSOs",
                "Parks with fewer than 10 QSOs on that UTC day",
            ],
            edgeCases: [
                "UTC day boundaries apply — an activation session "
                    + "spanning midnight splits across days",
                "Tiers: Warthog (5), Cheetah (10), Gazelle (15), "
                    + "Mustang (20), Falcon (25), Lion (30)",
                "This award is repeatable — you can earn each tier multiple times",
            ],
            methodology: "Groups valid activations by UTC date, "
                + "takes the date with the most parks"
        )
    }

    var repeatOffenderMethodology: StatMethodology {
        StatMethodology(
            title: "Repeat Offender",
            summary: "Most times you've activated the same single park.",
            included: [
                "Valid activations (10+ QSOs per UTC day) at each park",
                "Counts the park with the most separate activation days",
            ],
            excluded: [
                "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                "Hidden/deleted QSOs",
                "Activation attempts with fewer than 10 QSOs",
            ],
            edgeCases: [
                "Each UTC day at the same park is a separate activation",
                "Multiple activations on the same UTC day count as one",
                "Tiers start at Oasis (20) through Eagle's Nest (100), "
                    + "then increments of 20",
            ],
            methodology: "Groups valid activations by park reference, "
                + "takes the park with the highest activation count"
        )
    }

    var parkToParkMethodology: StatMethodology {
        StatMethodology(
            title: "Park to Park",
            summary: "QSOs made while both you and the other station "
                + "are in a park.",
            included: [
                "QSOs where you had a park reference AND the other station "
                    + "also had a park reference (SIG_INFO field)",
                "Each qualifying QSO counts individually",
            ],
            excluded: [
                "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                "Hidden/deleted QSOs",
                "QSOs where only one station was in a park",
            ],
            edgeCases: [
                "The other station's park reference must be present "
                    + "in the QSO record (typically from POTA spot data "
                    + "or manual entry)",
                "P2P QSOs that weren't tagged with the other station's park "
                    + "won't be counted",
                "Tiers increase in increments of 50 P2P QSOs",
            ],
            methodology: "Counts QSOs where both your park reference and "
                + "the other station's park reference are non-empty"
        )
    }

    var kiloMethodology: StatMethodology {
        StatMethodology(
            title: "Kilo",
            summary: "Log 1,000+ QSOs from a single park across "
                + "all your activations.",
            included: [
                "All QSOs with a park reference, totaled per park",
                "QSOs from all UTC days at that park are combined",
            ],
            excluded: [
                "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                "Hidden/deleted QSOs",
                "QSOs without a park reference",
            ],
            edgeCases: [
                "Unlike other awards, this does NOT require 10 QSOs "
                    + "per day — all QSOs at the park count",
                "Binary award: you either have 1,000+ at a park or you don't",
                "Progress shows your highest single-park QSO total",
            ],
            methodology: "Groups all QSOs by park reference, "
                + "checks if any park has ≥1,000 total QSOs"
        )
    }

    var laPortaMethodology: StatMethodology {
        StatMethodology(
            title: "LaPorta N1CC",
            summary: "Activate 10 different parks on 10 different bands. "
                + "Named after N1CC.",
            included: [
                "Valid activations (10+ QSOs per park/UTC day)",
                "Unique park + band combinations",
                "Need 10 unique parks AND 10 unique bands across those activations",
            ],
            excluded: [
                "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                "Hidden/deleted QSOs",
                "Activations with fewer than 10 QSOs",
            ],
            edgeCases: [
                "A park activated on two different bands "
                    + "contributes to both the park and band counts",
                "Binary award: requires BOTH 10 unique parks AND "
                    + "10 unique bands",
                "Band is determined from the QSOs in each activation group",
            ],
            methodology: "Finds valid activations, counts unique parks and "
                + "unique bands, requires both ≥10"
        )
    }

    // MARK: - Filter Pipeline

    /// Build a filter pipeline grounded in the user's actual data.
    func filterPipeline(
        from progress: POTAAwardsProgress
    ) -> [StatFilterStage] {
        var stages = pipelineCommonStages(from: progress)
        stages.append(contentsOf: pipelineResultStages(from: progress))
        return stages
    }

    /// Common stages shared across all POTA award categories.
    private func pipelineCommonStages(
        from progress: POTAAwardsProgress
    ) -> [StatFilterStage] {
        var stages: [StatFilterStage] = []
        let total = progress.totalParkQSOs
        let real = total - progress.metadataExcluded

        stages.append(StatFilterStage(
            "QSOs with a park reference", count: total
        ))
        if progress.metadataExcluded > 0 {
            stages.append(StatFilterStage(
                "After excluding metadata entries", count: real
            ))
        }
        stages.append(StatFilterStage(
            "Activation attempts (park + UTC day)",
            count: progress.totalActivationGroups
        ))
        let invalid = progress.totalActivationGroups
            - progress.validActivationGroups
        if invalid > 0 {
            stages.append(StatFilterStage(
                "Attempts with < 10 QSOs (not counted)",
                count: invalid
            ))
        }
        stages.append(StatFilterStage(
            "Valid activations (10+ QSOs)",
            count: progress.validActivationGroups
        ))
        return stages
    }

    /// Category-specific final result stages.
    private func pipelineResultStages(
        from progress: POTAAwardsProgress
    ) -> [StatFilterStage] {
        switch self {
        case .uniqueParks:
            [StatFilterStage(
                "Unique parks activated",
                count: progress.uniqueParksCount, isResult: true
            )]
        case .dxEntities:
            [StatFilterStage(
                "Unique DXCC entities",
                count: progress.dxEntitiesCount, isResult: true
            )]
        case .workedAllStates:
            [StatFilterStage(
                "US states with a valid activation",
                count: progress.statesActivated.count, isResult: true
            )]
        case .rover:
            [StatFilterStage(
                "Most parks in one UTC day",
                count: progress.roverMaxParks, isResult: true
            )]
        case .repeatOffender:
            [StatFilterStage(
                "Most activations at one park",
                count: progress.repeatOffenderMaxCount, isResult: true
            )]
        case .parkToPark:
            [StatFilterStage(
                "Park-to-park QSOs",
                count: progress.parkToParkCount, isResult: true
            )]
        case .kilo:
            kiloResultStages(from: progress)
        case .laPorta:
            [StatFilterStage(
                "Parks with 10+ bands",
                count: progress.laPortaQualifyingParks, isResult: true
            )]
        case .sixPack:
            [StatFilterStage(
                "Six Pack criteria met",
                count: progress.sixPackEarned ? 1 : 0, isResult: true
            )]
        }
    }

    private func kiloResultStages(
        from progress: POTAAwardsProgress
    ) -> [StatFilterStage] {
        var stages: [StatFilterStage] = []
        stages.append(StatFilterStage(
            "Best single-park QSO total",
            count: progress.bestSingleParkTotal, isResult: true
        ))
        if !progress.kiloParks.isEmpty {
            stages.append(StatFilterStage(
                "Parks with 1,000+ QSOs (Kilo earned)",
                count: progress.kiloParks.count, isResult: true
            ))
        }
        if !progress.nearKiloParks.isEmpty {
            stages.append(StatFilterStage(
                "Parks approaching Kilo (900–999 QSOs)",
                count: progress.nearKiloParks.count, isResult: true
            ))
        }
        return stages
    }

    var sixPackMethodology: StatMethodology {
        StatMethodology(
            title: "Six Pack",
            summary: "Make 10 QSOs on the 6-meter band from "
                + "6 different parks.",
            included: [
                "QSOs on the 6-meter band (50 MHz) with a park reference",
                "Need 10+ QSOs on 6m AND from 6+ unique parks",
            ],
            excluded: [
                "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                "Hidden/deleted QSOs",
                "QSOs on any other band",
                "QSOs without a park reference",
            ],
            edgeCases: [
                "Does not require 10 QSOs per park — "
                    + "total across all parks must reach 10",
                "Binary award: either you meet both criteria or you don't",
                "6m propagation is seasonal — typically best "
                    + "during summer sporadic-E openings",
            ],
            methodology: "Filters QSOs to 6m band + park reference, "
                + "checks ≥10 total QSOs from ≥6 unique parks"
        )
    }
}
