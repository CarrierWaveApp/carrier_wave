import CarrierWaveData
import Foundation

// MARK: - TourState

@Observable
final class TourState {
    // MARK: Lifecycle

    init() {
        hasCompletedIntroTour = UserDefaults.standard.bool(forKey: Keys.hasCompletedIntroTour)
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)
        lastTourVersion = UserDefaults.standard.string(forKey: Keys.lastTourVersion) ?? ""
        seenMiniTours = Set(
            UserDefaults.standard.stringArray(forKey: Keys.seenMiniTours) ?? []
        )
    }

    // MARK: Internal

    enum MiniTourID: String, CaseIterable {
        case logger
        case loggerInteractive = "logger_interactive"
        case logs
        case potaActivations = "pota_activations"
        case potaAccountSetup = "pota_account_setup"
        case challenges
        case statsDrilldown = "stats_drilldown"
        case lofiSetup = "lofi_setup"
        case activityLog = "activity_log"
    }

    private(set) var hasCompletedIntroTour: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedIntroTour, forKey: Keys.hasCompletedIntroTour)
        }
    }

    private(set) var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    private(set) var lastTourVersion: String {
        didSet { UserDefaults.standard.set(lastTourVersion, forKey: Keys.lastTourVersion) }
    }

    private(set) var seenMiniTours: Set<String> {
        didSet { UserDefaults.standard.set(Array(seenMiniTours), forKey: Keys.seenMiniTours) }
    }

    func shouldShowIntroTour() -> Bool {
        !hasCompletedIntroTour
    }

    func shouldShowOnboarding() -> Bool {
        hasCompletedIntroTour && !hasCompletedOnboarding && !hasExistingProfile()
    }

    func completeIntroTour(version: String) {
        hasCompletedIntroTour = true
        lastTourVersion = version
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func shouldShowUpdatePrompt(currentVersion: String, majorVersions: [String]) -> Bool {
        guard hasCompletedIntroTour else {
            return false
        }
        guard majorVersions.contains(currentVersion) else {
            return false
        }
        return lastTourVersion < currentVersion
    }

    func acknowledgeUpdatePrompt(version: String) {
        lastTourVersion = version
    }

    func shouldShowMiniTour(_ id: MiniTourID) -> Bool {
        !seenMiniTours.contains(id.rawValue)
    }

    func markMiniTourSeen(_ id: MiniTourID) {
        seenMiniTours.insert(id.rawValue)
    }

    func resetForTesting() {
        hasCompletedIntroTour = false
        hasCompletedOnboarding = false
        lastTourVersion = ""
        seenMiniTours = []
    }

    // MARK: Private

    private enum Keys {
        static let hasCompletedIntroTour = "tour.hasCompletedIntroTour"
        static let hasCompletedOnboarding = "tour.hasCompletedOnboarding"
        static let lastTourVersion = "tour.lastTourVersion"
        static let seenMiniTours = "tour.seenMiniTours"
    }

    /// Check if user already has a profile set up (skip onboarding if so)
    /// Note: We check UserDefaults directly instead of calling UserProfileService
    /// because UserProfileService is @MainActor and TourState is not.
    private func hasExistingProfile() -> Bool {
        UserDefaults.standard.string(forKey: "loggerDefaultCallsign") != nil
    }
}
