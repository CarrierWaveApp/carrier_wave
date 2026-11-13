//
//  FT8EnrichedDecodeRow.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

// MARK: - FT8EnrichedDecodeRow

/// Multi-line enriched decode row with callsign, SNR badge, grid, entity,
/// distance, and achievement badges.
struct FT8EnrichedDecodeRow: View {
    // MARK: Internal

    let enriched: FT8EnrichedDecode
    let isCurrentCycle: Bool

    var body: some View {
        HStack(spacing: 0) {
            if enriched.cycleAge == 0 {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: 3)
            }

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
        }
        .opacity(enriched.isDupe ? 0.5 : freshnessOpacity)
        .contentShape(Rectangle())
    }

    // MARK: Private

    private var freshnessOpacity: Double {
        switch enriched.cycleAge {
        case 0 ... 1: 1.0
        case 2 ... 3: 0.6
        default: 0.4
        }
    }

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

            Text("\(Int(enriched.decode.frequency)) Hz")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)

            if let grid = enriched.decode.message.grid {
                Text(grid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if enriched.isDirectedAtMe {
                youPill
            } else if enriched.decode.message.isCallable {
                cqBadge
            }

            if enriched.isDirectedAtMe {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
            } else if enriched.decode.message.isCallable {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var youPill: some View {
        Text("→ YOU")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange)
            .clipShape(Capsule())
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

/// Row variant for "Directed at You" section. Loud orange tint + accent bar so a
/// fresh call from another station is impossible to miss.
struct FT8DirectedDecodeRow: View {
    // MARK: Internal

    let enriched: FT8EnrichedDecode

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.orange)
                .frame(width: 6)

            FT8EnrichedDecodeRow(enriched: enriched, isCurrentCycle: true)
        }
        .background(Color.orange.opacity(backgroundOpacity))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.orange.opacity(0.4))
                .frame(height: 0.5)
        }
    }

    // MARK: Private

    private var backgroundOpacity: Double {
        switch enriched.cycleAge {
        case 0: 0.22
        case 1: 0.14
        default: 0.08
        }
    }
}
