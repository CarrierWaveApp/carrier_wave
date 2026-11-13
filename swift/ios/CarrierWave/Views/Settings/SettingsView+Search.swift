import CarrierWaveData
import SwiftUI

// MARK: - Search Destination Navigation

extension SettingsMainView {
    @ViewBuilder
    func searchDestinationView(
        for dest: SettingsSearchDestination
    ) -> some View {
        switch dest {
        case .appearance,
             .logger,
             .potaActivations,
             .syncSources,
             .dataTools,
             .aboutMe:
            categoryDestinationView(for: dest)
        case .tabConfiguration,
             .dashboardMetrics,
             .onAirNow,
             .huntP2P,
             .contestCalendar,
             .experiments,
             .keyboardRow,
             .commandRow,
             .keyboardRows,
             .prefixRow,
             .webSDRRecordings,
             .webSDRFavorites,
             .activityLogSettings,
             .myEquipment:
            featureDestinationView(for: dest)
        case .qrzCallbook,
             .callsignNotes,
             .externalData,
             .attributions,
             .syncDebug,
             .hiddenQSOs,
             .spotlightDebug,
             .backups:
            toolDestinationView(for: dest)
        case .qrzLogbook,
             .pota,
             .lofi,
             .hamrs,
             .lotw,
             .clublog,
             .eqsl,
             .icloud,
             .tota,
             .activities,
             .amt,
             .wsjtx,
             .callsignAliases:
            syncDestinationView(for: dest)
        }
    }

    @ViewBuilder
    private func categoryDestinationView(
        for dest: SettingsSearchDestination
    ) -> some View {
        switch dest {
        case .appearance:
            AppearanceSettingsView()
        case .logger:
            LoggerDetailSettingsView()
        case .potaActivations:
            POTAActivationSettingsView()
        case .syncSources:
            SyncSourcesSettingsView(
                potaAuth: potaAuth,
                tourState: tourState,
                syncService: syncService
            )
        case .dataTools:
            DataToolsSettingsView()
        case .aboutMe:
            AboutMeView { showOnboarding = true }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func featureDestinationView(
        for dest: SettingsSearchDestination
    ) -> some View {
        switch dest {
        case .tabConfiguration:
            TabConfigurationView()
        case .dashboardMetrics:
            DashboardMetricsSettingsView()
        case .onAirNow:
            OnAirSettingsView()
        case .huntP2P:
            HuntSettingsView()
        case .contestCalendar:
            ContestCalendarSettingsView()
        case .experiments:
            ExperimentsView()
        case .keyboardRow:
            KeyboardRowSettingsView()
        case .commandRow:
            CommandRowSettingsView()
        case .keyboardRows:
            KeyboardRowsSettingsView()
        case .prefixRow:
            PrefixRowSettingsView()
        case .webSDRRecordings:
            WebSDRRecordingsView()
        case .webSDRFavorites:
            WebSDRFavoritesView()
        case .activityLogSettings:
            ActivityLogSettingsView()
        case .myEquipment:
            EquipmentBrowserView()
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func toolDestinationView(
        for dest: SettingsSearchDestination
    ) -> some View {
        switch dest {
        case .qrzCallbook:
            QRZCallbookSettingsView()
        case .callsignNotes:
            CallsignNotesSettingsView()
        case .externalData:
            ExternalDataView()
        case .attributions:
            AttributionsView()
        case .syncDebug:
            SyncDebugView(potaAuth: potaAuth)
        case .hiddenQSOs:
            AllHiddenQSOsView()
        case .spotlightDebug:
            SpotlightDebugView()
        case .backups:
            BackupSettingsView()
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func syncDestinationView(
        for dest: SettingsSearchDestination
    ) -> some View {
        switch dest {
        case .qrzLogbook:
            QRZSettingsView(syncService: syncService)
        case .pota:
            POTASettingsView(
                potaAuth: potaAuth,
                tourState: tourState,
                syncService: syncService
            )
        case .lofi:
            LoFiSettingsView(
                tourState: tourState,
                syncService: syncService
            )
        case .hamrs:
            HAMRSSettingsView(syncService: syncService)
        case .lotw:
            LoTWSettingsView(syncService: syncService)
        case .clublog:
            ClubLogSettingsView()
        case .eqsl:
            EQSLSettingsView()
        case .icloud:
            CloudSyncSettingsView()
        case .tota:
            TOTASettingsView()
        case .amt:
            AMTSettingsView()
        case .wsjtx:
            WsjtxSettingsView()
        case .activities:
            ActivitiesSettingsView()
        case .callsignAliases:
            CallsignAliasesSettingsView()
        default:
            EmptyView()
        }
    }
}
