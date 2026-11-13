// FCC ULS Callsign Database Service
//
// Thin façade over the Rust reference-data core (`ReferenceDataApi`), which
// owns the FCC bundle end to end: metadata sidecar fetch, SHA-256
// short-circuit (no re-download when unchanged), gzip decompression, atomic
// file swap, and read-only lookups. Refreshes weekly.

import CarrierWaveData
import UIKit

// MARK: - FCCCallsignRecord

/// A record from the FCC callsign database.
struct FCCCallsignRecord {
    let callsign: String
    let firstName: String?
    let lastName: String?
    let city: String?
    let state: String?
    let grid: String?
    let operatorClass: String?

    var fullName: String? {
        switch (firstName, lastName) {
        case let (first?, last?):
            "\(first) \(last)"
        case let (nil, last?):
            last
        case let (first?, nil):
            first
        case (nil, nil):
            nil
        }
    }
}

// MARK: - FCCLookupService

/// Queries and refreshes the FCC amateur radio callsign database for fast
/// offline lookups. Download, verification, and storage live in the Rust
/// core; this actor only tracks refresh state for the Settings UI.
actor FCCLookupService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = FCCLookupService()

    /// Whether a download is in progress.
    private(set) var isDownloading = false

    /// Last error from download attempt, if any.
    private(set) var lastError: String?

    /// When the database was last refreshed (or confirmed fresh).
    var lastUpdated: Date? {
        get async {
            guard let fetchedAt = await fccStatus()?.fetchedAt else {
                return nil
            }
            return Date(timeIntervalSince1970: TimeInterval(fetchedAt))
        }
    }

    /// Number of records in the database.
    var recordCount: Int {
        get async {
            guard let status = await fccStatus() else {
                return 0
            }
            return Int(status.count)
        }
    }

    /// Look up a callsign in the FCC database. Returns nil when the
    /// database has not been downloaded or the callsign is unknown.
    func lookup(_ callsign: String) async -> FCCCallsignRecord? {
        guard let api = try? await preparedApi(),
              let record = try? api.fccLookup(callsign: callsign.uppercased())
        else {
            return nil
        }
        return FCCCallsignRecord(
            callsign: record.callsign,
            firstName: record.firstName,
            lastName: record.lastName,
            city: record.city,
            state: record.state,
            grid: record.grid,
            operatorClass: record.operatorClass
        )
    }

    /// Prepare the core for queries (no download). Seeds the Rust
    /// bookkeeping from a pre-Rust Swift download on first call so the
    /// next refresh short-circuits. Call at app startup.
    func loadIfNeeded() async {
        _ = try? await preparedApi()
    }

    /// Download or update the database if stale (7-day TTL). Triggered
    /// from Settings.
    func downloadOrUpdate() async {
        await refresh(force: false)
    }

    /// Force a fresh metadata check regardless of cache age. The core
    /// still skips the download when the remote SHA-256 is unchanged.
    func forceRefresh() async {
        await refresh(force: true)
    }

    // MARK: Private

    /// Whether the legacy Swift sidecar has been offered to the core this
    /// launch (seeding is a no-op once the Rust state exists).
    private var hasSeededLegacyState = false

    /// The shared reference-data API with legacy migration applied.
    private func preparedApi() async throws -> ReferenceDataApi {
        let api = try await ReferenceData.api()
        seedLegacyStateIfNeeded(api)
        return api
    }

    /// MIGRATION: hand the SHA-256 from the old Swift service's sidecar
    /// (`amateur-callsigns.json`) to the core so `refreshFcc` short-circuits
    /// instead of re-downloading hundreds of MB. The sidecar is left in
    /// place (harmless) but never written again. The record count is
    /// unknown to the sidecar, so 0 is seeded — the next metadata check
    /// corrects it.
    private func seedLegacyStateIfNeeded(_ api: ReferenceDataApi) {
        guard !hasSeededLegacyState else {
            return
        }
        hasSeededLegacyState = true

        let sidecarURL = ReferenceData.fccDirectory
            .appendingPathComponent("amateur-callsigns.json")
        guard let data = try? Data(contentsOf: sidecarURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha256 = json["sha256"] as? String
        else {
            return
        }
        try? api.seedFccState(sha256: sha256, recordCount: 0)
    }

    private func refresh(force: Bool) async {
        guard !isDownloading else {
            return
        }
        isDownloading = true
        defer { isDownloading = false }

        lastError = nil
        do {
            let api = try await preparedApi()
            _ = try await api.refreshFcc(force: force)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fccStatus() async -> FfiDatasetStatus? {
        guard let api = try? await preparedApi() else {
            return nil
        }
        return try? api.status().fccCallsigns
    }
}
