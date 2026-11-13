import Foundation

// MARK: - LayoutStore

/// Manages custom and built-in layouts. Persists user layouts to UserDefaults.
@MainActor @Observable
final class LayoutStore {
    // MARK: Lifecycle

    init() {
        load()
    }

    // MARK: Internal

    private(set) var customLayouts: [CustomLayout] = []
    var activeLayoutId: String = CustomLayout.hunterPreset.id

    var allLayouts: [CustomLayout] {
        CustomLayout.builtInPresets + customLayouts
    }

    var activeLayout: CustomLayout {
        allLayouts.first { $0.id == activeLayoutId } ?? CustomLayout.hunterPreset
    }

    func setActiveLayout(_ layout: CustomLayout) {
        activeLayoutId = layout.id
        UserDefaults.standard.set(activeLayoutId, forKey: Self.activeIdKey)
    }

    func addLayout(_ layout: CustomLayout) {
        customLayouts.append(layout)
        save()
    }

    func updateLayout(_ layout: CustomLayout) {
        guard let index = customLayouts.firstIndex(where: { $0.id == layout.id }) else {
            return
        }
        customLayouts[index] = layout
        save()
    }

    func deleteLayout(id: String) {
        customLayouts.removeAll { $0.id == id }
        if activeLayoutId == id {
            activeLayoutId = CustomLayout.hunterPreset.id
        }
        save()
    }

    func duplicateLayout(_ source: CustomLayout, name: String) -> CustomLayout {
        var copy = source
        copy.id = UUID().uuidString
        copy.name = name
        copy.isBuiltIn = false
        copy.createdAt = .now
        copy.modifiedAt = .now
        addLayout(copy)
        return copy
    }

    // MARK: - Export / Import

    func exportLayout(_ layout: CustomLayout) -> Data? {
        try? Self.prettyEncoder.encode(layout)
    }

    func importLayout(from data: Data) throws -> CustomLayout {
        var layout = try Self.decoder.decode(CustomLayout.self, from: data)
        layout.id = UUID().uuidString
        layout.isBuiltIn = false
        addLayout(layout)
        return layout
    }

    // MARK: Private

    private static let layoutsKey = "customLayouts"
    private static let activeIdKey = "activeLayoutId"

    private static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func save() {
        if let data = try? Self.prettyEncoder.encode(customLayouts) {
            UserDefaults.standard.set(data, forKey: Self.layoutsKey)
        }
        UserDefaults.standard.set(activeLayoutId, forKey: Self.activeIdKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.layoutsKey),
           let layouts = try? Self.decoder.decode([CustomLayout].self, from: data)
        {
            customLayouts = layouts
        }
        activeLayoutId = UserDefaults.standard.string(forKey: Self.activeIdKey)
            ?? CustomLayout.hunterPreset.id
    }
}
