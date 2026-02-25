import CarrierWaveCore
import SwiftUI

// MARK: - DashboardView Services List

extension DashboardView {
    /// Derived counts from ServicePresence (computed in background)
    func uploadedCount(for service: ServiceType) -> Int {
        presenceCounts.uploadedCount(for: service)
    }

    func pendingCount(for service: ServiceType) -> Int {
        presenceCounts.pendingCount(for: service)
    }

    // MARK: - Services List View

    var servicesList: some View {
        ServiceListView(
            services: buildServiceInfoList(),
            serviceSyncStates: syncService.serviceSyncStates,
            onServiceTap: { serviceId in
                selectedService = serviceId
            }
        )
    }

    // MARK: - Build Service Info List

    func buildServiceInfoList() -> [ServiceInfo] {
        let canBypass = debugMode && bypassPOTAMaintenance
        let potaInMaintenance = POTAClient.isInMaintenanceWindow() && !canBypass

        let allServices = [
            lofiServiceInfo,
            qrzServiceInfo,
            potaServiceInfo(inMaintenance: potaInMaintenance),
            hamrsServiceInfo,
            lotwServiceInfo,
            clublogServiceInfo,
            icloudServiceInfo,
        ]

        // Only show configured services on the dashboard
        return allServices.filter { $0.status != .notConfigured }
    }

    // MARK: - Individual Service Info Builders

    private var lofiServiceInfo: ServiceInfo {
        ServiceInfo(
            id: .service(.lofi),
            name: "Ham2K LoFi",
            status: lofiStatus,
            primaryStat: lofiIsConfigured && lofiIsLinked
                ? "\(uploadedCount(for: .lofi)) synced" : nil,
            secondaryStat: nil,
            tertiaryInfo: lofiStatusText ?? syncService.lastSyncResults[.lofi]?.summaryText,
            showWarning: false,
            isSyncing: syncService.isSyncing
        )
    }

    private var qrzServiceInfo: ServiceInfo {
        ServiceInfo(
            id: .service(.qrz),
            name: "QRZ Logbook",
            status: qrzIsConfigured ? .connected : .notConfigured,
            primaryStat: qrzIsConfigured ? "\(uploadedCount(for: .qrz)) synced" : nil,
            secondaryStat: qrzIsConfigured ? "\(asyncStats.qrzConfirmedCount) QSLs" : nil,
            tertiaryInfo: qrzIsConfigured
                ? syncService.lastSyncResults[.qrz]?.summaryText : "Not configured",
            showWarning: pendingCount(for: .qrz) > 0,
            isSyncing: syncService.isSyncing
        )
    }

    private func potaServiceInfo(inMaintenance: Bool) -> ServiceInfo {
        ServiceInfo(
            id: .service(.pota),
            name: "POTA",
            status: potaStatus(inMaintenance: inMaintenance),
            primaryStat: potaAuth.isConfigured ? "\(uploadedCount(for: .pota)) synced" : nil,
            secondaryStat: pendingCount(for: .pota) > 0
                ? "\(pendingCount(for: .pota)) pending" : nil,
            tertiaryInfo: potaAuth.isConfigured
                ? syncService.lastSyncResults[.pota]?.summaryText : "Not configured",
            showWarning: inMaintenance || potaAuth.currentToken?.isExpiringSoon() == true,
            isSyncing: syncService.isSyncing
        )
    }

    private var hamrsServiceInfo: ServiceInfo {
        ServiceInfo(
            id: .service(.hamrs),
            name: "HAMRS",
            status: hamrsIsConfigured ? .connected : .notConfigured,
            primaryStat: hamrsIsConfigured ? "\(uploadedCount(for: .hamrs)) synced" : nil,
            secondaryStat: nil,
            tertiaryInfo: hamrsIsConfigured
                ? syncService.lastSyncResults[.hamrs]?.summaryText : "Not configured",
            showWarning: false,
            isSyncing: syncService.isSyncing
        )
    }

    private var lotwServiceInfo: ServiceInfo {
        ServiceInfo(
            id: .service(.lotw),
            name: "LoTW",
            status: lotwIsConfigured ? .connected : .notConfigured,
            primaryStat: lotwIsConfigured ? "\(uploadedCount(for: .lotw)) synced" : nil,
            secondaryStat: lotwIsConfigured ? "\(asyncStats.lotwConfirmedCount) QSLs" : nil,
            tertiaryInfo: lotwIsConfigured
                ? syncService.lastSyncResults[.lotw]?.summaryText : "Not configured",
            showWarning: false,
            isSyncing: syncService.isSyncing
        )
    }

