import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - MacrosLibraryView

/// Top-level entry point for the radio macros library in CW Sweep,
/// reached from Settings → Macros tab. Mirrors the iOS shape: segmented
/// Mine / Browse / Updates with a NavigationStack push to the detail
/// view. The Settings window is 750 pt wide — too narrow for a real
/// NavigationSplitView, so we stick with stack navigation.
struct MacrosLibraryView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.selectedTab) {
                ForEach(MacroLibraryModel.LibraryTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .labelsHidden()

            Divider()

            switch model.selectedTab {
            case .mine:
                MacrosLibraryMineTab(model: model)
            case .browse:
                MacrosLibraryBrowseTab(model: model)
            case .updates:
                MacrosLibraryUpdatesTab(model: model)
            }
        }
        .navigationTitle("Macros")
        .task {
            // Holder is configured at app launch (CWSweepApp). Refresh on
            // tab appearance so Updates land sooner.
            await MacrosRegistryHolder.shared.pollIfStale()
        }
    }

    // MARK: Private

    @State private var model = MacroLibraryModel()
}

// MARK: - MacrosLibraryPlaceholderTab

struct MacrosLibraryPlaceholderTab: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }
}
