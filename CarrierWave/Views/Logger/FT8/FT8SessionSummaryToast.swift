//
//  FT8SessionSummaryToast.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

struct FT8SessionSummaryToast: View {
    // MARK: Internal

    let band: String
    let qsoCount: Int
    let duration: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("FT8 Session Complete")
                    .font(.subheadline.bold())
            }

            Text("\(formattedDuration) on \(band) · \(qsoCount) QSOs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
        .padding(.horizontal)
    }

    // MARK: Private

    private var formattedDuration: String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        return "\(hours)h \(remaining)m"
    }
}
