import Foundation

// MARK: - PendingUploadReason

/// Classifies why a QSO is pending upload to a service.
/// Used by the Pending Uploads view for user-facing diagnostics.
public enum PendingUploadReason: String, CaseIterable, Sendable {
    /// Fresh QSO, will upload on next sync
    case notYetAttempted
    /// Missing both band and frequency
    case missingFields
    /// POTA QSO without park reference
    case missingParkReference
    /// POTA upload permanently rejected (invalid park)
    case invalidParkReference
    /// myCallsign doesn't match primary callsign
    case callsignMismatch
    /// stationCallsign is set (club station)
    case clubStation
    /// Service auth not configured
    case serviceNotConfigured
    /// Transient upload failure (network, timeout, maintenance)
    case uploadFailed
    /// POTA: submitted but awaiting job confirmation
    case awaitingConfirmation
    /// Bug: metadata pseudo-mode has needsUpload
    case metadataMode
    /// Soft-deleted QSO still has needsUpload
    case hidden

    // MARK: Public

    /// Human-readable title
    public var title: String {
        switch self {
        case .notYetAttempted: "Not Yet Uploaded"
        case .missingFields: "Missing Band/Frequency"
        case .missingParkReference: "No Park Reference"
        case .invalidParkReference: "Invalid Park Reference"
        case .callsignMismatch: "Callsign Mismatch"
        case .clubStation: "Club Station"
        case .serviceNotConfigured: "Service Not Configured"
        case .uploadFailed: "Upload Failed"
        case .awaitingConfirmation: "Awaiting Confirmation"
        case .metadataMode: "Metadata Entry"
        case .hidden: "Hidden QSO"
        }
    }

    /// Explanation for the user
    public var explanation: String {
        switch self {
        case .notYetAttempted:
            "This QSO will be uploaded on the next sync."
        case .missingFields:
            "Add a band or frequency to this QSO before it can be uploaded."
        case .missingParkReference:
            "POTA requires a park reference. Edit the QSO to add one."
        case .invalidParkReference:
            "The park reference was rejected by POTA. Check the format (e.g. US-0001)."
        case .callsignMismatch:
            "This QSO was logged under a different callsign than your primary."
        case .clubStation:
            "Club station QSOs are not uploaded to personal sync accounts."
        case .serviceNotConfigured:
            "Sign in to this service in Settings to enable uploads."
        case .uploadFailed:
            "The last upload attempt failed. Will retry on next sync."
        case .awaitingConfirmation:
            "Submitted to POTA, waiting for job processing to complete."
        case .metadataMode:
            "This is a metadata entry (weather/solar/note), not a QSO."
        case .hidden:
            "This QSO is hidden/deleted and won't be uploaded."
        }
    }

    /// SF Symbol name
    public var iconName: String {
        switch self {
        case .notYetAttempted: "clock"
        case .missingFields: "exclamationmark.triangle"
        case .missingParkReference: "mappin.slash"
        case .invalidParkReference: "xmark.seal"
        case .callsignMismatch: "person.crop.circle.badge.xmark"
        case .clubStation: "building.2"
        case .serviceNotConfigured: "gear.badge.xmark"
        case .uploadFailed: "arrow.triangle.2.circlepath.circle"
        case .awaitingConfirmation: "hourglass"
        case .metadataMode: "doc.badge.gearshape"
        case .hidden: "eye.slash"
        }
    }

    /// Whether the user can take action to fix this
    public var isActionable: Bool {
        switch self {
        case .missingFields,
             .missingParkReference,
             .invalidParkReference,
             .serviceNotConfigured:
            true
        case .notYetAttempted,
             .callsignMismatch,
             .clubStation,
             .uploadFailed,
             .awaitingConfirmation,
             .metadataMode,
             .hidden:
            false
        }
    }

    /// Whether this will auto-resolve without user action
    public var isTransient: Bool {
        switch self {
        case .notYetAttempted,
             .uploadFailed,
             .awaitingConfirmation:
            true
        case .missingFields,
             .missingParkReference,
             .invalidParkReference,
             .callsignMismatch,
             .clubStation,
             .serviceNotConfigured,
             .metadataMode,
             .hidden:
            false
        }
    }

    /// Priority for sorting (lower = more important)
    public var sortPriority: Int {
        switch self {
        case .missingFields: 0
        case .missingParkReference: 1
        case .invalidParkReference: 2
        case .serviceNotConfigured: 3
        case .callsignMismatch: 4
        case .clubStation: 5
        case .metadataMode: 6
        case .hidden: 7
        case .uploadFailed: 8
        case .notYetAttempted: 9
        case .awaitingConfirmation: 10
        }
    }
}
