import CarrierWaveData
import UIKit

// MARK: - SavedQueryStores

/// Single home for the on-disk `.cwquery` saved-query store location.
/// Shared by the spot SQL editor, the band scope, the hunter spot
/// filter's saved-query mode, and `cwquery://` deep-link imports so
/// they all read and write the same directory.
enum SavedQueryStores {
    /// Saved queries live in the same iCloud Drive directory CW Sweep
    /// writes to, so authoring on macOS shows up on the phone
    /// automatically. Falls back to local Application Support when
    /// iCloud Drive is unavailable.
    ///
    /// `nonisolated` — called from detached tasks (band-scope query
    /// application) as well as the main actor; touches only FileManager.
    nonisolated static func makeStore() -> SavedQueryStore {
        let directory: URL
        if let iCloud = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.com.jsvana.FullDuplex"
        ) {
            directory = iCloud.appendingPathComponent("Documents/Queries", isDirectory: true)
        } else {
            let appSupport = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            directory = appSupport
                .appendingPathComponent("CarrierWave", isDirectory: true)
                .appendingPathComponent("Queries", isDirectory: true)
        }
        return SavedQueryStore(directory: directory)
    }
}
