import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - QRZ callbook lookup (shared Rust FFI)

extension CallsignLookupService {
    /// Shared QRZ callbook client over the Rust `QrzApi`. One instance keeps a
    /// single in-memory QRZ session alive across lookups (incl. grid batch repair).
    static let qrzCallbook = QrzCallbookClient()

    /// Look up a callsign in the QRZ XML callbook.
    func lookupInQRZ(_ callsign: String) async -> CallsignInfo? {
        await lookupInQRZWithResult(callsign).info
    }

    /// Look up a callsign in QRZ with detailed result/error information.
    func lookupInQRZWithResult(_ callsign: String) async -> CallsignLookupResult {
        do {
            guard let lookup = try await Self.qrzCallbook.lookup(callsign) else {
                return .notFound(qrzAttempted: true, poloNotesChecked: true)
            }
            return .fromQRZ(callsignInfo(from: lookup, queried: callsign))
        } catch QrzCallbookError.noCredentials {
            return .error(.noQRZApiKey)
        } catch {
            return .error(Self.lookupError(from: error), qrzAttempted: true)
        }
    }

    // MARK: - Mapping

    /// Project an `FfiQrzLookup` onto the app's `CallsignInfo`. The redirect note
    /// ("Looked up as …") isn't carried by the FFI result, so it's reconstructed
    /// here from the queried vs. canonical callsign — matching the old behaviour.
    func callsignInfo(from lookup: FfiQrzLookup, queried: String) -> CallsignInfo {
        let canonical = lookup.callsign.uppercased()
        let isRedirected = canonical != queried.uppercased()
        return CallsignInfo(
            callsign: canonical,
            name: lookup.name,
            firstName: lookup.firstName,
            nickname: lookup.nickname,
            qth: lookup.qth,
            state: lookup.state,
            country: lookup.country,
            grid: lookup.grid,
            licenseClass: lookup.licenseClass,
            previousCallsign: lookup.previousCallsign,
            source: .qrz,
            callsignChangeNote: isRedirected ? "Looked up as \(queried.uppercased())" : nil
        )
    }

    /// Map a thrown `CwError` from the FFI onto a `CallsignLookupError`.
    private static func lookupError(from error: Error) -> CallsignLookupError {
        switch error {
        case CwError.Auth:
            .qrzAuthFailed
        case let CwError.Network(reason):
            .networkError(reason)
        case let CwError.Query(reason),
             let CwError.Store(reason):
            .networkError(reason)
        default:
            .networkError(error.localizedDescription)
        }
    }
}
