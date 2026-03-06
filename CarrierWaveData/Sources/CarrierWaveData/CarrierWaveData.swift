// CarrierWaveData — Shared models and services for Carrier Wave ecosystem
//
// This package contains:
// - SwiftData models (QSO, ServicePresence, LoggingSession, etc.)
// - Protocol abstractions for platform-specific features
// - Shared utilities (KeychainHelper)
//
// Used by both Carrier Wave (iOS) and CW Sweep (macOS).

@_exported import CarrierWaveCore
import SwiftData

/// SwiftData schema containing all shared models
public enum CarrierWaveSchema {
    public static let models: [any PersistentModel.Type] = [
        QSO.self,
        ServicePresence.self,
        LoggingSession.self,
        ActivationMetadata.self,
        SessionSpot.self,
        ActivityLog.self,
        CloudSyncMetadata.self,
        UploadDestination.self,
        WebSDRRecording.self,
        WebSDRFavorite.self,
    ]
}
