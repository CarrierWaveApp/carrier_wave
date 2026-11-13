import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - MacrosLibraryView

/// Top-level entry point for the radio macros library, reached from
/// Settings → Experiments → Radio CAT Control → Macros. Phase 1 only
/// populates the Mine tab; Browse + Updates are stubs that ship in
/// Plan E (server registry).
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ExperimentalBadge(feature: .radioControl)
            }
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
