import Foundation

// MARK: - ExperimentalFeature

/// Central registry of all experimental features in Carrier Wave.
///
/// Each feature has a maturity level, description, and an opt-in toggle
/// backed by `UserDefaults`. The Experiments hub in Settings reads this
/// enum to display a unified list; individual views use `isEnabled(_:)`
/// to gate visibility.
///
/// When graduating a feature, remove its case here and delete all
/// `ExperimentalFeature.isEnabled(...)` guards referencing it.
public enum ExperimentalFeature: String, CaseIterable, Identifiable, Sendable {
    case icloudSync
    case radioControl
    case videoExport
    case ft8
    case tuneIn
    case eqsl
    case needs
    case parkGIS
    case queryRunner
    case rustStoreQSO
    case remoteSweep
    case propagationCheck
    case weatherRadar
    case activityLayers
    case bandScope
    case syncServer
    case satellites
    case wsjtx

    // MARK: Public

    // MARK: - Maturity

    public enum Maturity: String, Sendable {
        case alpha
        case beta

        // MARK: Public

        public var label: String {
            switch self {
            case .alpha: "Alpha"
            case .beta: "Experimental"
            }
        }
    }

    /// All features that are currently enabled.
    public static var enabledFeatures: [ExperimentalFeature] {
        allCases.filter { isEnabled($0) }
    }

    /// All features grouped by visibility: enabled first, then hidden.
    public static var grouped: (enabled: [ExperimentalFeature], hidden: [ExperimentalFeature]) {
        let enabled = allCases.filter { isEnabled($0) }
        let hidden = allCases.filter { !isEnabled($0) }
        return (enabled, hidden)
    }

    public var id: String {
        rawValue
    }

    // MARK: - Display Metadata

    public var title: String {
        switch self {
        case .icloudSync: "iCloud QSO Sync"
        case .radioControl: "Radio CAT Control"
        case .videoExport: "Video Export"
        case .ft8: "FT8"
        case .tuneIn: "Tune In"
        case .eqsl: "eQSL"
        case .needs: "Smart Spots / Needs"
        case .parkGIS: "Park Boundaries"
        case .queryRunner: "SQL Query Runner"
        case .rustStoreQSO: "QSO Rust Store"
        case .remoteSweep: "Remote Control of CW Sweep"
        case .propagationCheck: "Propagation Check"
        case .weatherRadar: "Weather Radar"
        case .activityLayers: "Activity Map Layers"
        case .bandScope: "Band Scope"
        case .syncServer: "Carrier Wave Sync"
        case .satellites: "Satellites"
        case .wsjtx: "WSJT-X Logging"
        }
    }

    public var summary: String {
        switch self {
        case .icloudSync:
            "Sync QSOs, sessions, and upload status across devices via iCloud."
        case .radioControl:
            "CAT control via BLE (ESP32 proxy), WiFi (Icom RS-BA1), or Flex SmartSDR."
        case .videoExport:
            "Generate animated map videos of logging sessions."
        case .ft8:
            "Decode and transmit FT8 using the iPhone microphone and speaker."
        case .tuneIn:
            "Listen to spots via KiwiSDR WebSDR receivers worldwide."
        case .eqsl:
            "Upload QSOs and download confirmations from eQSL.cc."
        case .needs:
            "Smart spot recommendations based on DXCC, WAS, and hunter progress."
        case .parkGIS:
            "Show park boundary polygons on the map."
        case .queryRunner:
            "Write, run, and save SQL queries (.cwquery) against live spots and your QSO log."
        case .rustStoreQSO:
            "Serve QSO reads from the Rust store instead of SwiftData (experimental mirror)."
        case .remoteSweep:
            "Pair this phone with CW Sweep on your Mac to view radio state and tune from across the room."
        case .propagationCheck:
            "How's my antenna? Watch RBN and PSK Reporter while you CQ, save results, and compare antennas or bands."
        case .weatherRadar:
            "NEXRAD radar overlay and active NWS alerts for your operating location (US only)."
        case .activityLayers:
            "Toggleable map overlays — grid squares and Tiles on the Air — on the Parks & Summits map."
        case .bandScope:
            "Vertical band scope of live POTA spots, plotted from the same saved SQL queries CW Sweep uses."
        case .syncServer:
            "Sync your log through the Carrier Wave server with end-to-end encryption, "
                + "instead of iCloud. Set a sync passphrase to begin."
        case .satellites:
            "Live satellite positions on a map, propagated from SatNOGS orbital elements."
        case .wsjtx:
            "Log FT8, FT4 and other digital QSOs as WSJT-X on your computer makes them, "
                + "over your local network."
        }
    }

