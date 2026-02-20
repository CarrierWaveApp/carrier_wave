import SwiftUI

/// Idle mode: swipeable pages for solar, spots, stats, and quick start.
struct IdleView: View {
    var body: some View {
        TabView {
            SolarView()
            SpotsListView()
            StatsView()
            QuickStartView()
        }
        .tabViewStyle(.verticalPage)
    }
}
