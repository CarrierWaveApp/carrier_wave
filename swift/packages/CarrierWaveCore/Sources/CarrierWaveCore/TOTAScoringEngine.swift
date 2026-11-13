//
//  TOTAScoringEngine.swift
//  CarrierWaveCore
//
//  Pure scoring engine for Tiles on the Air (TOTA). Inputs in, ledger out.
//  No SwiftData, no UIKit. The caller (typically iOS Services) builds
//  `TOTAScoringInputs` from a `LoggingSession` + its QSOs + a T3 snapshot,
//  then calls `TOTAScoringEngine.score(_:)` to get back a `TOTAScoringResult`
//  with four confidence tiers and a headline total.
//
//  Formula source: docs/features/tota-scoring.md (mirrors the tota-rules skill).
//

import Foundation

// MARK: - TOTACategoryKind

/// Pure value-type mirror of `CarrierWaveData.TOTACategory`. Kept here so the
/// engine has no dependency on the data layer.
public enum TOTACategoryKind: String, Sendable {
    case standard
    case mobile
}

// MARK: - TOTAScoringQSO

/// Minimum QSO shape the engine needs. Caller projects from `QSO`.
public struct TOTAScoringQSO: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        mode: String,
        callsign: String,
        timestamp: Date
    ) {
        self.id = id
        self.mode = mode
        self.callsign = callsign
        self.timestamp = timestamp
    }

    // MARK: Public

    public let id: UUID
    public let mode: String
    public let callsign: String
    public let timestamp: Date
}

// MARK: - TOTAScoringInputs

/// All the inputs needed to compute a TOTA score. Packed into a single value
/// so the engine signature stays small and tests are readable.
public struct TOTAScoringInputs: Sendable {
    // MARK: Lifecycle

    public init(
        category: TOTACategoryKind = .standard,
        qsos: [TOTAScoringQSO],
        t3CallsignToTile: [String: String] = [:],
        distanceMiles: Double?,
        elevationGainFeet: Double?,
        ruckWeightPounds: Double?,
        personalEffortFactor: Int?,
        qrpActivation: Bool,
        isWinter: Bool,
        withPets: Bool,
        withKids: Bool,
        winlinkSent: Bool,
        aprsSent: Bool,
        varacSent: Bool,
        firstActivationOfTileEver: Bool,
        tileCount: Int
    ) {
        self.category = category
        self.qsos = qsos
        self.t3CallsignToTile = t3CallsignToTile
        self.distanceMiles = distanceMiles
        self.elevationGainFeet = elevationGainFeet
        self.ruckWeightPounds = ruckWeightPounds
        self.personalEffortFactor = personalEffortFactor
        self.qrpActivation = qrpActivation
        self.isWinter = isWinter
        self.withPets = withPets
        self.withKids = withKids
        self.winlinkSent = winlinkSent
        self.aprsSent = aprsSent
        self.varacSent = varacSent
        self.firstActivationOfTileEver = firstActivationOfTileEver
        self.tileCount = tileCount
    }

    // MARK: Public

    public let category: TOTACategoryKind
    public let qsos: [TOTAScoringQSO]
    /// Map of UPPERCASED chaser callsign → 6-char tile, derived from the spots
    /// feed snapshot. Presence of a key means the QSO with that callsign earns
    /// the T3 boost.
    public let t3CallsignToTile: [String: String]
    public let distanceMiles: Double?
    public let elevationGainFeet: Double?
    public let ruckWeightPounds: Double?
    public let personalEffortFactor: Int?
    public let qrpActivation: Bool
    public let isWinter: Bool
    public let withPets: Bool
    public let withKids: Bool
    public let winlinkSent: Bool
    public let aprsSent: Bool
    public let varacSent: Bool
    /// User-asserted: the very first activation of this tile by anyone. Server
    /// is authoritative; we treat as Asserted-tier credit.
    public let firstActivationOfTileEver: Bool
    /// Number of distinct tiles activated (drives the per-tile
    /// first-in-quarter eligibility count in the Pending tier).
    public let tileCount: Int
}