    private var clublogServiceInfo: ServiceInfo {
        ServiceInfo(
            id: .service(.clublog),
            name: "Club Log",
            status: clublogIsConfigured ? .connected : .notConfigured,
            primaryStat: clublogIsConfigured
                ? "\(uploadedCount(for: .clublog)) synced" : nil,
            secondaryStat: pendingCount(for: .clublog) > 0
                ? "\(pendingCount(for: .clublog)) pending" : nil,
            tertiaryInfo: clublogIsConfigured
                ? syncService.lastSyncResults[.clublog]?.summaryText : "Not configured",
            showWarning: pendingCount(for: .clublog) > 0,
            isSyncing: syncService.isSyncing
        )
    }

    private var icloudServiceInfo: ServiceInfo {
        let cloudSync = CloudSyncService.shared
        let hasFolder = iCloudMonitor.iCloudContainerURL != nil
        let syncEnabled = cloudSync.isEnabled

        let status: ServiceStatus = if syncEnabled {
            .connected
        } else if hasFolder {
            .connected
        } else {
            .notConfigured
        }

        let primaryStat: String? = if syncEnabled {
            cloudSync.syncStatus.displayText
        } else if hasFolder {
            "\(asyncStats.icloudImportedCount) imported"
        } else {
            nil
        }

        let secondaryStat: String? = if cloudSync.pendingCount > 0 {
            "\(cloudSync.pendingCount) pending"
        } else if !iCloudMonitor.pendingFiles.isEmpty {
            "\(iCloudMonitor.pendingFiles.count) files pending"
        } else {
            nil
        }

        return ServiceInfo(
            id: .icloud,
            name: "iCloud",
            status: status,
            primaryStat: primaryStat,
            secondaryStat: secondaryStat,
            tertiaryInfo: status == .notConfigured ? "Not configured" : nil,
            showWarning: cloudSync.syncStatus.isError || !iCloudMonitor.pendingFiles.isEmpty,
            isSyncing: cloudSync.isSyncing
        )
    }

    // MARK: - Status Helpers

    var lofiStatus: ServiceStatus {
        if lofiIsConfigured, lofiIsLinked {
            return .connected
        } else if lofiIsConfigured {
            return .pending
        }
        return .notConfigured
    }

    var lofiStatusText: String? {
        if lofiIsConfigured, lofiIsLinked {
            return nil
        } else if lofiIsConfigured {
            return "Pending"
        }
        return "Not configured"
    }

    func potaStatus(inMaintenance: Bool) -> ServiceStatus {
        if inMaintenance {
            return .maintenance
        }
        // Use isConfigured (has stored credentials) for status
        // This shows "connected" even if token expired - will re-auth on sync
        return potaAuth.isConfigured ? .connected : .notConfigured
    }

    // MARK: - Service Detail Sheet Builder

    @ViewBuilder
    func serviceDetailSheet(for serviceId: ServiceIdentifier) -> some View {
        switch serviceId {
        case let .service(serviceType):
            switch serviceType {
            case .lofi:
                lofiDetailSheet
            case .qrz:
                qrzDetailSheet
            case .pota:
                potaDetailSheet
            case .hamrs:
                hamrsDetailSheet
            case .lotw:
                lotwDetailSheet
            case .clublog:
                clublogDetailSheet
            }
        case .icloud:
            icloudDetailSheet
        }
    }

    // MARK: - Detail Sheets

    var lofiDetailSheet: some View {
        ServiceDetailSheet(
            serviceId: .service(.lofi),
            isConfigured: lofiIsConfigured && lofiIsLinked,
            callsign: lofiCallsign,
            syncedCount: uploadedCount(for: .lofi),
            pendingCount: pendingCount(for: .lofi),
            confirmedCount: nil,
            lastSyncReport: syncService.lastSyncResults[.lofi],
            isSyncing: isSyncing,
            debugMode: debugMode,
            isInMaintenance: false,
            sessionExpiringSoon: false,
            sessionExpiryDate: nil,
            importedCount: nil,
            pendingFiles: nil,
            isMonitoring: nil,
            onSync: { await syncFromLoFi() },
            onForceRedownload: { await performLoFiForceRedownload() },
            onClearData: { await clearLoFiData() },
            onConfigure: {
                selectedService = nil
                settingsDestination = .lofi
                selectedTab = .more
            }
        )
    }

    var qrzDetailSheet: some View {
        ServiceDetailSheet(
            serviceId: .service(.qrz),
            isConfigured: qrzIsConfigured,
            callsign: qrzCallsign,
            syncedCount: uploadedCount(for: .qrz),
            pendingCount: pendingCount(for: .qrz),
            confirmedCount: asyncStats.qrzConfirmedCount,
            lastSyncReport: syncService.lastSyncResults[.qrz],
            isSyncing: isSyncing,
            debugMode: debugMode,
            isInMaintenance: false,
            sessionExpiringSoon: false,
            sessionExpiryDate: nil,
            importedCount: nil,
            pendingFiles: nil,
            isMonitoring: nil,
            onSync: { await performQRZSync() },
            onForceRedownload: { await performQRZForceRedownload() },
            onClearData: { await clearQRZData() },
            onConfigure: {
                selectedService = nil
                settingsDestination = .qrz
                selectedTab = .more
            }
        )
    }

