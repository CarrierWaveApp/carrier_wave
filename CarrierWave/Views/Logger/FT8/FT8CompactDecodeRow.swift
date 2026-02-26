//
//  FT8CompactDecodeRow.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

/// Single-line compact decode row for space-constrained or preference-based display.
struct FT8CompactDecodeRow: View {
    let enriched: FT8EnrichedDecode

    var body: some View {
        HStack(spacing: 6) {
            Text(enriched.decode.message.callerCallsign ?? "???")
                .font(.caption.monospaced().weight(.medium))
                .frame(width: 72, alignment: .leading)

            Text("\(enriched.decode.snr)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            if let grid = enriched.decode.message.grid {
                Text(grid)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
            }

            if enriched.decode.message.isCallable {
                Text("CQ")
                    .font(.caption2.bold())
                    .foregroundStyle(.blue)
            }

            if let entity = enriched.dxccEntity {
                Text(entity)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if enriched.isNewDXCC {
                Text("NEW DXCC")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.yellow)
            } else if enriched.isNewGrid {
                Text("NEW GRID")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.cyan)
            } else if enriched.isDupe {
                Text("DUPE")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .opacity(enriched.isDupe ? 0.5 : 1.0)
        .contentShape(Rectangle())
    }
}
