// Sidebar Map View
//
// Lightweight map view for the iPad sidebar showing current session QSOs.
// Wraps SessionQSOMap with a compact stats bar header.

import CarrierWaveData
import SwiftUI

// MARK: - SidebarMapView

struct SidebarMapView: View {
    // MARK: Internal

    let sessionQSOs: [QSO]
    let myGrid: String?
    var roveStops: [RoveStop] = []

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            Divider()
            SessionQSOMap(
                sessionQSOs: sessionQSOs,
                myGrid: myGrid,
                roveStops: roveStops
            )
        }
    }

    // MARK: Private

    private var isRove: Bool {
        !roveStops.isEmpty
    }

    private var mappedCount: Int {
        sessionQSOs.filter { ($0.theirGrid?.count ?? 0) >= 4 }.count
    }

    private var statsBar: some View {
        HStack {
            Image(systemName: "map.fill")
                .foregroundStyle(.blue)

            if isRove {
                Text("\(roveStops.count) stops")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Text("\(mappedCount) QSOs mapped")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
