import Foundation

// MARK: - BandScopeLayout

/// Layout modes for the band scope container view.
/// Each mode corresponds to a design variant from the band scope redesign spec.
enum BandScopeLayout: String, CaseIterable, Identifiable, Codable {
    /// Variant 1: Refined single-band scope with mini-map, crosshair, watch markers
    case single
    /// Variant 4 (recommended): Single-band scope + band rail sidebar
    case hybrid
    /// Variant 2: N1MM-style stacked band columns
    case stacked
    /// Variant 3: TradingView-style grid of band cells
    case grid

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .single: "Single Band"
        case .hybrid: "Band Scope + Rail"
        case .stacked: "Stacked Bands"
        case .grid: "Band Grid"
        }
    }

    var icon: String {
        switch self {
        case .single: "waveform"
        case .hybrid: "sidebar.trailing"
        case .stacked: "rectangle.split.3x1"
        case .grid: "square.grid.3x3"
        }
    }
}

// MARK: - FrequencyBookmark

/// A user-placed frequency marker ("watch this frequency").
/// Persists per session; not stored in SwiftData.
struct FrequencyBookmark: Identifiable, Codable, Equatable {
    // MARK: Lifecycle

    init(frequencyKHz: Double, bandId: String, note: String? = nil) {
        id = UUID()
        self.frequencyKHz = frequencyKHz
        self.bandId = bandId
        self.note = note
        createdAt = Date()
    }

    // MARK: Internal

    let id: UUID
    var frequencyKHz: Double
    var bandId: String
    var note: String?
    var createdAt: Date

    /// Age in minutes since creation
    var ageMinutes: Double {
        Date().timeIntervalSince(createdAt) / 60
    }

    /// Display string for the frequency
    var frequencyDisplay: String {
        String(format: "%.1f", frequencyKHz)
    }
}

// MARK: - ZoomRegionPreset

/// Named zoom presets for common sub-band regions.
struct ZoomRegionPreset: Identifiable {
    /// All available presets
    static let all: [ZoomRegionPreset] = [
        // 20m presets
        ZoomRegionPreset(id: "20m-cw-dx", label: "CW DX (000-040)", bandId: "20m",
                         lowerKHz: 14_000, upperKHz: 14_040),
        ZoomRegionPreset(id: "20m-rtty", label: "RTTY (070-099)", bandId: "20m",
                         lowerKHz: 14_070, upperKHz: 14_099),
        ZoomRegionPreset(id: "20m-ft8", label: "FT8 (074)", bandId: "20m",
                         lowerKHz: 14_070, upperKHz: 14_080),
        ZoomRegionPreset(id: "20m-ssb-dx", label: "SSB DX (150-200)", bandId: "20m",
                         lowerKHz: 14_150, upperKHz: 14_200),
        // 40m presets
        ZoomRegionPreset(id: "40m-cw", label: "CW (000-070)", bandId: "40m",
                         lowerKHz: 7_000, upperKHz: 7_070),
        ZoomRegionPreset(id: "40m-ft8", label: "FT8 (074)", bandId: "40m",
                         lowerKHz: 7_070, upperKHz: 7_080),
        // 15m presets
        ZoomRegionPreset(id: "15m-cw-dx", label: "CW DX (000-040)", bandId: "15m",
                         lowerKHz: 21_000, upperKHz: 21_040),
        ZoomRegionPreset(id: "15m-ssb-dx", label: "SSB DX (200-300)", bandId: "15m",
                         lowerKHz: 21_200, upperKHz: 21_300),
        // 10m presets
        ZoomRegionPreset(id: "10m-cw", label: "CW (000-070)", bandId: "10m",
                         lowerKHz: 28_000, upperKHz: 28_070),
        ZoomRegionPreset(id: "10m-ft8", label: "FT8 (074)", bandId: "10m",
                         lowerKHz: 28_070, upperKHz: 28_080),
    ]

    let id: String
    let label: String
    let bandId: String
    let lowerKHz: Double
    let upperKHz: Double

    /// Presets applicable to a given band
    static func presets(for bandId: String) -> [ZoomRegionPreset] {
        all.filter { $0.bandId == bandId }
    }
}

// MARK: - PerBandZoomState

/// Stores zoom/pan state per band for preservation across band switches.
struct PerBandZoomState: Codable {
    var zoom: CGFloat
    var pan: CGFloat
}
