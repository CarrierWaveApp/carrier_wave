import CarrierWaveData
import SwiftUI

// MARK: - SpotFilterSheet saved-query filter mode

/// "Filter by saved query" mode for the hunter spot list — the iOS
/// mirror of CW Sweep's `bandScopeFilterMode`. Selecting a `.cwquery`
/// makes the engine re-run it after every publish; the snapshot's
/// `allowed_spot_ids` then gates the list on top of the widget filters.
extension SpotFilterSheet {
    var savedQuerySection: some View {
        Section {
            Picker("Saved Query", selection: $filters.savedQueryID) {
                Text("Off").tag(UUID?.none)
                ForEach(availableSavedQueries) { query in
                    Text(query.name).tag(UUID?.some(query.id))
                }
            }
        } header: {
            Text("Filter by Saved Query")
        } footer: {
            savedQueryFooter
        }
    }

    @ViewBuilder
    private var savedQueryFooter: some View {
        if let error = SpotEngineProvider.shared.lastBandScopeQueryError,
           filters.savedQueryID != nil
        {
            Text(error)
                .foregroundStyle(.orange)
        } else if filters.savedQueryID != nil {
            Text(
                "Only spots returned by this query are shown, on top of the "
                    + "filters below. Edit queries in the Spot SQL editor."
            )
        } else if availableSavedQueries.isEmpty {
            Text("Save a query in the Spot SQL editor (Settings › Experiments) to filter with SQL.")
        }
    }

    func loadSavedQueries() async -> [SavedQuery] {
        await (try? SavedQueryStores.makeStore().list()) ?? []
    }
}
