import Foundation

// MARK: - SyncableSettingType

/// Type descriptor for safe encoding/decoding of synced values.
enum SyncableSettingType {
    case bool
    case int
    case double
    case string
    case data // For JSON blobs (tab config, station profiles, equipment lists)
    case stringArray
}

// MARK: - SyncableSetting

/// A single registered setting that participates in iCloud KVS sync.
struct SyncableSetting {
    // MARK: Lifecycle

    init(_ localKey: String, type: SyncableSettingType) {
        self.localKey = localKey
        cloudKey = "v1.\(localKey)"
        self.type = type
    }

    // MARK: Internal

    let localKey: String
    let cloudKey: String
    let type: SyncableSettingType
}

// MARK: - SettingsSyncService

/// Syncs user settings between devices via iCloud Key-Value Store.
///
/// Architecture:
/// ```
/// UserDefaults ←→ SettingsSyncService ←→ NSUbiquitousKeyValueStore ←→ iCloud
/// ```
///
/// - Pull on launch: reads all registered keys from iCloud KVS → writes to UserDefaults
/// - Push on change: detects local UserDefaults changes → pushes diffs to iCloud KVS
/// - Pull on remote change: observes iCloud external change notification → updates UserDefaults
/// - Echo suppression prevents sync loops
@MainActor
final class SettingsSyncService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = SettingsSyncService()

    /// Register a callback that fires after each cloud pull.
    /// Use for bridging UserDefaults → SwiftData (e.g., callsign notes sources).
    /// Must be registered before `start()` to catch the initial pull.
    func onPull(_ callback: @MainActor @escaping () -> Void) {
        postPullCallbacks.append(callback)
    }

    /// Start syncing. Call once from app entry point.
    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true

        let cloud = NSUbiquitousKeyValueStore.default

        // 1. Pull remote values first (remote wins on first launch)
        pullFromCloud()

        // 2. Snapshot current local state for change detection
        captureSnapshot()

        // 3. Push any local-only values that aren't in the cloud yet
        pushFirstSyncValues()

        // 4. Observe remote changes (queue: .main ensures @MainActor safety)
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pullFromCloud()
            }
        }

        // 5. Observe local changes (queue: .main prevents crashes when
        //    frameworks like PencilKit post from background threads)
        localObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.suppressEcho else {
                    return
                }
                self.pushToCloud()
            }
        }

        // 6. Trigger initial sync from iCloud
        cloud.synchronize()
    }

    // MARK: - Testing Hooks

    /// Exposed for unit tests only. Pulls all registered keys from cloud to local.
    func pullFromCloud() {
        let cloud = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard

        suppressEcho = true
        defer {
            suppressEcho = false
            captureSnapshot()
        }

        for setting in SettingsSyncRegistry.allSettings {
            guard let cloudValue = cloud.object(forKey: setting.cloudKey) else {
                continue
            }
            writeToLocal(setting: setting, value: cloudValue, local: local)
        }

        for callback in postPullCallbacks {
            callback()
        }
    }

    /// Exposed for unit tests only. Pushes diff to cloud.
    func pushToCloud() {
        let cloud = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard

        for setting in SettingsSyncRegistry.allSettings {
            let currentValue = local.object(forKey: setting.localKey)
            let snapshotValue = localSnapshot[setting.localKey]

            guard !valuesEqual(currentValue, snapshotValue, type: setting.type) else {
                continue
            }

            if let currentValue {
                cloud.set(currentValue, forKey: setting.cloudKey)
            } else {
                cloud.removeObject(forKey: setting.cloudKey)
            }
        }

        cloud.synchronize()
        captureSnapshot()
    }

    // MARK: Private

    private var isRunning = false
    private var postPullCallbacks: [@MainActor () -> Void] = []

    /// Flag to suppress echo: when true, local writes from cloud pull
    /// won't trigger a push back to cloud.
    private var suppressEcho = false

    /// Snapshot of local UserDefaults values for registered keys.
    /// Used for diffing on `didChangeNotification`.
    private var localSnapshot: [String: Any] = [:]

    /// Observation tokens for block-based notification observers.
    private var cloudObserver: Any?
    private var localObserver: Any?

    // MARK: - Snapshot

    private func captureSnapshot() {
        let local = UserDefaults.standard
        localSnapshot = [:]
        for setting in SettingsSyncRegistry.allSettings {
            if let value = local.object(forKey: setting.localKey) {
                localSnapshot[setting.localKey] = value
            }
        }
    }

    // MARK: - First Sync

    /// On first launch with iCloud, push local values for keys that
    /// have no cloud counterpart yet. This seeds the cloud with the
    /// user's existing settings.
    private func pushFirstSyncValues() {
        let cloud = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard
        var didPush = false

        for setting in SettingsSyncRegistry.allSettings {
            // Skip if cloud already has a value
            guard cloud.object(forKey: setting.cloudKey) == nil else {
                continue
            }
            // Push local value if it exists
            if let localValue = local.object(forKey: setting.localKey) {
                cloud.set(localValue, forKey: setting.cloudKey)
                didPush = true
            }
        }

        if didPush {
            cloud.synchronize()
        }
    }

    // MARK: - Helpers

    private func writeToLocal(
        setting: SyncableSetting,
        value: Any,
        local: UserDefaults
    ) {
        switch setting.type {
        case .bool:
            if let typed = value as? Bool {
                local.set(typed, forKey: setting.localKey)
            }
        case .int:
            if let typed = value as? Int {
                local.set(typed, forKey: setting.localKey)
            }
        case .double:
            if let typed = value as? Double {
                local.set(typed, forKey: setting.localKey)
            }
        case .string:
            if let typed = value as? String {
                local.set(typed, forKey: setting.localKey)
            }
        case .data:
            if let typed = value as? Data {
                local.set(typed, forKey: setting.localKey)
            }
        case .stringArray:
            if let typed = value as? [String] {
                local.set(typed, forKey: setting.localKey)
            }
        }
    }

    private func valuesEqual(_ lhs: Any?, _ rhs: Any?, type: SyncableSettingType) -> Bool {
        if lhs == nil, rhs == nil {
            return true
        }
        guard let lhs, let rhs else {
            return false
        }

        switch type {
        case .bool:
            return (lhs as? Bool) == (rhs as? Bool)
        case .int:
            return (lhs as? Int) == (rhs as? Int)
        case .double:
            return (lhs as? Double) == (rhs as? Double)
        case .string:
            return (lhs as? String) == (rhs as? String)
        case .data:
            return (lhs as? Data) == (rhs as? Data)
        case .stringArray:
            return (lhs as? [String]) == (rhs as? [String])
        }
    }
}
