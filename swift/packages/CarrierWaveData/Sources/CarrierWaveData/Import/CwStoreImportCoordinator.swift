import CarrierWaveCore
import Foundation
import Security
import SwiftData

// Orchestrates the one-time SwiftData → cw-store seed import on-device: resolves
// the store location + at-rest key, runs the import, verifies it, and records
// completion so it never runs twice per app version. The actual field work is in
// SwiftDataStoreImporter; this is the thin "where + when" layer.
//
// Triggered from `CarrierWaveApp.applyQSOMirrorMode` at launch (Phase 1c made
// the mirror default-on), so it re-runs a full re-seed on the first launch of
// every new app version. The importer does all row work off-main on fresh
// per-batch contexts (bounded memory) and commits each batch as one
// transaction. The at-rest key is device-local and non-synced (per-device by
// design; see KeychainHelper.Keys.cwStoreEncryptionKey).

// MARK: - CwStoreImportError

public enum CwStoreImportError: Error, Sendable {
    case appGroupUnavailable(String)
    case keyGenerationFailed(OSStatus)
}

// MARK: - CwStoreImportCoordinator

public struct CwStoreImportCoordinator: Sendable {
    // MARK: Lifecycle

    /// Injectable core. Tests pass a temp `storeURL`, a fixed `key`, and an
    /// isolated `defaults` suite.
    public init(
        storeURL: URL,
        key: @escaping @Sendable () throws -> String,
        defaults: UserDefaults,
        completionVersion: String,
        markerKey: String = CwStoreImportCoordinator.importMarkerKey
    ) {
        self.storeURL = storeURL
        self.key = key
        self.defaults = defaults
        self.completionVersion = completionVersion
        self.markerKey = markerKey
    }

    // MARK: Public

    public enum Outcome: Sendable, Equatable {
        case alreadyComplete
        case completed(ImportReport)
        case verificationFailed([VerifyReport.Table])
    }

    /// `UserDefaults` key holding the last app version whose SwiftData→store
    /// import completed *and verified*. Non-nil ⇒ the store has been fully
    /// populated at least once.
    public static let importMarkerKey = "cwStoreImportCompletedVersion"

    /// True once a full import+verify has completed at least once — the gate the
    /// CloudKit journal checks before treating the store as QSO-authoritative, so
    /// a `.on` flag never points sync at a not-yet-imported (empty) store.
    public static func hasEverCompletedImport(defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: importMarkerKey) != nil
    }

    /// App-facing convenience: store at `CwStoreLocation.storeURL`, key from the
    /// device-local keychain, marker in `UserDefaults`.
    public static func appGroup(
        appGroupID: String = CwStoreLocation.defaultAppGroupID,
        version: String,
        defaults: UserDefaults = .standard
    ) throws -> CwStoreImportCoordinator {
        let storeURL = try CwStoreLocation.storeURL(appGroupID: appGroupID)
        return CwStoreImportCoordinator(
            storeURL: storeURL,
            key: { try CwStoreProvider.localEncryptionKey() },
            defaults: defaults,
            completionVersion: version
        )
    }

    /// Run the import unless it has already completed for `completionVersion`.
    /// Imports into the on-disk store, verifies count agreement, and only then
    /// records completion — a partial/failed run never looks done (an
    /// interrupted run simply resumes from scratch next launch; upserts are
    /// idempotent). Each batch fetches on a fresh off-main `ModelContext` and
    /// commits as one transaction (bounded memory, no main-thread disk
    /// barriers — see SwiftDataStoreImporter's header), so calling this from
    /// the main actor is safe even for 100k-row logs.
    public func runIfNeeded(from container: ModelContainer) async throws -> Outcome {
        if defaults.string(forKey: markerKey) == completionVersion {
            return .alreadyComplete
        }
        let store = try FieldStore.open(path: storeURL.path, key: key())
        let importer = SwiftDataStoreImporter(container: container)
        let report = try await importer.importAll(into: store)
        let verification = try await importer.compareCounts(to: store)
        guard verification.ok else {
            return .verificationFailed(verification.mismatches)
        }
        defaults.set(completionVersion, forKey: markerKey)
        return .completed(report)
    }

    // MARK: Private

    private let storeURL: URL
    private let key: @Sendable () throws -> String
    private let defaults: UserDefaults
    private let completionVersion: String
    private let markerKey: String
}
