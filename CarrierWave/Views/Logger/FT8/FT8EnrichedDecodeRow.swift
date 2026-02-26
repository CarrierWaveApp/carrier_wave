//
//  FT8EnrichedDecodeRow.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

// MARK: - FT8EnrichedDecodeRow

/// Multi-line enriched decode row with callsign, SNR badge, grid, entity,
/// distance, and achievement badges.
struct FT8EnrichedDecodeRow: View {
    // MARK: Internal

    let enriched: FT8EnrichedDecode
    let isCurrentCycle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            essentialsLine
            if hasContextLine {
                contextLine
            }
            if hasBadges {
                badgeLine
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .opacity(enriched.isDupe ? 0.5 : 1.0)
        .contentShape(Rectangle())
    }

    // MARK: Private

    private var callsign: String {
        enriched.decode.message.callerCallsign ?? enriched.decode.rawText
    }

    private var hasContextLine: Bool {
        enriched.dxccEntity != nil || enriched.distanceMiles != nil
    }

    private var hasBadges: Bool {
        enriched.isNewDXCC || enriched.isNewState || enriched.isNewGrid
            || enriched.isNewBand || enriched.isDupe
    }

    // MARK: Line 1 — Essentials

    private var essentialsLine: some View {
        HStack(spacing: 8) {
            Text(callsign)
                .font(.headline.monospaced().weight(.semibold))
                .fontWeight(isCurrentCycle ? .bold : .semibold)

            FT8SNRBadge(snr: enriched.decode.snr)

            if let grid = enriched.decode.message.grid {
                Text(grid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if enriched.decode.message.isCallable {
                cqBadge
            }

            if enriched.decode.message.isCallable {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var cqBadge: some View {
        if let modifier = enriched.decode.message.cqModifier {
            Text("CQ \(modifier)")
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())
        } else {
            Text("CQ")
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())
        }
    }

    // MARK: Line 2 — Context

    private var contextLine: some View {
        HStack(spacing: 4) {
            if let entity = enriched.dxccEntity {
                Text(entity)
            }
            if let state = enriched.stateProvince {
                Text("\u{00B7}")
                Text(state)
            }
            if let miles = enriched.distanceMiles {
                Text("\u{00B7}")
                Text("\(miles.formatted()) mi")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Line 3 — Badges

    private var badgeLine: some View {
        HStack(spacing: 4) {
            if enriched.isNewDXCC {
                FT8AchievementBadge.newDXCC
            }
            if enriched.isNewState {
                FT8AchievementBadge.newState
            }
            if enriched.isNewGrid {
                FT8AchievementBadge.newGrid
            }
            if enriched.isNewBand {
                FT8AchievementBadge.newBand
            }
            if enriched.isDupe {
                FT8AchievementBadge.dupe
            }
        }
    }
}

// MARK: - FT8DirectedDecodeRow

/// Row variant for "Directed at You" section with orange left border.
struct FT8DirectedDecodeRow: View {
    let enriched: FT8EnrichedDecode

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange)
                .frame(width: 4)

            FT8EnrichedDecodeRow(enriched: enriched, isCurrentCycle: true)
        }
    }
}
