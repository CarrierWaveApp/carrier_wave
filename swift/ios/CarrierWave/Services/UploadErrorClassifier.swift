import CarrierWaveCore
import Foundation

// MARK: - UploadErrorClassifier

/// Maps service-specific errors to user-facing diagnostics with actionable guidance.
enum UploadErrorClassifier {
    // MARK: Internal

    /// Classify an upload error into a diagnostic with guidance text.
    static func classify(
        error: Error,
        service: ServiceType,
        affectedCount: Int
    ) -> UploadErrorDiagnostic {
        let (category, guidance) = categorize(error: error, service: service)
        return UploadErrorDiagnostic(
            category: category,
            service: service,
            message: error.localizedDescription,
            guidance: guidance,
            affectedCount: affectedCount
        )
    }

    /// Classify a validation issue (not an Error, just missing fields).
    static func validationDiagnostic(
        service: ServiceType,
        message: String,
        guidance: String,
        affectedCount: Int
    ) -> UploadErrorDiagnostic {
        UploadErrorDiagnostic(
            category: .validation,
            service: service,
            message: message,
            guidance: guidance,
            affectedCount: affectedCount
        )
    }

    // MARK: Private

    private static func categorize(
        error: Error,
        service: ServiceType
    ) -> (UploadErrorCategory, String) {
        // Check for timeout first (wraps all services)
        if error is SyncTimeoutError {
            return (.networkTimeout, "Sync timed out. Will retry on next sync.")
        }

        // Check for URLError (network-level failures)
        if let urlError = error as? URLError {
            return classifyURLError(urlError)
        }

        // Service-specific classification
        switch service {
        case .qrz:
            return classifyQRZError(error)
        case .pota:
            return classifyPOTAError(error)
        case .clublog:
            return classifyClubLogError(error)
        case .eqsl:
            return classifyEQSLError(error)
        case .lotw:
            return classifyLoTWError(error)
        case .hamrs:
            return classifyHAMRSError(error)
        case .lofi:
            return classifyLoFiError(error)
        }
    }

    private static func classifyURLError(
        _ error: URLError
    ) -> (UploadErrorCategory, String) {
        switch error.code {
        case .notConnectedToInternet,
             .dataNotAllowed:
            (.networkOffline, "No internet connection. Will retry when you're back online.")
        case .timedOut:
            (.networkTimeout, "Connection timed out. Will retry on next sync.")
        case .networkConnectionLost:
            (.networkTimeout, "Connection was lost. Will retry on next sync.")
        case .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed:
            (.serverError, "Could not reach server. The service may be down.")
        default:
            (.networkTimeout, "Network error. Will retry on next sync.")
        }
    }

    private static func classifyQRZError(
        _ error: Error
    ) -> (UploadErrorCategory, String) {
        guard let qrzError = error as? QRZError else {
            return classifyGenericError(error)
        }
        switch qrzError {
        case .invalidApiKey:
            return (.authentication, "Your QRZ API key is invalid. Update it in Settings → QRZ.")
        case .subscriptionRequired:
            return (
                .subscriptionRequired,
                "QRZ requires an XML Logbook Data subscription to upload. "
                    + "Check your QRZ account at qrz.com."
            )
        case .sessionExpired:
            return (.authentication, "QRZ session expired. Will re-authenticate on next sync.")
        case .uploadFailed:
            return (.serverError, "QRZ rejected the upload. Check the sync debug log for details.")
        case let .networkError(wrapped):
            if let urlError = wrapped as? URLError {
                return classifyURLError(urlError)
            }
            return (.networkTimeout, "Network error reaching QRZ. Will retry on next sync.")
        case .invalidResponse:
            return (.serverError, "QRZ returned an unexpected response. Will retry on next sync.")
        case .fetchFailed,
             .noQSOs:
            return (.serverError, "QRZ returned an error. Will retry on next sync.")
        }
    }

    private static func classifyPOTAError(
        _ error: Error
    ) -> (UploadErrorCategory, String) {
        guard let potaError = error as? POTAError else {
            return classifyGenericError(error)
        }
        switch potaError {
        case .notAuthenticated:
            return (.authentication, "POTA login expired. Sign in again in Settings → POTA.")
        case .invalidParkReference:
            return (
                .validation,
                "One or more QSOs have an invalid park reference format. "
                    + "If you see upload errors, please reach out on the Carrier Wave "
                    + "Discord before contacting POTA directly."
            )
        case .maintenanceWindow:
            return (.maintenance, "POTA is in daily maintenance (0000–0400 UTC). Will retry after.")
        case .uploadFailed:
            return (
                .serverError,
                "POTA rejected the upload. Check the sync debug log for details. "
                    + "If you see upload errors, please reach out on the Carrier Wave "
                    + "Discord before contacting POTA directly."
            )
        case let .networkError(wrapped):
            if let urlError = wrapped as? URLError {
                return classifyURLError(urlError)
            }
            return (.networkTimeout, "Network error reaching POTA. Will retry on next sync.")
        case .fetchFailed:
            return (.serverError, "POTA returned an error. Will retry on next sync.")
        }
    }

