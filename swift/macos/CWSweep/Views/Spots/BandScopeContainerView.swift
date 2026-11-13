import SwiftUI

// MARK: - BandScopeContainerView

/// Legacy panel target preserved for layouts saved before the band
/// scope was split into four dedicated panels (single / rail /
/// stacked / grid). Reads the user's last-picked mode from
/// `bandScopeLayout` so saved layouts keep showing the same view, but
/// no longer offers an in-place mode picker — users now place each
/// variant as its own widget via the layout editor.
struct BandScopeContainerView: View {
    // MARK: Internal

    var body: some View {
        switch layout {
        case .single: ContestBandScopeView(showSummaryBar: true)
        case .hybrid: BandScopeHybridPane()
        case .stacked: StackedBandScopeView()
        case .grid: GridBandOverviewView()
        }
    }

    // MARK: Private

    @AppStorage("bandScopeLayout") private var layout: BandScopeLayout = .hybrid
}

// MARK: - BandScopeHybridPane

/// "Band Scope + Rail" variant — contest scope alongside the band
/// rail. Lives here (instead of inline in PanelRegistry) so its body
/// stays small enough that the AnyView dispatch doesn't blow up the
/// type checker.
struct BandScopeHybridPane: View {
    var body: some View {
        HSplitView {
            ContestBandScopeView(showSummaryBar: false)
            BandRailView()
        }
    }
}
