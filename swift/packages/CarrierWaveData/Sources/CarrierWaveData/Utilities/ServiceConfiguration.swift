import CarrierWaveCore
import Foundation

// MARK: - ServiceConfiguration

/// Checks which upload services are configured by inspecting Keychain credentials.
/// Thread-safe — KeychainHelper reads are synchronous and safe from any thread.
public enum ServiceConfiguration {
    // MARK: Public

    /// Returns the set of upload-capable services that have credentials configured.
    /// Use this to avoid creating ServicePresence upload markers for unconfigured services.
    public static func configuredUploadServices() -> Set<ServiceType> {
        var configured: Set<ServiceType> = []
        let keychain = KeychainHelper.shared

        // QRZ: needs API key
        if (try? keychain.read(for: KeychainHelper.Keys.qrzApiKey)) != nil {
            configured.insert(.qrz)
        }

        // POTA: needs stored token
        if (try? keychain.readString(for: KeychainHelper.Keys.potaIdToken)) != nil {
            configured.insert(.pota)
        }

        // Club Log: "Coming Soon" — not yet configurable as a sync source

        // eQSL: needs username + password
        if (try? keychain.readString(for: KeychainHelper.Keys.eqslUsername)) != nil,
           (try? keychain.readString(for: KeychainHelper.Keys.eqslPassword)) != nil
        {
            configured.insert(.eqsl)
        }

        return configured
    }

    /// Check if a specific upload service is configured.
    public static func isConfigured(_ service: ServiceType) -> Bool {
        let keychain = KeychainHelper.shared
        switch service {
        case .qrz:
            return (try? keychain.read(for: KeychainHelper.Keys.qrzApiKey)) != nil
        case .pota:
            return (try? keychain.readString(for: KeychainHelper.Keys.potaIdToken)) != nil
        case .clublog:
            return false // "Coming Soon" — not yet configurable as a sync source
        case .eqsl:
            return (try? keychain.readString(for: KeychainHelper.Keys.eqslUsername)) != nil
                && (try? keychain.readString(for: KeychainHelper.Keys.eqslPassword)) != nil
        case .lofi,
             .lotw,
             .hamrs:
            return false // Not upload services
        }
    }

    /// Get the sync mode for a service. Defaults to `.bidirectional`.
    public static func syncMode(for service: ServiceType) -> SyncMode {
        guard let raw = UserDefaults.standard.string(forKey: syncModeKey(for: service)),
              let mode = SyncMode(rawValue: raw)
        else {
            return .bidirectional
        }
        return mode
    }

    /// Set the sync mode for a service.
    public static func setSyncMode(_ mode: SyncMode, for service: ServiceType) {
        UserDefaults.standard.set(mode.rawValue, forKey: syncModeKey(for: service))
    }

    /// Whether uploads are enabled for a service (based on its sync mode).
    public static func isUploadEnabled(for service: ServiceType) -> Bool {
        syncMode(for: service).isUploadEnabled
    }

    /// Whether downloads are enabled for a service (based on its sync mode).
    public static func isDownloadEnabled(for service: ServiceType) -> Bool {
        syncMode(for: service).isDownloadEnabled
    }

    // MARK: Private

    // MARK: - Per-Service Sync Mode

    /// UserDefaults key for a service's sync mode.
    private static func syncModeKey(for service: ServiceType) -> String {
        "syncMode.\(service.rawValue)"
    }
}
