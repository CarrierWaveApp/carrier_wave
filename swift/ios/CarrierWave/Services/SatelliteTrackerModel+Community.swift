import CarrierWaveCore
import UIKit

// MARK: - SatelliteTrackerModel + Community activity

extension SatelliteTrackerModel {
    /// The AMSAT community-activity grid, enriched by the engine (catalog
    /// identity + SatNOGS transmitter, next pass over the observer, own
    /// QSOs). Cache-through on the server histogram (20 min TTL, stale
    /// fallback offline); `cellSeconds` ≥ 3600 merges hourly buckets into
    /// coarser cells. Requires a loaded catalog.
    func communityActivity(
        force: Bool = false,
        cellSeconds: Int
    ) async throws -> CommunityActivity {
        let api = try await SatelliteEngine.api()
        let ffi = try await api.communityActivity(
            force: force,
            observer: ffiObserver(),
            nowEpoch: simulatedEpoch(),
            cellSecs: Int64(cellSeconds)
        )
        return CommunityActivity(ffi: ffi)
    }

    /// The selected bird's community reports (reporter grids for the map,
    /// previous-orbit line for the info card). Soft: failure leaves the
    /// previous value, and a stale selection's result is dropped.
    func loadReports(for noradID: Int, force: Bool = false) async {
        guard let api = try? await SatelliteEngine.api() else {
            return
        }
        if communityActivity == nil || force {
            communityActivity = try? await communityActivity(force: force, cellSeconds: 3 * 3_600)
        }
        let ffi = try? await api.communityReports(
            noradId: UInt32(noradID),
            force: force,
            nowEpoch: simulatedEpoch()
        )
        guard let ffi, selectedNoradID == noradID else {
            return
        }
        selectedReports = CommunityReports(ffi: ffi)
    }

    /// File the operator's own observation with AMSAT (status.amsat.org).
    /// Only from an explicit tap: AMSAT's guidelines forbid background or
    /// automated submissions, and the report must carry the operator's
    /// callsign and the time they heard (or didn't hear) the bird. The
    /// engine validates and normalises; AMSAT's own rejection reason comes
    /// back as the error message.
    func submitCommunityReport(
        amsatName: String,
        report: String,
        callsign: String,
        grid: String?,
        at reportedAt: Date
    ) async throws -> CommunityReportReceipt {
        let api = try await SatelliteEngine.api()
        let ffi = try await api.submitCommunityReport(
            submission: FfiCommunityReportSubmission(
                amsatName: amsatName,
                report: report,
                callsign: callsign,
                grid: grid,
                reportedAtEpoch: Int64(reportedAt.timeIntervalSince1970)
            )
        )
        return CommunityReportReceipt(ffi: ffi)
    }
}
