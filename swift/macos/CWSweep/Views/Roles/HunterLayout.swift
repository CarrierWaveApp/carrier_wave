import SwiftUI

/// Hunter layout: entry + log + spots on left, band scope on right.
/// When radio sends scope data, waterfall renders inside the band scope.
struct HunterLayout: View {
    let radioManager: RadioManager

    var body: some View {
        GeometryReader { geo in
            HSplitView {
                VSplitView {
                    VStack(spacing: 0) {
                        ParsedEntryView(radioManager: radioManager)
                            .padding()
                        Divider()
                        QSOLogTableView()
                            .vimPaneFocus(.qsoLog)
                    }
                    .frame(minHeight: 120, idealHeight: 350)

                    SpotListView()
                        .vimPaneFocus(.spotList)
                        .frame(minHeight: 200, idealHeight: 350)
                }
                .layoutPriority(1)

                BandScopeContainerView()
                    .vimPaneFocus(.bandScope)
                    .frame(minWidth: 200, maxWidth: geo.size.width / 2)
            }
        }
    }
}
