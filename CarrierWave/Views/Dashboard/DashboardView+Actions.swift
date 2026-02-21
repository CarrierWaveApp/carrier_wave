import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - DashboardView Actions

extension DashboardView {
    func loadQRZConfig() {
        qrzIsConfigured = qrzClient.hasApiKey()
        qrzCallsign = qrzClient.getCallsign()
    }

    /// Refresh service configuration status from Keychain
    /// Called on appear to pick up changes made in settings
    func refreshServiceStatus() {
        lofiIsConfigured = lofiClient.isConfigured
        lofiIsLinked = lofiClient.isLinked
        lofiCallsign = lofiClient.getCallsign()
        hamrsIsConfigured = hamrsClient.isConfigured
        lotwIsConfigured = lotwClient.isConfigured
        clublogIsConfigured = clublogClient.isConfigured
        clublogCallsign = clublogClient.getCallsign()
    }

    func performFullSync() async {
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        do {
            let result = try await syncService.syncAll()
            print("Sync: down=\(result.downloaded), up=\(result.uploaded), new=\(result.newQSOs)")
            if !result.errors.isEmpty {
                print("Sync errors: \(result.errors)")
            }
            // Small delay to ensure SQLite writes are fully committed
            try? await Task.sleep(for: .milliseconds(50))

            // Recompute stats after sync completes
            asyncStats.recompute(from: modelContext)
            presenceCounts.recompute(from: modelContext)
        } catch {
            print("Sync error: \(error.localizedDescription)")
        }
    }

    func performDownloadOnly() async {
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        do {
            let result = try await syncService.downloadOnly()
            let msg =
                "Download-only: down=\(result.downloaded), new=\(result.newQSOs), "
                    + "merged=\(result.mergedQSOs)"
            print(msg)
            if !result.errors.isEmpty {
                print("Download-only sync errors: \(result.errors)")
            }

            // Small delay to ensure SQLite writes are fully committed
            try? await Task.sleep(for: .milliseconds(50))

            // Recompute stats after sync completes
            asyncStats.recompute(from: modelContext)
            presenceCounts.recompute(from: modelContext)
        } catch {
            print("Download-only sync error: \(error.localizedDescription)")
        }
    }

    func syncFromLoFi() async {
        isSyncing = true
        syncingService = .lofi
        defer {
            isSyncing = false
            syncingService = nil
        }

        do {
            _ = try await syncService.syncLoFi()
        } catch {
            syncService.storeErrorReport(service: .lofi, error: error)
        }
    }

    func performQRZSync() async {
        isSyncing = true
        syncingService = .qrz
        defer {
            isSyncing = false
            syncingService = nil
        }

        do {
            _ = try await syncService.syncQRZ()
        } catch {
            syncService.storeErrorReport(service: .qrz, error: error)
        }
    }

    func performPOTASync() async {
        isSyncing = true
        syncingService = .pota
        defer {
            isSyncing = false
            syncingService = nil
        }

        do {
            _ = try await syncService.syncPOTA()
        } catch {
            syncService.storeErrorReport(service: .pota, error: error)
        }
    }

    // MARK: - Force Re-download Methods

    func performQRZForceRedownload() async -> (updated: Int, created: Int) {
        isSyncing = true
        defer {
            isSyncing = false
            asyncStats.recompute(from: modelContext)
            presenceCounts.recompute(from: modelContext)
        }
        do {
            return try await syncService.forceRedownloadFromQRZ()
        } catch {
            syncService.storeErrorReport(service: .qrz, error: error)
            return (updated: 0, created: 0)
        }
    }

    func performPOTAForceRedownload() async -> (updated: Int, created: Int) {
        isSyncing = true
        defer {
            isSyncing = false
            asyncStats.recompute(from: modelContext)
            presenceCounts.recompute(from: modelContext)
        }
        do {
            return try await syncService.forceRedownloadFromPOTA()
        } catch {
            syncService.storeErrorReport(service: .pota, error: error)
            return (updated: 0, created: 0)
        }
    }

