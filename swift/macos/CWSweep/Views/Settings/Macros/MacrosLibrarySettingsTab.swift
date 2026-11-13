import CarrierWaveData
import SwiftUI

// MARK: - MacrosLibrarySettingsTab

/// Settings tab that hosts the macros library. The library itself
/// (`MacrosLibraryView`) is filled in by Task 2 of Plan G; for Task 1 we
/// only wire the tab so SettingsView compiles and shows the placeholder.
struct MacrosLibrarySettingsTab: View {
    var body: some View {
        NavigationStack {
            MacrosLibraryView()
        }
    }
}
