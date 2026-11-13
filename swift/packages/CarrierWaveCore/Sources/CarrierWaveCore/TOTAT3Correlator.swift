//
//  TOTAT3Correlator.swift
//  CarrierWaveCore
//
//  Pure spot ↔ QSO correlation. Given a list of TOTA spots and a list of
//  QSOs, finds which QSOs were with another tile activator (T3 candidates)
//  by matching callsign + a 6-hour preceding-spot window.
//
//  Per docs/features/tota-scoring.md:
//   - Window: spot.createdAt in [qso.timestamp - 6h, qso.timestamp]
//   - Multiple matches → take closest preceding spot
//   - Spots without `maidenheadGrid` are not T3 (we don't know the chaser's tile)
//

import Foundation

// MARK: - T3SpotRecord

/// Minimum spot shape the correlator needs.
public struct T3SpotRecord: Sendable, Equatable {
    // MARK: Lifecycle

    public init(callsign: String, maidenheadTile: String?, createdAt: Date) {
        self.callsign = callsign
        self.maidenheadTile = maidenheadTile
        self.createdAt = createdAt
    }

    // MARK: Public

    public let callsign: String
    public let maidenheadTile: String?
    public let createdAt: Date
}

// MARK: - T3CorrelatedQSO

public struct T3CorrelatedQSO: Sendable, Equatable {
    // MARK: Lifecycle

    public init(qsoId: UUID, callsign: String, theirTile: String, spotCreatedAt: Date) {
        self.qsoId = qsoId
        self.callsign = callsign
        self.theirTile = theirTile
        self.spotCreatedAt = spotCreatedAt
    }

    // MARK: Public

    public let qsoId: UUID
    public let callsign: String
    public let theirTile: String
    public let spotCreatedAt: Date
}

// MARK: - TOTAT3Correlator

public enum TOTAT3Correlator: Sendable {
    /// Window for matching spots before a QSO.
    public static let defaultWindow: TimeInterval = 6 * 60 * 60

    /// Correlate spots against QSOs to produce T3 candidates.
    public static func correlate(
        spots: [T3SpotRecord],
        qsos: [TOTAScoringQSO],
        window: TimeInterval = defaultWindow
    ) -> [T3CorrelatedQSO] {
        // Index spots by uppercased callsign for fast lookup.
        var byCallsign: [String: [T3SpotRecord]] = [:]
        for spot in spots {
            byCallsign[spot.callsign.uppercased(), default: []].append(spot)
        }

        var result: [T3CorrelatedQSO] = []
        for qso in qsos {
            let key = qso.callsign.uppercased()
            guard let candidates = byCallsign[key] else {
                continue
            }
            let lower = qso.timestamp.addingTimeInterval(-window)
            // Pick the spot with the latest createdAt that is in [lower, qso.timestamp]
            // and has a tile.
            let inWindow = candidates.filter { spot in
                spot.maidenheadTile != nil
                    && spot.createdAt >= lower
                    && spot.createdAt <= qso.timestamp
            }
            guard let best = inWindow.max(by: { $0.createdAt < $1.createdAt }),
                  let tile = best.maidenheadTile
            else {
                continue
            }
            result.append(
                T3CorrelatedQSO(
                    qsoId: qso.id,
                    callsign: qso.callsign,
                    theirTile: tile,
                    spotCreatedAt: best.createdAt
                )
            )
        }
        return result
    }
}
