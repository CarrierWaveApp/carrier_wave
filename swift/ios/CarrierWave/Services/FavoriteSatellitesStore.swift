import SwiftUI

// MARK: - FavoriteSatellitesStore

/// The operator's favorited birds (NORAD IDs), persisted as a JSON array in
/// UserDefaults. Favorites drive pass alerts (`SatellitePassAlertScheduler`)
/// and sort first in the satellite lists. A singleton because the scheduler,
/// the background-refresh task, and several views all need one instance while
/// `SatelliteTrackerModel` stays view-owned.
@MainActor
@Observable
final class FavoriteSatellitesStore {
    // MARK: Lifecycle

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let ids = try? JSONDecoder().decode([Int].self, from: data)
        {
            noradIDs = Set(ids)
        } else {
            noradIDs = []
        }
    }

    // MARK: Internal

    static let shared = FavoriteSatellitesStore()

    /// Called after every change — wired to the alert scheduler's reschedule.
    var onChange: (() -> Void)?

    private(set) var noradIDs: Set<Int>

    func isFavorite(_ noradID: Int) -> Bool {
        noradIDs.contains(noradID)
    }

    func toggle(_ noradID: Int) {
        if noradIDs.contains(noradID) {
            noradIDs.remove(noradID)
        } else {
            noradIDs.insert(noradID)
        }
        persist()
        onChange?()
    }

    // MARK: Private

    private static let defaultsKey = "satelliteFavoriteNoradIDs"

    private func persist() {
        let ids = noradIDs.sorted()
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
