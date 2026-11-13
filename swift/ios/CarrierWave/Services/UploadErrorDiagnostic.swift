import CarrierWaveCore
import Foundation

// MARK: - UploadErrorCategory

/// Categories of upload errors, ordered by user-action priority.
enum UploadErrorCategory: String, Codable, CaseIterable {
    /// Bad or expired credentials — user must re-authenticate
    case authentication
    /// QSO data issues (missing fields, bad park reference)
    case validation
    /// Service requires a paid subscription
    case subscriptionRequired
    /// Upload permanently rejected by service
    case rejected
    /// Service is in scheduled maintenance
    case maintenance
    /// Too many requests — temporary throttle
    case rateLimited
    /// Network timeout or slow connection
    case networkTimeout
    /// Device is offline
    case networkOffline
    /// Remote service returned a server error (5xx)
    case serverError

    // MARK: Internal

    /// Human-readable title for grouping in UI
    var title: String {
        switch self {
        case .authentication: "Authentication"
        case .validation: "Invalid Data"
        case .subscriptionRequired: "Subscription Required"
        case .rejected: "Permanently Rejected"
        case .maintenance: "Service Maintenance"
        case .rateLimited: "Rate Limited"
        case .networkTimeout: "Network Timeout"
        case .networkOffline: "No Internet"
        case .serverError: "Server Error"
        }
    }

    /// SF Symbol name for this category
    var iconName: String {
        switch self {
        case .authentication: "key.slash"
        case .validation: "exclamationmark.triangle"
        case .subscriptionRequired: "creditcard"
        case .rejected: "xmark.seal"
        case .maintenance: "wrench.and.screwdriver"
        case .rateLimited: "gauge.with.dots.needle.33percent"
        case .networkTimeout: "clock.badge.exclamationmark"
        case .networkOffline: "wifi.slash"
        case .serverError: "server.rack"
        }
    }

    /// Whether errors in this category will resolve without user action
    var isTransient: Bool {
        switch self {
        case .maintenance,
             .rateLimited,
             .networkTimeout,
             .networkOffline,
             .serverError:
            true
        case .authentication,
             .validation,
             .subscriptionRequired,
             .rejected:
            false
        }
    }
}

// MARK: - UploadErrorDiagnostic

/// A classified upload error with user-facing guidance.
/// Ephemeral — stored in UserDefaults, not SwiftData.
struct UploadErrorDiagnostic: Codable, Equatable, Identifiable {
    // MARK: Lifecycle

    init(
        category: UploadErrorCategory,
        service: ServiceType,
        message: String,
        guidance: String,
        affectedCount: Int,
        timestamp: Date = Date()
    ) {
        id = UUID()
        self.category = category
        self.service = service
        self.message = message
        self.guidance = guidance
        self.affectedCount = affectedCount
        self.timestamp = timestamp
    }

    // MARK: Internal

    /// Stable identity for SwiftUI lists
    let id: UUID
    /// Error classification
    let category: UploadErrorCategory
    /// Which service failed
    let service: ServiceType
    /// Technical error detail (from the error itself)
    let message: String
    /// User-facing guidance on how to fix
    let guidance: String
    /// How many QSOs were affected by this error
    let affectedCount: Int
    /// When this error occurred
    let timestamp: Date
}
