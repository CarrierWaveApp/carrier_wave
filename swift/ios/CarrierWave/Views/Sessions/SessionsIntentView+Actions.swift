import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Intent Actions

/// Routing logic for each of the four intent cards plus recent/saved
/// templates. All actions either mutate `UserDefaults` defaults used by
/// `SessionStartSheet` and then present it, or navigate into the Hunter
/// Log flow.
extension SessionsIntentView {
    // MARK: - Intent Card Actions

    /// "Activate" — start a session with the user's last-used program
    /// selection preserved (so the sheet opens with POTA/SOTA/etc. already
    /// picked). First-time users land on plain-casual defaults, which is
    /// fine — the sheet still lets them pick.
    func startActivate() {
        if tourState.shouldShowMiniTour(.loggerInteractive) {
            presentLoggerTour()
            return
        }
        // Leave `loggerDefaultPrograms` as whatever the user last used.
        // `SessionStartSheet` will restore it from `@AppStorage`.
        sessionOperationType = .activation
        showSessionSheet = true
    }

    /// "Hunt" — opens the Hunter Log if set up, otherwise the setup sheet.
    /// Hunter Log is a no-session-start-stop flow for chasing spots, so we
    /// route directly into it rather than through `SessionStartSheet`.
    func startHunt() {
        guard activityLogManager?.activeLog != nil else {
            showingActivityLogSetup = true
            return
        }
        navigateToHunterLog = true
    }

    /// "Casual" — clears the program selection so the sheet opens with no
    /// activation type pre-selected. Frequency/mode defaults still apply.
    func startCasual() {
        if tourState.shouldShowMiniTour(.loggerInteractive) {
            presentLoggerTour()
            return
        }
        UserDefaults.standard.set("", forKey: "loggerDefaultPrograms")
        UserDefaults.standard.removeObject(forKey: "loggerDefaultParkReference")
        sessionOperationType = .casual
        showSessionSheet = true
    }

    /// "Contest" — present the session-start sheet pre-wired for a contest
    /// start. The sheet inspects `initialContestId` on appearance: if it's a
    /// non-empty slug, the sheet pre-loads that `ContestDefinition`; if it's
    /// the empty string (no last-used contest), the sheet auto-presents the
    /// `ContestCalendarView` picker so the operator's first interaction is
    /// "which contest?" rather than scrolling through the form.
    func startContest() {
        if tourState.shouldShowMiniTour(.loggerInteractive) {
            presentLoggerTour()
            return
        }
        // Clear programs so casual/POTA pre-selection doesn't fight the
        // contest flow. The contest section drives setup from here.
        UserDefaults.standard.set("", forKey: "loggerDefaultPrograms")
        UserDefaults.standard.removeObject(forKey: "loggerDefaultParkReference")
        let lastUsed = UserDefaults.standard.string(forKey: "loggerDefaultContestId") ?? ""
        sessionStartContestIntent = lastUsed
        sessionOperationType = .contest
        showSessionSheet = true
    }

    // MARK: - Tour Presentation

    private func presentLoggerTour() {
        let manager = LoggerTourManager()
        manager.setOnComplete {
            tourState.markMiniTourSeen(.loggerInteractive)
            tourState.markMiniTourSeen(.logger)
            loggerTourManager = nil
        }
        manager.start()
        loggerTourManager = manager
    }

    // MARK: - Template Actions

    func startFromTemplate(_ template: SessionTemplate) {
        UserDefaults.standard.set(template.mode, forKey: "loggerDefaultMode")
        if let power = template.power {
            UserDefaults.standard.set(String(power), forKey: "loggerDefaultPower")
        }
        if let programs = template.programsRaw, !programs.isEmpty {
            UserDefaults.standard.set(programs, forKey: "loggerDefaultPrograms")
        }
        if let park = template.parkReference {
            UserDefaults.standard.set(park, forKey: "loggerDefaultParkReference")
        }
        sessionOperationType = .activation
        showSessionSheet = true
    }

    func startFromSavedTemplate(_ template: SavedSessionTemplate) {
        selectedSavedTemplate = template
        sessionOperationType = .activation
        showSessionSheet = true
    }

    // MARK: - Data Loading

    func refreshActiveSessions() {
        guard let manager = sessionManager else {
            activeSessions = []
            activeSessionQSOCounts = [:]
            return
        }

        activeSessions = manager.fetchActiveSessions()

        var counts: [UUID: Int] = [:]
        for session in activeSessions {
            let sessionId = session.id
            counts[sessionId] = (try? modelContext.boundedCount(
                QSO.self,
                predicate: #Predicate { $0.loggingSessionId == sessionId && !$0.isHidden }
            )) ?? 0
        }
        activeSessionQSOCounts = counts
    }

    func loadRecentTemplates() {
        guard let manager = sessionManager else {
            recentTemplates = []
            return
        }
        loadDismissedTemplateKeys()
        let recent = manager.getRecentSessions(limit: 20)
        let all = SessionTemplate.fromRecentSessions(recent, limit: 20)
        recentTemplates = Array(
            all.filter { !dismissedTemplateKeys.contains($0.id) }.prefix(3)
        )
        savedTemplates = SavedSessionTemplateStore.load()
    }

    func dismissTemplate(_ template: SessionTemplate) {
        withAnimation {
            dismissedTemplateKeys.insert(template.id)
            recentTemplates.removeAll { $0.id == template.id }
        }
        saveDismissedTemplateKeys()
        loadRecentTemplates()
    }

    func deleteSavedTemplate(_ template: SavedSessionTemplate) {
        withAnimation {
            savedTemplates.removeAll { $0.id == template.id }
        }
        SavedSessionTemplateStore.delete(id: template.id)
    }

    private func loadDismissedTemplateKeys() {
        let stored = UserDefaults.standard.stringArray(
            forKey: SessionsIntentView.dismissedTemplatesKey
        ) ?? []
        dismissedTemplateKeys = Set(stored)
    }

    private func saveDismissedTemplateKeys() {
        UserDefaults.standard.set(
            Array(dismissedTemplateKeys),
            forKey: SessionsIntentView.dismissedTemplatesKey
        )
    }

    /// Fetches the session referenced by `pendingSpotlightSessionID` from
    /// SwiftData and assigns it to `spotlightSession` so the navigation
    /// destination pushes `SessionDetailView`. Clears the pending binding so
    /// it isn't re-consumed.
    func consumePendingSpotlightSession() async {
        guard let sessionID = pendingSpotlightSessionID else {
            return
        }
        pendingSpotlightSessionID = nil
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        descriptor.fetchLimit = 1
        spotlightSession = try? modelContext.fetch(descriptor).first
    }
}
