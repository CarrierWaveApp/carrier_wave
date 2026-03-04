//
//  FT8BadgeViews.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

// MARK: - FT8AchievementBadge

/// Achievement badge for worked-before status (NEW DXCC, NEW BAND, DUPE, etc.)
struct FT8AchievementBadge: View {
    let label: String
    let foregroundColor: Color
    let backgroundColor: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Preset Badges

extension FT8AchievementBadge {
    static var newDXCC: FT8AchievementBadge {
        FT8AchievementBadge(
            label: "NEW DXCC",
            foregroundColor: .yellow,
            backgroundColor: Color.yellow.opacity(0.3)
        )
    }

    static var newState: FT8AchievementBadge {
        FT8AchievementBadge(
            label: "NEW STATE",
            foregroundColor: .blue,
            backgroundColor: Color.blue.opacity(0.15)
        )
    }

    static var newGrid: FT8AchievementBadge {
        FT8AchievementBadge(
            label: "NEW GRID",
            foregroundColor: .cyan,
            backgroundColor: Color.cyan.opacity(0.15)
        )
    }

    static var newBand: FT8AchievementBadge {
        FT8AchievementBadge(
            label: "NEW BAND",
            foregroundColor: .white,
            backgroundColor: .blue
        )
    }

    static var dupe: FT8AchievementBadge {
        FT8AchievementBadge(
            label: "DUPE",
            foregroundColor: .orange,
            backgroundColor: Color.orange.opacity(0.2)
        )
    }
}

// MARK: - FT8SNRBadge

/// Colored SNR badge indicating signal strength tier.
struct FT8SNRBadge: View {
    // MARK: Internal

    let snr: Int

    var body: some View {
        Text("\(snr)")
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: Private

    private var tier: FT8EnrichedDecode.SNRTier {
        FT8EnrichedDecode.snrTier(forSNR: snr)
    }

    private var foregroundColor: Color {
        switch tier {
        case .strong: .green
        case .medium: .yellow
        case .weak: .orange
        }
    }

    private var backgroundColor: Color {
        switch tier {
        case .strong: Color.green.opacity(0.2)
        case .medium: Color.yellow.opacity(0.2)
        case .weak: Color.orange.opacity(0.2)
        }
    }
}
