import Foundation

// MARK: - CwStoreSyncMode

/// Rollout seam for which engine owns cross-device QSO sync (Phase 7.2 of the
/// sync-server plan). Stored in `@AppStorage("cwStoreSyncMode")`, mirroring the
/// `CwStoreQSOMode` pattern.
///
/// - `.off` (default, all platforms): today's behavior — `CloudSyncJournalEngine`
///   drives CloudKit via `CKSyncEngine`.
/// - `.serverSync`: `CloudSyncJournalEngine` skips `CKSyncEngine` entirely and
///   drives the E2E Carrier Wave server via the injected server-sync runner
///   (`sync_run_once` through cw-ffi).
///
/// This is the selection seam only. The authority flip to `.serverSync` is
/// user-gated on a two-device round-trip verification — do not change the
/// default without that sign-off.
public enum CwStoreSyncMode: String, CaseIterable, Sendable {
    case off
    case serverSync

    // MARK: Public

    public static let appStorageKey = "cwStoreSyncMode"

    /// The current mode read from `UserDefaults` (the backing store for the
    /// `@AppStorage("cwStoreSyncMode")` picker). Lets non-View code
    /// (`CloudSyncJournalEngine`, background triggers) route by mode without a
    /// SwiftUI binding. Defaults to `.off` everywhere.
    public static var current: CwStoreSyncMode {
        guard let raw = UserDefaults.standard.string(forKey: appStorageKey),
              let mode = CwStoreSyncMode(rawValue: raw)
        else {
            return .off
        }
        return mode
    }

    /// Whether the CloudKit `CKSyncEngine` should be constructed and driven.
    public var startsCKSyncEngine: Bool {
        self == .off
    }

    /// Whether journal-engine sync entry points should be routed to the
    /// E2E server-sync runner instead of CloudKit.
    public var drivesServerSync: Bool {
        self == .serverSync
    }
}
