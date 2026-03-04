import CarrierWaveData
import Foundation

// MARK: - CWError

/// Errors for CW transcription and audio processing
enum CWError: Error, LocalizedError {
    case microphonePermissionDenied
    case microphonePermissionRestricted
    case audioEngineStartFailed(Error)
    case audioSessionSetupFailed(Error)
    case noInputAvailable
    case processingFailed(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone access denied. Please enable in Settings."
        case .microphonePermissionRestricted:
            "Microphone access is restricted on this device."
        case let .audioEngineStartFailed(error):
            "Failed to start audio engine: \(error.localizedDescription)"
        case let .audioSessionSetupFailed(error):
            "Failed to setup audio session: \(error.localizedDescription)"
        case .noInputAvailable:
            "No audio input available."
        case let .processingFailed(reason):
            "Audio processing failed: \(reason)"
        }
    }
}
