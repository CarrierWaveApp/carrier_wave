import SwiftUI

// MARK: - LoggerSpotsSidebarView

/// Tabbed sidebar for iPad showing POTA spots, RBN/My Spots, and P2P opportunities.
/// Lives alongside LoggerView in a horizontal layout.
struct LoggerSpotsSidebarView: View {
    // MARK: Internal

    @Binding var selectedTab: SidebarTab
    @Binding var rbnTargetCallsign: String?

    let userCallsign: String?
    let userGrid: String?
    let isPOTAActivation: Bool
    let currentBand: String?
    let currentMode: String?
    let onSelectSpot: (SpotSelection) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabPicker
            Divider()
            tabContent
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Private

    private var visibleTabs: [SidebarTab] {
        if isPOTAActivation {
            SidebarTab.allCases
        } else {
            [.pota, .mySpots]
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Spots", selection: $selectedTab) {
            ForEach(visibleTabs) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .pota:
            SidebarPOTASpotsView(
                userCallsign: userCallsign,
                initialBand: currentBand,
                initialMode: currentMode,
                onSelectSpot: { spot in
                    onSelectSpot(.pota(spot))
                }
            )

        case .mySpots:
            SidebarRBNSpotsView(
                callsign: userCallsign
                    ?? UserDefaults.standard.string(forKey: "loggerDefaultCallsign")
                    ?? "UNKNOWN",
                targetCallsign: rbnTargetCallsign,
                onSelectSpot: { spot in
                    onSelectSpot(.rbn(spot))
                }
            )

        case .p2p:
            SidebarP2PView(
                userCallsign: userCallsign,
                userGrid: userGrid,
                isPOTAActivation: isPOTAActivation,
                initialBand: currentBand,
                initialMode: currentMode,
                onSelectOpportunity: { opportunity in
                    onSelectSpot(.p2p(opportunity))
                }
            )
        }
    }
}
