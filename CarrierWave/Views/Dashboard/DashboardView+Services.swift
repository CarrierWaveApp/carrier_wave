import SwiftUI

// MARK: - DashboardView Services List

extension DashboardView {
    // MARK: - Services List View

    var servicesList: some View {
        ServiceListView(
            services: buildServiceInfoList(),
            syncPhase: syncService.syncPhase,
            onServiceTap: { serviceId in
                selectedService = serviceId
            }
        )
    }

    // MARK: - Build Service Info List

    func buildServiceInfoList() -> [ServiceInfo] {
        let canBypass = debugMode && bypassPOTAMaintenance
        let potaInMaintenance = POTAClient.isInMaintenanceWindow() && !canBypass

        return [
            lofiServiceInfo,
            qrzServiceInfo,
            potaServiceInfo(inMaintenance: potaInMaintenance),
            hamrsServiceInfo,
            lotwServiceInfo,
            icloudServiceInfo,
        ]
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
            tertiaryInfo: lofiStatusText,
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
            tertiaryInfo: qrzIsConfigured ? nil : "Not configured",
            showWarning: pendingCount(for: .qrz) > 0,
            isSyncing: syncService.isSyncing
        )
    }

    private func potaServiceInfo(inMaintenance: Bool) -> ServiceInfo {
        ServiceInfo(
            id: .service(.pota),
            name: "POTA",
            status: potaStatus(inMaintenance: inMaintenance),
            primaryStat: potaAuth.isAuthenticated ? "\(uploadedCount(for: .pota)) synced" : nil,
            secondaryStat: pendingCount(for: .pota) > 0
                ? "\(pendingCount(for: .pota)) pending" : nil,
            tertiaryInfo: potaAuth.isAuthenticated ? nil : "Not configured",
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
            tertiaryInfo: hamrsIsConfigured ? nil : "Not configured",
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
            tertiaryInfo: lotwIsConfigured ? nil : "Not configured",
            showWarning: false,
            isSyncing: syncService.isSyncing
        )
    }

    private var icloudServiceInfo: ServiceInfo {
        ServiceInfo(
            id: .icloud,
            name: "iCloud",
            status: iCloudMonitor.iCloudContainerURL != nil ? .connected : .notConfigured,
            primaryStat: iCloudMonitor.iCloudContainerURL != nil
                ? "\(qsos.filter { $0.importSource == .icloud }.count) imported" : nil,
            secondaryStat: !iCloudMonitor.pendingFiles.isEmpty
                ? "\(iCloudMonitor.pendingFiles.count) pending" : nil,
            tertiaryInfo: iCloudMonitor.iCloudContainerURL != nil ? nil : "Not configured",
            showWarning: !iCloudMonitor.pendingFiles.isEmpty,
            isSyncing: false
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
        return potaAuth.isAuthenticated ? .connected : .notConfigured
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
            lastSyncResult: lofiSyncResult,
            isSyncing: isSyncing,
            debugMode: debugMode,
            isInMaintenance: false,
            sessionExpiringSoon: false,
            sessionExpiryDate: nil,
            importedCount: nil,
            pendingFiles: nil,
            isMonitoring: nil,
            onSync: { await syncFromLoFi() },
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
            confirmedCount: qsos.filter(\.qrzConfirmed).count,
            lastSyncResult: qrzSyncResult,
            isSyncing: isSyncing,
            debugMode: debugMode,
            isInMaintenance: false,
            sessionExpiringSoon: false,
            sessionExpiryDate: nil,
            importedCount: nil,
            pendingFiles: nil,
            isMonitoring: nil,
            onSync: { await performQRZSync() },
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
            isConfigured: potaAuth.isAuthenticated,
            callsign: potaAuth.currentToken?.callsign,
            syncedCount: uploadedCount(for: .pota),
            pendingCount: pendingCount(for: .pota),
            confirmedCount: nil,
            lastSyncResult: potaSyncResult,
            isSyncing: isSyncing,
            debugMode: debugMode,
            isInMaintenance: inMaintenance,
            sessionExpiringSoon: potaAuth.currentToken?.isExpiringSoon() ?? false,
            sessionExpiryDate: potaAuth.currentToken?.expiresAt,
            importedCount: nil,
            pendingFiles: nil,
            isMonitoring: nil,
            onSync: { await performPOTASync() },
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
            lastSyncResult: hamrsSyncResult,
            isSyncing: isSyncing,
            debugMode: debugMode,
            isInMaintenance: false,
            sessionExpiringSoon: false,
            sessionExpiryDate: nil,
            importedCount: nil,
            pendingFiles: nil,
            isMonitoring: nil,
            onSync: { await syncFromHAMRS() },
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
            confirmedCount: qsos.filter(\.lotwConfirmed).count,
            lastSyncResult: lotwSyncResult,
            isSyncing: isSyncing,
            debugMode: debugMode,
            isInMaintenance: false,
            sessionExpiringSoon: false,
            sessionExpiryDate: nil,
            importedCount: nil,
            pendingFiles: nil,
            isMonitoring: nil,
            onSync: { await syncFromLoTW() },
            onClearData: { clearLoTWData() },
            onConfigure: {
                selectedService = nil
                settingsDestination = .lotw
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
            lastSyncResult: nil,
            isSyncing: false,
            debugMode: debugMode,
            isInMaintenance: false,
            sessionExpiringSoon: false,
            sessionExpiryDate: nil,
            importedCount: qsos.filter { $0.importSource == .icloud }.count,
            pendingFiles: iCloudMonitor.pendingFiles.count,
            isMonitoring: iCloudMonitor.isMonitoring,
            onSync: nil,
            onClearData: nil,
            onConfigure: {
                selectedService = nil
                settingsDestination = .icloud
                selectedTab = .more
            }
        )
    }
}
