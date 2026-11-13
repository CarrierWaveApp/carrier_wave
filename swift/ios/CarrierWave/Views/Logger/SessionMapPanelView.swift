// Session Map Panel View for Logger
//
// Displays a map of QSOs from the current logging session.
// Wraps SessionQSOMap with a dismiss header for the phone logger overlay.

import CarrierWaveData
import SwiftUI

// MARK: - SessionMapPanelView

struct SessionMapPanelView: View {
    // MARK: Internal

    let sessionQSOs: [QSO]
    let myGrid: String?
    var roveStops: [RoveStop] = []
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            SessionQSOMap(
                sessionQSOs: sessionQSOs,
                myGrid: myGrid,
                roveStops: roveStops
            )
            .frame(height: 250)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
    }

    // MARK: Private

    private var isRove: Bool {
        !roveStops.isEmpty
    }

    private var mappedCount: Int {
        sessionQSOs.filter { ($0.theirGrid?.count ?? 0) >= 4 }.count
    }

    private var header: some View {
        HStack {
            Image(systemName: "map.fill")
                .foregroundStyle(.blue)

            Text(isRove ? "Rove Map" : "Session Map")
                .font(.headline)

            Spacer()

            if isRove {
                Text("\(roveStops.count) stops")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Text("\(mappedCount) QSOs")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }
}