// MARK: - TOTAScoringResult

/// Four-tier score ledger. `total` reflects pre-upload pessimism: it sums
/// Confirmed + Estimated + Asserted only. Pending bonuses are visible in
/// `pendingMaxPoints` but not added — the server resolves those on upload.
public struct TOTAScoringResult: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        confirmed: ConfirmedTier,
        estimatedT3Boost: Double,
        assertedFirstEver: Double,
        pendingMaxPoints: Double,
        total: Double
    ) {
        self.confirmed = confirmed
        self.estimatedT3Boost = estimatedT3Boost
        self.assertedFirstEver = assertedFirstEver
        self.pendingMaxPoints = pendingMaxPoints
        self.total = total
    }

    // MARK: Public

    public struct ConfirmedTier: Sendable, Equatable {
        // MARK: Lifecycle

        public init(
            effectiveQSOs: Double,
            distanceMiles: Double,
            base: Double,
            qrpMultiplierApplied: Bool,
            qsoSubtotal: Double,
            winterBonus: Double,
            ruckBonus: Double,
            elevationBonus: Double,
            petsBonus: Double,
            kidsBonus: Double,
            winlinkFlat: Double,
            aprsFlat: Double,
            varacFlat: Double,
            subtotal: Double
        ) {
            self.effectiveQSOs = effectiveQSOs
            self.distanceMiles = distanceMiles
            self.base = base
            self.qrpMultiplierApplied = qrpMultiplierApplied
            self.qsoSubtotal = qsoSubtotal
            self.winterBonus = winterBonus
            self.ruckBonus = ruckBonus
            self.elevationBonus = elevationBonus
            self.petsBonus = petsBonus
            self.kidsBonus = kidsBonus
            self.winlinkFlat = winlinkFlat
            self.aprsFlat = aprsFlat
            self.varacFlat = varacFlat
            self.subtotal = subtotal
        }

        // MARK: Public

        public let effectiveQSOs: Double
        public let distanceMiles: Double
        public let base: Double
        public let qrpMultiplierApplied: Bool
        public let qsoSubtotal: Double
        public let winterBonus: Double
        public let ruckBonus: Double
        public let elevationBonus: Double
        public let petsBonus: Double
        public let kidsBonus: Double
        public let winlinkFlat: Double
        public let aprsFlat: Double
        public let varacFlat: Double
        public let subtotal: Double
    }

    public let confirmed: ConfirmedTier
    public let estimatedT3Boost: Double
    public let assertedFirstEver: Double
    /// Maximum points the server could add for first-in-quarter (per-tile +10).
    public let pendingMaxPoints: Double
    /// Pre-upload pessimistic total. Excludes `pendingMaxPoints`.
    public let total: Double
}

// MARK: - TOTAScoringEngine

public enum TOTAScoringEngine: Sendable {
    // MARK: Public

    /// Score the inputs into a four-tier ledger. Pure; deterministic.
    public static func score(_ inputs: TOTAScoringInputs) -> TOTAScoringResult {
        let filtered = filteredQSOs(for: inputs)
        let effective = effectiveQSOs(filtered, t3CallsignToTile: inputs.t3CallsignToTile)
        let t3Boost = t3BoostPoints(filtered, t3CallsignToTile: inputs.t3CallsignToTile)
        let flats = flatBonuses(for: inputs)
        let pendingMax = Double(max(inputs.tileCount, 1)) * 10.0
        let asserted = inputs.firstActivationOfTileEver ? 10.0 : 0.0

        // Both formulas read `flatBonuses(for:)` per-flag inside the branch;
        // the rolled value is computed for clarity but not threaded through.
        _ = flats
        switch inputs.category {
        case .mobile:
            return scoreMobile(
                inputs: inputs,
                effective: effective,
                t3Boost: t3Boost,
                pendingMax: pendingMax,
                asserted: asserted
            )
        case .standard:
            return scoreStandard(
                inputs: inputs,
                effective: effective,
                t3Boost: t3Boost,
                pendingMax: pendingMax,
                asserted: asserted
            )
        }
    }

