// Video Export Defaults
//
// UserDefaults-backed persistence for the last-used VideoExportConfig on this device.
// The sessionId is excluded (always per-session); everything else pre-fills the sheet.

import Foundation

// MARK: - StoredVideoExportConfig

struct StoredVideoExportConfig: Codable, Equatable {
    static let defaults = StoredVideoExportConfig(
        mode: .highlightReel,
        includeAudio: true,
        mapStyle: .standard,
        layers: .defaults,
        hudDensity: .full,
        theme: .classic
    )

    var mode: VideoExportConfig.Mode
    var includeAudio: Bool
    var mapStyle: VideoExportConfig.MapStyle
    var layers: LayerVisibility
    var hudDensity: HUDDensity
    var theme: ThemePreset
}

// MARK: - VideoExportDefaults

enum VideoExportDefaults {
    // MARK: Internal

    static func load() -> StoredVideoExportConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(StoredVideoExportConfig.self, from: data)
        else {
            return .defaults
        }
        return decoded
    }

    static func save(_ config: StoredVideoExportConfig) {
        guard let data = try? JSONEncoder().encode(config) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: Private

    private static let storageKey = "videoExport.lastConfig.v1"
}