    func performLoFiForceRedownload() async -> (updated: Int, created: Int) {
        isSyncing = true
        defer {
            isSyncing = false
            asyncStats.recompute(from: modelContext)
            presenceCounts.recompute(from: modelContext)
        }
        do {
            return try await syncService.forceRedownloadFromLoFi()
        } catch {
            syncService.storeErrorReport(service: .lofi, error: error)
            return (updated: 0, created: 0)
        }
    }

    func performHAMRSForceRedownload() async -> (updated: Int, created: Int) {
        isSyncing = true
        defer {
            isSyncing = false
            asyncStats.recompute(from: modelContext)
            presenceCounts.recompute(from: modelContext)
        }
        do {
            return try await syncService.forceRedownloadFromHAMRS()
        } catch {
            syncService.storeErrorReport(service: .hamrs, error: error)
            return (updated: 0, created: 0)
        }
    }

    func performLoTWForceRedownload() async -> (updated: Int, created: Int) {
        isSyncing = true
        defer {
            isSyncing = false
            asyncStats.recompute(from: modelContext)
            presenceCounts.recompute(from: modelContext)
        }
        do {
            return try await syncService.forceRedownloadFromLoTW()
        } catch {
            syncService.storeErrorReport(service: .lotw, error: error)
            return (updated: 0, created: 0)
        }
    }

    // MARK: - Clear Data Methods

