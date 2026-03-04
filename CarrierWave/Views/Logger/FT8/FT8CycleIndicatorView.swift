//
//  FT8CycleIndicatorView.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

struct FT8CycleIndicatorView: View {
    // MARK: Internal

    let isTransmitting: Bool
    let timeRemaining: Double

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isTransmitting ? Color.orange : Color.blue)
                .frame(width: 8, height: 8)
            Text(isTransmitting ? "TX" : "RX")
                .font(.caption.bold())
                .foregroundStyle(isTransmitting ? .orange : .blue)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isTransmitting ? Color.orange : Color.blue)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 8)

            Text("\(Int(timeRemaining))s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }

    // MARK: Private

    private static let slotDuration = 15.0

    private var progress: Double {
        max(0, min(1, (FT8CycleIndicatorView.slotDuration - timeRemaining) / FT8CycleIndicatorView.slotDuration))
    }
}
