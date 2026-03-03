import Foundation

// MARK: - StationProfile

/// Reusable station configuration for the activity log.
/// Users define profiles like "Home QTH", "Mobile", "QRP Portable"
/// and switch between them as operating conditions change.
struct StationProfile: Codable, Identifiable, Equatable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        name: String,
        power: Int? = nil,
        rig: String? = nil,
        antenna: String? = nil,
        key: String? = nil,
        mic: String? = nil,
        grid: String? = nil,
        useCurrentLocation: Bool = false,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.power = power
        self.rig = rig
        self.antenna = antenna
        self.key = key
        self.mic = mic
        self.grid = grid
        self.useCurrentLocation = useCurrentLocation
        self.isDefault = isDefault
    }

    // MARK: Internal

    var id: UUID
    var name: String
    var power: Int?
    var rig: String?
    var antenna: String?
    var key: String?
    var mic: String?
    var grid: String?
    var useCurrentLocation: Bool
    var isDefault: Bool

    /// Summary line for display (e.g., "IC-7300 · 100W · Hex beam")
    var summaryLine: String {
        var parts: [String] = []
        if let rig, !rig.isEmpty {
            parts.append(rig)
        }
        if let power {
            parts.append("\(power)W")
        }
        if let antenna, !antenna.isEmpty {
            parts.append(antenna)
        }
        return parts.isEmpty ? "No equipment set" : parts.joined(separator: " · ")
    }
}

// MARK: - StationProfileStorage

/// UserDefaults-backed storage for station profiles.
/// Mirrors the RadioStorage pattern from RadioPickerSheet.swift.
enum StationProfileStorage {
    // MARK: Internal

    static func load() -> [StationProfile] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([StationProfile].self, from: data)) ?? []
    }

    static func save(_ profiles: [StationProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func add(_ profile: StationProfile) {
        var profiles = load()
        // If this is the first profile or marked as default, ensure only one default
        var newProfile = profile
        if profiles.isEmpty {
            newProfile.isDefault = true
        } else if newProfile.isDefault {
            profiles = profiles.map { existing in
                var updated = existing
                updated.isDefault = false
                return updated
            }
        }
        profiles.append(newProfile)
        save(profiles)
    }

    static func update(_ profile: StationProfile) {
        var profiles = load()
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }
        // If setting as default, clear other defaults
        if profile.isDefault {
            profiles = profiles.map { existing in
                var updated = existing
                updated.isDefault = false
                return updated
            }
        }
        profiles[index] = profile
        save(profiles)
    }

    static func remove(_ id: UUID) {
        var profiles = load()
        profiles.removeAll { $0.id == id }
        // If we removed the default, make the first one default
        if !profiles.isEmpty, !profiles.contains(where: \.isDefault) {
            profiles[0].isDefault = true
        }
        save(profiles)
    }

    static func defaultProfile() -> StationProfile? {
        let profiles = load()
        return profiles.first(where: { $0.isDefault }) ?? profiles.first
    }

    static func profile(for id: UUID) -> StationProfile? {
        load().first { $0.id == id }
    }

    // MARK: Private

    private static let key = "stationProfiles"
}
