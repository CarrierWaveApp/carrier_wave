import UIKit

// MARK: - GoalProfileStore

/// Owns the active goal profile + quick toggles for the Band Scope.
/// Built-ins live in code; user-defined profiles persist as one JSON file
/// in Application Support. The active selection and toggles persist in
/// UserDefaults so a relaunch resumes the same lens state.
@MainActor
@Observable
final class GoalProfileStore {
    // MARK: Lifecycle

    init() {
        userProfiles = Self.loadUserProfiles()
        let defaults = UserDefaults.standard
        activeProfileID = defaults.string(forKey: Self.activeProfileKey)
            ?? GoalProfile.everything.id
        let storedToggles = defaults.data(forKey: Self.togglesKey)
            .flatMap { try? JSONDecoder().decode(QuickToggles.self, from: $0) }
        if let storedToggles {
            quickToggles = storedToggles
        }
    }

    // MARK: Internal

    static let activeProfileKey = "bandScopeActiveProfile"
    static let togglesKey = "bandScopeQuickToggles"

    private(set) var userProfiles: [GoalProfile]

    var quickToggles = QuickToggles() {
        didSet {
            if let data = try? JSONEncoder().encode(quickToggles) {
                UserDefaults.standard.set(data, forKey: Self.togglesKey)
            }
        }
    }

    var activeProfileID: String {
        didSet {
            UserDefaults.standard.set(activeProfileID, forKey: Self.activeProfileKey)
        }
    }

    var allProfiles: [GoalProfile] {
        GoalProfile.builtIns + userProfiles
    }

    var activeProfile: GoalProfile {
        allProfiles.first { $0.id == activeProfileID } ?? .everything
    }

    func saveUserProfile(_ profile: GoalProfile) {
        if let index = userProfiles.firstIndex(where: { $0.id == profile.id }) {
            userProfiles[index] = profile
        } else {
            userProfiles.append(profile)
        }
        persistUserProfiles()
    }

    func deleteUserProfile(id: String) {
        userProfiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = GoalProfile.everything.id
        }
        persistUserProfiles()
    }

    // MARK: Private

    private static var profilesURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let dir = support.appendingPathComponent("CarrierWave", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("band-scope-profiles.json")
    }

    private static func loadUserProfiles() -> [GoalProfile] {
        guard let data = try? Data(contentsOf: profilesURL) else {
            return []
        }
        return (try? JSONDecoder().decode([GoalProfile].self, from: data)) ?? []
    }

    private func persistUserProfiles() {
        guard let data = try? JSONEncoder().encode(userProfiles) else {
            return
        }
        try? data.write(to: Self.profilesURL, options: .atomic)
    }
}
