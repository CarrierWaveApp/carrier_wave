//
//  FT8TranscriptRow.swift
//  CarrierWave
//

import SwiftUI

struct FT8TranscriptRow: View {
    let message: String
    let timestamp: Date
    let isTX: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(timestamp, format: .dateTime.hour().minute().second())
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)

            Image(systemName: isTX ? "arrow.right" : "arrow.left")
                .font(.system(size: 8))
                .foregroundStyle(isTX ? .blue : .secondary)

            Text(message)
                .font(.caption.monospaced())
                .lineLimit(1)

            Spacer()

            Text(isTX ? "TX" : "RX")
                .font(.caption2)
                .foregroundStyle(isTX ? .blue : .secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(isTX ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
    }
}
