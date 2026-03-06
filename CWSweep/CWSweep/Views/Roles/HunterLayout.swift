import SwiftUI

/// Hunter layout: Spot list + quick log + band map (compact)
struct HunterLayout: View {
    let radioManager: RadioManager

    var body: some View {
        HSplitView {
            // Left: Spot list (primary)
            SpotListView()
                .frame(minWidth: 280)

            // Right: Quick log + compact band map
            VSplitView {
                VStack(spacing: 0) {
                    ParsedEntryView(radioManager: radioManager)
                        .padding()

                    Divider()

                    // Recent QSOs
                    QSOLogTableView()
                }
                .frame(minHeight: 300, idealHeight: 400)

                BandMapView()
                    .frame(minHeight: 200, idealHeight: 250)
            }
            .frame(minWidth: 280)
        }
    }
}