    var potaDetailSheet: some View {
        let canBypass = debugMode && bypassPOTAMaintenance
        let inMaintenance = POTAClient.isInMaintenanceWindow() && !canBypass

        return ServiceDetailSheet(
            serviceId: .service(.pota),
            isConfigured: potaAuth.isConfigured,
            callsign: potaAuth.currentToken?.callsign ?? potaAuth.getStoredUsername(),
            syncedCount: uploadedCount(for: .pota),
            pendingCount: pendingCount(for: .pota),
            confirmedCount: nil,
            lastSyncReport: syncService.lastSyncResults[.pota],
            isSyncing: isSyncing,
            debugMode: debugMode,
            isInMaintenance: inMaintenance,
            sessionExpiringSoon: potaAuth.currentToken?.isExpiringSoon() ?? false,
            sessionExpiryDate: potaAuth.currentToken?.expiresAt,
            importedCount: nil,
            pendingFiles: nil,
            isMonitoring: nil,
            onSync: { await performPOTASync() },
            onForceRedownload: { await performPOTAForceRedownload() },
            onClearData: nil,
            onConfigure: {
                selectedService = nil
                settingsDestination = .pota
                selectedTab = .more
            }
        )
    }

    var hamrsDetailSheet: some View {
        ServiceDetailSheet(
            serviceId: .service(.hamrs),
            isConfigured: hamrsIsConfigured,
            callsign: nil,
            syncedCount: uploadedCount(for: .hamrs),
            pendingCount: pendingCount(for: .hamrs),
            confirmedCount: nil,
            lastSyncReport: syncService.lastSyncResults[.hamrs],
            isSyncing: isSyncing,
            debugMode: debugMode,
            isInMaintenance: false,
            sessionExpiringSoon: false,
            sessionExpiryDate: nil,
            importedCount: nil,
            pendingFiles: nil,
            isMonitoring: nil,
            onSync: { await syncFromHAMRS() },
            onForceRedownload: { await performHAMRSForceRedownload() },
            onClearData: nil,
            onConfigure: {
                selectedService = nil
                settingsDestination = .hamrs
                selectedTab = .more
            }
        )
    }

    var lotwDetailSheet: some View {
        ServiceDetailSheet(
            serviceId: .service(.lotw),
            isConfigured: lotwIsConfigured,
            callsign: nil,
            syncedCount: uploadedCount(for: .lotw),
            pendingCount: pendingCount(for: .lotw),
            confirmedCount: asyncStats.lotwConfirmedCount,
            lastSyncReport: syncService.lastSyncResults[.lotw],
            isSyncing: isSyncing,
            debugMode: debugMode,
            isInMaintenance: false,
            sessionExpiringSoon: false,
            sessionExpiryDate: nil,
            importedCount: nil,
            pendingFiles: nil,
            isMonitoring: nil,
            onSync: { await syncFromLoTW() },
            onForceRedownload: { await performLoTWForceRedownload() },
            onClearData: { clearLoTWData() },
            onConfigure: {
                selectedService = nil
                settingsDestination = .lotw
                selectedTab = .more
            }
        )
    }

    var clublogDetailSheet: some View {
        ServiceDetailSheet(
            serviceId: .service(.clublog),
            isConfigured: clublogIsConfigured,
            callsign: clublogCallsign,
            syncedCount: uploadedCount(for: .clublog),
            pendingCount: pendingCount(for: .clublog),
            confirmedCount: nil,
            lastSyncReport: syncService.lastSyncResults[.clublog],
            isSyncing: isSyncing,
            debugMode: debugMode,
            isInMaintenance: false,
            sessionExpiringSoon: false,
            sessionExpiryDate: nil,
            importedCount: nil,
            pendingFiles: nil,
            isMonitoring: nil,
            onSync: { await syncFromClubLog() },
            onForceRedownload: { await performClubLogForceRedownload() },
            onClearData: { clearClubLogData() },
            onConfigure: {
                selectedService = nil
                settingsDestination = .clublog
                selectedTab = .more
            }
        )
    }

    var icloudDetailSheet: some View {
        ServiceDetailSheet(
            serviceId: .icloud,
            isConfigured: iCloudMonitor.iCloudContainerURL != nil,
            callsign: nil,
            syncedCount: 0,
            pendingCount: 0,
            confirmedCount: nil,
            lastSyncReport: nil,
            isSyncing: false,
            debugMode: debugMode,
            isInMaintenance: false,
            sessionExpiringSoon: false,
            sessionExpiryDate: nil,
            importedCount: asyncStats.icloudImportedCount,
            pendingFiles: iCloudMonitor.pendingFiles.count,
            isMonitoring: iCloudMonitor.isMonitoring,
            onSync: nil,
            onForceRedownload: nil,
            onClearData: nil,
            onConfigure: {
                selectedService = nil
                settingsDestination = .icloud
                selectedTab = .more
            }
        )
    }
}