    func clearQRZData() async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let qrzRaw = ImportSource.qrz.rawValue
            let descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate { $0.importSourceRawValue == qrzRaw && !$0.isHidden }
            )
            let qrzQSOs = try modelContext.fetch(descriptor)
            for qso in qrzQSOs {
                qso.isHidden = true
                qso.cloudDirtyFlag = true
                qso.modifiedAt = Date()
            }
            try modelContext.save()
        } catch {
            syncService.storeErrorReport(service: .qrz, error: error)
        }
    }

    func clearLoFiData() async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let lofiRaw = ImportSource.lofi.rawValue
            let descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate { $0.importSourceRawValue == lofiRaw && !$0.isHidden }
            )
            let lofiQSOs = try modelContext.fetch(descriptor)
            for qso in lofiQSOs {
                qso.isHidden = true
                qso.cloudDirtyFlag = true
                qso.modifiedAt = Date()
            }
            try modelContext.save()

            // Reset sync timestamp so QSOs can be re-downloaded
            lofiClient.resetSyncTimestamp()
        } catch {
            syncService.storeErrorReport(service: .lofi, error: error)
        }
    }

    func syncFromHAMRS() async {
        isSyncing = true
        syncingService = .hamrs
        defer {
            isSyncing = false
            syncingService = nil
        }

        do {
            _ = try await syncService.syncHAMRS()
        } catch {
            syncService.storeErrorReport(service: .hamrs, error: error)
        }
    }

    func clearHAMRSCredentials() {
        hamrsClient.clearCredentials()
        refreshServiceStatus()
    }

    func syncFromLoTW() async {
        isSyncing = true
        syncingService = .lotw
        defer {
            isSyncing = false
            syncingService = nil
        }

        do {
            _ = try await syncService.syncLoTW()
        } catch {
            syncService.storeErrorReport(service: .lotw, error: error)
        }
    }

    func clearLoTWData() {
        isSyncing = true
        defer { isSyncing = false }

        // Clear LoTW timestamps to allow re-download
        lotwClient.clearCredentials()
        refreshServiceStatus()
    }

    func syncFromClubLog() async {
        isSyncing = true
        syncingService = .clublog
        defer {
            isSyncing = false
            syncingService = nil
        }

        do {
            _ = try await syncService.syncClubLog()
        } catch {
            syncService.storeErrorReport(service: .clublog, error: error)
        }
    }

    func performClubLogForceRedownload() async -> (updated: Int, created: Int) {
        isSyncing = true
        defer {
            isSyncing = false
            asyncStats.recompute(from: modelContext)
            presenceCounts.recompute(from: modelContext)
        }
        do {
            let result = try await syncService.syncClubLog(forceFullSync: true)
            return (updated: 0, created: result.downloaded)
        } catch {
            syncService.storeErrorReport(service: .clublog, error: error)
            return (updated: 0, created: 0)
        }
    }

    func clearClubLogData() {
        clublogClient.logout()
        refreshServiceStatus()
    }

    // MARK: - Callsign Alias Detection

    /// Check for callsigns in QSOs that aren't configured as user callsigns
    func checkForUnconfiguredCallsigns() async {
        // Get all unique MYCALLSIGN values from async stats (computed in background)
        let allMyCallsigns = asyncStats.uniqueMyCallsigns

        // Skip check if no QSOs with callsigns (stats may still be computing)
        guard !allMyCallsigns.isEmpty else {
            return
        }

        // Get unconfigured callsigns
        let unconfigured = aliasService.getUnconfiguredCallsigns(from: allMyCallsigns)

        // Only show alert if there are unconfigured callsigns AND user has at least one configured
        let hasConfiguredCallsigns = !aliasService.getAllUserCallsigns().isEmpty
        if !unconfigured.isEmpty, hasConfiguredCallsigns {
            unconfiguredCallsigns = unconfigured
            showingCallsignAliasAlert = true
        }
    }

    /// Add all unconfigured callsigns as previous callsigns
    func addUnconfiguredCallsignsAsAliases() async {
        for callsign in unconfiguredCallsigns {
            do {
                try aliasService.addPreviousCallsign(callsign)
            } catch {
                print("Failed to add callsign alias \(callsign): \(error)")
            }
        }
        unconfiguredCallsigns = []
    }

    // MARK: - POTA Presence Repair

    /// Check for QSOs incorrectly marked for POTA upload (no park reference but needsUpload=true)
    /// Runs on background thread via actor.
    func checkForMismarkedPOTAPresence() async {
        let repairService = POTAPresenceRepairService(container: modelContext.container)
        do {
            let count = try await repairService.countMismarkedQSOs()
            if count > 0 {
                mismarkedPOTACount = count
                showingPOTARepairAlert = true
            }
        } catch {
            print("Failed to check for mismarked POTA presence: \(error)")
        }
    }

    /// Repair incorrectly marked POTA service presence records
    /// Runs on background thread via actor.
    func repairMismarkedPOTAPresence() async {
        let repairService = POTAPresenceRepairService(container: modelContext.container)
        do {
            let result = try await repairService.repairMismarkedQSOs()
            print("Repaired \(result.repairedCount) mismarked POTA presence records")
            mismarkedPOTACount = 0
        } catch {
            print("Failed to repair mismarked POTA presence: \(error)")
        }
    }

    // MARK: - Two-fer Duplicate Repair

    /// Check for duplicate QSOs from two-fer park reference mismatches
    /// Runs on background thread via actor.
    func checkForTwoferDuplicates() async {
        let repairService = TwoferDuplicateRepairService(container: modelContext.container)
        do {
            let count = try await repairService.countDuplicates()
            if count > 0 {
                twoferDuplicateCount = count
                showingTwoferRepairAlert = true
            }
        } catch {
            print("Failed to check for two-fer duplicates: \(error)")
        }
    }

    /// Repair duplicate QSOs by merging truncated versions into complete versions
    /// Runs on background thread via actor.
    func repairTwoferDuplicates() async {
        let repairService = TwoferDuplicateRepairService(container: modelContext.container)
        do {
            let result = try await repairService.repairDuplicates()
            print(
                "Repaired \(result.qsosMerged) duplicate groups, removed \(result.qsosRemoved) QSOs"
            )
            twoferDuplicateCount = 0
        } catch {
            print("Failed to repair two-fer duplicates: \(error)")
        }
    }
}

// Backfill and repair methods are in DashboardView+Repairs.swift
