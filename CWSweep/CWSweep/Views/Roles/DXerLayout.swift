import SwiftUI

/// DXer layout: DX cluster + band map (multi-band) + DXCC tracker + logger
struct DXerLayout: View {
    let radioManager: RadioManager

    var body: some View {
        HSplitView {
            // Left: Cluster spots
            SpotListView()
                .frame(minWidth: 280)

            // Center: Band map + logger
            VSplitView {
                BandMapView()
                    .frame(minHeight: 300)

                VStack(spacing: 0) {
                    ParsedEntryView(radioManager: radioManager)
                        .padding()

                    Divider()

                    QSOLogTableView()
                        .frame(maxHeight: 200)
                }
            }
            .frame(minWidth: 280)
        }
    }
}
