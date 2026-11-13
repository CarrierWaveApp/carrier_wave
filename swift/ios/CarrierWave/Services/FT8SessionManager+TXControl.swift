//
//  FT8SessionManager+TXControl.swift
//  CarrierWave
//

import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - TX Control & Channel Recommendation

extension FT8SessionManager {
    func haltTX() {
        isTXHalted = true
        if let call = qsoStateMachine.theirCallsign {
            txState = .halted(callsign: call)
        }
    }

    func resumeTX() {
        isTXHalted = false
        if let call = qsoStateMachine.theirCallsign {
            txState = .armed(callsign: call)
        }
    }

    /// Analyze recent decodes to recommend the least-occupied channels.
    func recommendedChannels() -> [ChannelRecommendation] {
        let binWidth = 50.0
        let minHz = 200.0
        let maxHz = 2_800.0
        let binCount = Int((maxHz - minHz) / binWidth)

        // Count decodes per bin across all retained results
        var bins = [Int](repeating: 0, count: binCount)
        for result in decodeResults {
            let freq = result.frequency
            guard freq >= minHz, freq < maxHz else {
                continue
            }
            let idx = Int((freq - minHz) / binWidth)
            if idx >= 0, idx < binCount {
                bins[idx] += 1
                // Penalise adjacent bins (guard band)
                if idx > 0 {
                    bins[idx - 1] += 1
                }
                if idx < binCount - 1 {
                    bins[idx + 1] += 1
                }
            }
        }

        let maxCount = bins.max() ?? 0
        var recommendations: [ChannelRecommendation] = []
        for i in 0 ..< binCount {
            let freq = minHz + Double(i) * binWidth + binWidth / 2
            let count = bins[i]
            let occupancy: ChannelRecommendation.OccupancyLevel = if count == 0 {
                .clear
            } else if maxCount > 0, Double(count) / Double(maxCount) < 0.25 {
                .quiet
            } else if maxCount > 0, Double(count) / Double(maxCount) < 0.6 {
                .fair
            } else {
                .busy
            }
            recommendations.append(ChannelRecommendation(
                frequency: freq,
                activityCount: count,
                occupancy: occupancy
            ))
        }

        return recommendations.sorted { $0.activityCount < $1.activityCount }
    }
}