    // MARK: Internal

    // MARK: Internal — visible to tests

    /// Per-mode weight. FT8/FT4 = 0.2, everything else = 1.0.
    static func modeWeight(for mode: String) -> Double {
        let upper = mode.uppercased()
        return (upper == "FT8" || upper == "FT4") ? 0.2 : 1.0
    }

    /// Defensive WL/APRS/VARAC exclusion: when the session-level flag is set,
    /// drop any QSO whose mode matches so the +5 flat doesn't double-count
    /// alongside a logged QSO row.
    static func filteredQSOs(for inputs: TOTAScoringInputs) -> [TOTAScoringQSO] {
        inputs.qsos.filter { qso in
            let upper = qso.mode.uppercased()
            if inputs.winlinkSent, upper == "WINLINK" {
                return false
            }
            if inputs.aprsSent, upper == "APRS" {
                return false
            }
            if inputs.varacSent, upper == "VARAC" {
                return false
            }
            return true
        }
    }

    static func effectiveQSOs(
        _ qsos: [TOTAScoringQSO],
        t3CallsignToTile: [String: String]
    ) -> Double {
        qsos.reduce(into: 0.0) { acc, qso in
            let weight = modeWeight(for: qso.mode)
            let isT3 = t3CallsignToTile[qso.callsign.uppercased()] != nil
            let factor = isT3 ? weight * 2.0 : weight
            acc += factor
        }
    }

    /// Points contributed by T3 above what each QSO would score without it.
    static func t3BoostPoints(
        _ qsos: [TOTAScoringQSO],
        t3CallsignToTile: [String: String]
    ) -> Double {
        qsos.reduce(into: 0.0) { acc, qso in
            guard t3CallsignToTile[qso.callsign.uppercased()] != nil else {
                return
            }
            // Doubling adds another +1× to the QSO's effective weight.
            acc += modeWeight(for: qso.mode)
        }
    }

    static func flatBonuses(for inputs: TOTAScoringInputs) -> Double {
        var total = 0.0
        if inputs.winlinkSent {
            total += 5.0
        }
        if inputs.aprsSent {
            total += 5.0
        }
        if inputs.varacSent {
            total += 5.0
        }
        return total
    }

    /// Distance with PEF scaling and 0.25-mi floor (only when distance > 0).
    static func scaledDistance(_ inputs: TOTAScoringInputs) -> Double {
        guard let raw = inputs.distanceMiles, raw > 0 else {
            return 0
        }
        let floored = max(raw, 0.25)
        let pef = inputs.personalEffortFactor.map(Double.init) ?? 1.0
        return floored * pef
    }

    // MARK: Private

