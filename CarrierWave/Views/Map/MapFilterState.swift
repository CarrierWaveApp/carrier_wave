import CarrierWaveData
import Foundation

/// Filter state for the QSO map view
@Observable
final class MapFilterState {
    /// Maximum QSOs to display for performance
    static let maxQSOsDefault = 500

    var startDate: Date?
    var endDate: Date?
    var selectedBand: String?
    var selectedMode: String?
    var selectedPark: String?
    var confirmedOnly: Bool = false
    var showPaths: Bool = false
    var showIndividualQSOs: Bool = false
    var showAllQSOs: Bool = false

    /// Check if any filter is active
    var hasActiveFilters: Bool {
        startDate != nil || endDate != nil || selectedBand != nil ||
            selectedMode != nil || selectedPark != nil || confirmedOnly
    }

    /// Reset all filters
    func resetFilters() {
        startDate = nil
        endDate = nil
        selectedBand = nil
        selectedMode = nil
        selectedPark = nil
        confirmedOnly = false
    }
}
