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
             .aboutMe,
             .tabConfiguration,
             .dashboardMetrics,
             .keyboardRow,
             .commandRow,
             .webSDRRecordings,
             .webSDRFavorites,
             .activityLogSettings:
            categoryDestinationView(for: dest)
        case .qrzCallbook,
             .callsignNotes,
             .externalData,
             .attributions,
             .syncDebug,
             .hiddenQSOs:
            toolDestinationView(for: dest)
        case .qrzLogbook,
             .pota,
             .lofi,
             .hamrs,
             .lotw,
             .clublog,
             .icloud,
             .activities,
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
        case .tabConfiguration:
            TabConfigurationView()
        case .dashboardMetrics:
            DashboardMetricsSettingsView()
        case .keyboardRow:
            KeyboardRowSettingsView()
        case .commandRow:
            CommandRowSettingsView()
        case .webSDRRecordings:
            WebSDRRecordingsView()
        case .webSDRFavorites:
            WebSDRFavoritesView()
        case .activityLogSettings:
            ActivityLogSettingsView()
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
            ClubLogSettingsView(syncService: syncService)
        case .icloud:
            ICloudSettingsView()
        case .activities:
            ActivitiesSettingsView()
        case .callsignAliases:
            CallsignAliasesSettingsView()
        default:
            EmptyView()
        }
    }
}