    private static func classifyClubLogError(
        _ error: Error
    ) -> (UploadErrorCategory, String) {
        guard let clError = error as? ClubLogError else {
            return classifyGenericError(error)
        }
        switch clError {
        case .authenticationFailed:
            return (.authentication, "Club Log login failed. Check credentials in Settings → Club Log.")
        case .forbidden:
            return (
                .authentication,
                "Club Log rejected your request (403). "
                    + "This may be their IP firewall — try again later."
            )
        case .uploadRejected:
            return (.rejected, "Club Log permanently rejected these QSOs. Check data in debug log.")
        case .uploadFailed:
            return (.serverError, "Club Log upload failed. Will retry on next sync.")
        case .notConfigured:
            return (.authentication, "Club Log is not configured. Set it up in Settings → Club Log.")
        case .serverError:
            return (.serverError, "Club Log returned a server error. Will retry on next sync.")
        case let .networkError(wrapped):
            if let urlError = wrapped as? URLError {
                return classifyURLError(urlError)
            }
            return (.networkTimeout, "Network error reaching Club Log. Will retry on next sync.")
        case .fetchFailed,
             .invalidResponse:
            return (.serverError, "Club Log returned an error. Will retry on next sync.")
        }
    }

    private static func classifyEQSLError(
        _ error: Error
    ) -> (UploadErrorCategory, String) {
        guard let eqslError = error as? EQSLError else {
            return classifyGenericError(error)
        }
        switch eqslError {
        case .authenticationFailed:
            return (.authentication, "eQSL login failed. Check credentials in Settings → eQSL.")
        case .uploadRejected:
            return (.rejected, "eQSL permanently rejected these QSOs. Check data in debug log.")
        case .uploadFailed:
            return (.serverError, "eQSL upload failed. Will retry on next sync.")
        case .notConfigured:
            return (.authentication, "eQSL is not configured. Set it up in Settings → eQSL.")
        case let .networkError(wrapped):
            if let urlError = wrapped as? URLError {
                return classifyURLError(urlError)
            }
            return (.networkTimeout, "Network error reaching eQSL. Will retry on next sync.")
        case .fetchFailed,
             .invalidResponse:
            return (.serverError, "eQSL returned an error. Will retry on next sync.")
        }
    }

    private static func classifyLoTWError(
        _ error: Error
    ) -> (UploadErrorCategory, String) {
        guard let lotwError = error as? LoTWError else {
            return classifyGenericError(error)
        }
        switch lotwError {
        case .authenticationFailed:
            return (.authentication, "LoTW login failed. Check your credentials in Settings → LoTW.")
        case .noCredentials:
            return (.authentication, "LoTW credentials not set. Configure in Settings → LoTW.")
        case .serviceError:
            return (.serverError, "LoTW returned an error. Will retry on next sync.")
        case .invalidResponse:
            return (.serverError, "LoTW returned an unexpected response. Will retry on next sync.")
        }
    }

    private static func classifyHAMRSError(
        _ error: Error
    ) -> (UploadErrorCategory, String) {
        guard let hamrsError = error as? HAMRSError else {
            return classifyGenericError(error)
        }
        switch hamrsError {
        case .notConfigured:
            return (.authentication, "HAMRS is not configured. Set it up in Settings.")
        case .invalidApiKey:
            return (.authentication, "HAMRS API key is invalid. Update it in Settings.")
        case .subscriptionInactive:
            return (.subscriptionRequired, "HAMRS subscription is inactive. Check your account.")
        case let .networkError(wrapped):
            if let urlError = wrapped as? URLError {
                return classifyURLError(urlError)
            }
            return (.networkTimeout, "Network error reaching HAMRS. Will retry on next sync.")
        case .invalidResponse,
             .decodingError,
             .invalidCouchDBURL:
            return (.serverError, "HAMRS returned an error. Will retry on next sync.")
        }
    }

    private static func classifyLoFiError(
        _ error: Error
    ) -> (UploadErrorCategory, String) {
        guard let lofiError = error as? LoFiError else {
            return classifyGenericError(error)
        }
        switch lofiError {
        case .notConfigured:
            return (.authentication, "LoFi is not configured. Set up your callsign in Settings.")
        case .notLinked:
            return (.authentication, "LoFi account not linked. Link it in Settings → LoFi.")
        case .registrationFailed:
            return (.authentication, "LoFi registration failed. Try re-linking in Settings → LoFi.")
        case .authenticationRequired:
            return (.authentication, "LoFi authentication required. Re-link in Settings → LoFi.")
        case let .networkError(wrapped):
            if let urlError = wrapped as? URLError {
                return classifyURLError(urlError)
            }
            return (.networkTimeout, "Network error reaching LoFi. Will retry on next sync.")
        case .invalidResponse:
            return (.serverError, "LoFi returned an unexpected response. Will retry on next sync.")
        case .apiError:
            return (.serverError, "LoFi returned an error. Will retry on next sync.")
        }
    }

    private static func classifyGenericError(
        _ error: Error
    ) -> (UploadErrorCategory, String) {
        // Unwrap network errors from any wrapper
        if let urlError = (error as NSError).underlyingErrors.compactMap({ $0 as? URLError }).first {
            return classifyURLError(urlError)
        }
        return (.serverError, "An unexpected error occurred. Will retry on next sync.")
    }
}
