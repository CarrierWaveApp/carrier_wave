import CarrierWaveData
import Foundation

/// Loads contest definitions from bundled JSON and user custom directory.
actor ContestTemplateLoader {
    // MARK: Internal

    func allTemplates() throws -> [ContestDefinition] {
        let templates = try loadIfNeeded()
        return Array(templates.values).sorted { $0.name < $1.name }
    }

    func template(for id: String) throws -> ContestDefinition? {
        let templates = try loadIfNeeded()
        return templates[id]
    }

    // MARK: Private

    private var cache: [String: ContestDefinition]?

    @discardableResult
    private func loadIfNeeded() throws -> [String: ContestDefinition] {
        if let cache {
            return cache
        }

        var result: [String: ContestDefinition] = [:]

        // Load bundled templates
        if let bundleURL = Bundle.main.url(forResource: "ContestTemplates", withExtension: nil) {
            let urls = try FileManager.default.contentsOfDirectory(
                at: bundleURL,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }

            for url in urls {
                let data = try Data(contentsOf: url)
                let definition = try JSONDecoder().decode(ContestDefinition.self, from: data)
                result[definition.id] = definition
            }
        }

        // Load user custom templates from ~/Library/Application Support/CWSweep/ContestTemplates/
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        if let customDir = appSupport?.appendingPathComponent("CWSweep/ContestTemplates") {
            if FileManager.default.fileExists(atPath: customDir.path) {
                let urls = try FileManager.default.contentsOfDirectory(
                    at: customDir,
                    includingPropertiesForKeys: nil
                ).filter { $0.pathExtension == "json" }

                for url in urls {
                    let data = try Data(contentsOf: url)
                    let definition = try JSONDecoder().decode(ContestDefinition.self, from: data)
                    result[definition.id] = definition
                }
            }
        }

        cache = result
        return result
    }
}