    private static func scoreStandard(
        inputs: TOTAScoringInputs,
        effective: Double,
        t3Boost: Double,
        pendingMax: Double,
        asserted: Double
    ) -> TOTAScoringResult {
        let distance = scaledDistance(inputs)
        let base = effective * distance
        let qrpMultiplier = inputs.qrpActivation ? 2.0 : 1.0
        let qsoSubtotal = base * qrpMultiplier

        let winterPct = inputs.isWinter ? 0.20 : 0.0
        let ruckSteps = floor((inputs.ruckWeightPounds ?? 0) / 5.0)
        let ruckPct = ruckSteps * 0.05
        let elevSteps = floor((inputs.elevationGainFeet ?? 0) / 200.0)
        let elevPct = elevSteps * 0.02
        let petsPct = inputs.withPets ? 0.15 : 0.0
        let kidsPct = inputs.withKids ? 0.20 : 0.0

        let winterBonus = qsoSubtotal * winterPct
        let ruckBonus = qsoSubtotal * ruckPct
        let elevBonus = qsoSubtotal * elevPct
        let petsBonus = qsoSubtotal * petsPct
        let kidsBonus = qsoSubtotal * kidsPct

        // Each flat is shown separately so the ledger can label them.
        let winlinkFlat = inputs.winlinkSent ? 5.0 : 0.0
        let aprsFlat = inputs.aprsSent ? 5.0 : 0.0
        let varacFlat = inputs.varacSent ? 5.0 : 0.0

        let confirmedSubtotal = qsoSubtotal
            + winterBonus + ruckBonus + elevBonus + petsBonus + kidsBonus
            + winlinkFlat + aprsFlat + varacFlat

        let confirmed = TOTAScoringResult.ConfirmedTier(
            effectiveQSOs: effective,
            distanceMiles: distance,
            base: base,
            qrpMultiplierApplied: inputs.qrpActivation,
            qsoSubtotal: qsoSubtotal,
            winterBonus: winterBonus,
            ruckBonus: ruckBonus,
            elevationBonus: elevBonus,
            petsBonus: petsBonus,
            kidsBonus: kidsBonus,
            winlinkFlat: winlinkFlat,
            aprsFlat: aprsFlat,
            varacFlat: varacFlat,
            subtotal: confirmedSubtotal
        )

        // T3 contribution to points = boost × distance × QRP multiplier
        // (T3 doubles the QSO weight, so its incremental contribution rides the
        // same distance/QRP scaling, and *also* increases the percentage bonus
        // base by the same proportion since the percentages are off qsoSubtotal).
        let percentageMultiplier = winterPct + ruckPct + elevPct + petsPct + kidsPct
        let t3Points = t3Boost * distance * qrpMultiplier * (1.0 + percentageMultiplier)

        let total = confirmedSubtotal + t3Points + asserted
        return TOTAScoringResult(
            confirmed: confirmed,
            estimatedT3Boost: t3Points,
            assertedFirstEver: asserted,
            pendingMaxPoints: pendingMax,
            total: total
        )
    }

    private static func scoreMobile(
        inputs: TOTAScoringInputs,
        effective: Double,
        t3Boost: Double,
        pendingMax: Double,
        asserted: Double
    ) -> TOTAScoringResult {
        // mobile_total = effective_qsos × (2 if QRP else 1) + flat_bonuses
        let qrpMultiplier = inputs.qrpActivation ? 2.0 : 1.0
        let qsoSubtotal = effective * qrpMultiplier

        let winlinkFlat = inputs.winlinkSent ? 5.0 : 0.0
        let aprsFlat = inputs.aprsSent ? 5.0 : 0.0
        let varacFlat = inputs.varacSent ? 5.0 : 0.0

        let confirmedSubtotal = qsoSubtotal + winlinkFlat + aprsFlat + varacFlat

        let confirmed = TOTAScoringResult.ConfirmedTier(
            effectiveQSOs: effective,
            distanceMiles: 0,
            base: qsoSubtotal,
            qrpMultiplierApplied: inputs.qrpActivation,
            qsoSubtotal: qsoSubtotal,
            winterBonus: 0,
            ruckBonus: 0,
            elevationBonus: 0,
            petsBonus: 0,
            kidsBonus: 0,
            winlinkFlat: winlinkFlat,
            aprsFlat: aprsFlat,
            varacFlat: varacFlat,
            subtotal: confirmedSubtotal
        )

        // T3 in Mobile still doubles the QSO point (no distance multiplier).
        let t3Points = t3Boost * qrpMultiplier
        let total = confirmedSubtotal + t3Points + asserted

        return TOTAScoringResult(
            confirmed: confirmed,
            estimatedT3Boost: t3Points,
            assertedFirstEver: asserted,
            pendingMaxPoints: pendingMax,
            total: total
        )
    }
}