    public var iconName: String {
        switch self {
        case .icloudSync: "icloud"
        case .radioControl: "antenna.radiowaves.left.and.right"
        case .videoExport: "film"
        case .ft8: "waveform"
        case .tuneIn: "headphones"
        case .eqsl: "envelope"
        case .needs: "sparkles"
        case .parkGIS: "map"
        case .queryRunner: "doc.text.magnifyingglass"
        case .rustStoreQSO: "cylinder"
        case .remoteSweep: "iphone.radiowaves.left.and.right"
        case .propagationCheck: "dot.radiowaves.up.forward"
        case .weatherRadar: "cloud.rain"
        case .activityLayers: "square.grid.3x3"
        case .bandScope: "chart.xyaxis.line"
        case .syncServer: "lock.icloud"
        case .satellites: "globe.americas"
        case .wsjtx: "dot.radiowaves.left.and.right"
        }
    }

    public var maturity: Maturity {
        switch self {
        case .icloudSync: .beta
        case .radioControl: .alpha
        case .videoExport: .beta
        case .ft8: .alpha
        case .tuneIn: .beta
        case .eqsl: .beta
        case .needs: .beta
        case .parkGIS: .beta
        case .queryRunner: .alpha
        case .rustStoreQSO: .alpha
        case .remoteSweep: .alpha
        case .propagationCheck: .alpha
        case .weatherRadar: .alpha
        case .activityLayers: .alpha
        case .bandScope: .alpha
        case .syncServer: .alpha
        case .satellites: .alpha
        case .wsjtx: .beta
        }
    }

    /// Features that cannot be disabled by the user.
    public var canBeDisabled: Bool {
        switch self {
        case .icloudSync,
             .radioControl,
             .videoExport,
             .ft8,
             .tuneIn,
             .eqsl,
             .parkGIS:
            false
        default:
            true
        }
    }

    /// Features hidden by default — users must opt in from the Experiments hub.
    public var isHiddenByDefault: Bool {
        switch self {
        case .queryRunner,
             .remoteSweep,
             .propagationCheck,
             .weatherRadar,
             .bandScope,
             .satellites:
            true
        // `.rustStoreQSO` graduated to default-on (Phase 1c): no longer hidden, so
        // `isEnabled` returns true by default while staying user-toggleable —
        // a kill switch back to SwiftData authority if a problem surfaces.
        default:
            false
        }
    }

    // MARK: - Feature Gating

    /// Check whether a feature is enabled. Hidden features require explicit
    /// opt-in regardless of other flags. Non-hidden, non-disableable features
    /// are always on. Otherwise falls back to UserDefaults.
    public static func isEnabled(_ feature: ExperimentalFeature) -> Bool {
        let key = defaultsKey(for: feature)
        if feature.isHiddenByDefault {
            // Hidden features must be explicitly opted in
            return UserDefaults.standard.bool(forKey: key)
        }
        if !feature.canBeDisabled {
            return true
        }
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Toggle a hidden feature on or off.
    public static func setEnabled(_ feature: ExperimentalFeature, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey(for: feature))
    }

    // MARK: Private

    private static func defaultsKey(for feature: ExperimentalFeature) -> String {
        "experimental.\(feature.rawValue).enabled"
    }
}
