import CarrierWaveData
import Foundation

// MARK: - SavedSessionTemplate

/// A user-saved session configuration template with a custom name.
/// Stored as JSON in UserDefaults, separate from the auto-generated
/// recent-session templates.
struct SavedSessionTemplate: Codable, Identifiable {
    // MARK: Lifecycle

    init(
        name: String,
        mode: String,
        power: String?,
        programs: [String],
        parkReference: String?,
        sotaReference: String?,
        wwffReference: String?,
        missionReference: String?,
        radio: String?,
        antenna: String?,
        key: String?,
        mic: String?,
        callsignPrefix: String?,
        callsignSuffix: String?,
        customSuffix: String?,
        isClubStation: Bool,
        clubCallsign: String?,
        isRove: Bool,
        grid: String?
    ) {
        id = UUID()
        self.name = name
        createdAt = Date()
        self.mode = mode
        self.power = power
        self.programs = programs
        self.parkReference = parkReference
        self.sotaReference = sotaReference
        self.wwffReference = wwffReference
        self.missionReference = missionReference
        self.radio = radio
        self.antenna = antenna
        self.key = key
        self.mic = mic
        self.callsignPrefix = callsignPrefix
        self.callsignSuffix = callsignSuffix
        self.customSuffix = customSuffix
        self.isClubStation = isClubStation
        self.clubCallsign = clubCallsign
        self.isRove = isRove
        self.grid = grid
    }

    // MARK: Internal

    let id: UUID
    let name: String
    let createdAt: Date
    let mode: String
    let power: String?
    let programs: [String]
    let parkReference: String?
    let sotaReference: String?
    let wwffReference: String?
    let missionReference: String?
    let radio: String?
    let antenna: String?
    let key: String?
    let mic: String?
    let callsignPrefix: String?
    let callsignSuffix: String?
    let customSuffix: String?
    let isClubStation: Bool
    let clubCallsign: String?
    let isRove: Bool
    let grid: String?

    /// The activation type derived from saved programs
    var activationType: ActivationType {
        ActivationType.from(programs: Set(programs))
    }

    /// Summary line for display (e.g. "CW 100W POTA")
    var subtitle: String {
        var parts: [String] = [mode]
        if let power, !power.isEmpty {
            parts.append("\(power)W")
        }
        if let radio, !radio.isEmpty {
            parts.append(radio)
        }
        if !programs.isEmpty {
            let labels = programs.map { $0.uppercased() }
            parts.append(contentsOf: labels)
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: - SavedSessionTemplateStore

/// Manages persistence of saved session templates in UserDefaults.
enum SavedSessionTemplateStore {
    // MARK: Internal

    static func load() -> [SavedSessionTemplate] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }
        return (try? JSONDecoder().decode(
            [SavedSessionTemplate].self, from: data
        )) ?? []
    }

    static func save(_ templates: [SavedSessionTemplate]) {
        guard let data = try? JSONEncoder().encode(templates) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func add(_ template: SavedSessionTemplate) {
        var templates = load()
        templates.insert(template, at: 0)
        save(templates)
    }

    static func delete(id: UUID) {
        var templates = load()
        templates.removeAll { $0.id == id }
        save(templates)
    }

    // MARK: Private

    private static let storageKey = "savedSessionTemplates"
}
