import CarrierWaveData
import XCTest
@testable import CarrierWave

/// iOS-side gate tests for `MacroTelemetryReporter`. Body-shape mapping
/// is covered by `RegistryRunEventBodyTests` in CarrierWaveData; this
/// suite focuses on the UserDefaults opt-in + the registry-only filter.
final class MacroTelemetryReporterTests: XCTestCase {
    func testOptInKeyMatchesSettingsBinding() {
        // The Settings → Experiments toggle is wired to this exact key.
        // If the constant changes the toggle silently stops gating telemetry,
        // so pin it down.
        XCTAssertEqual(MacroTelemetryReporter.optInKey, "macrosTelemetryOptIn")
    }

    func testReportIsNoOpForLocalOnlyMacroEvenWhenOptedIn() async {
        UserDefaults.standard.set(true, forKey: MacroTelemetryReporter.optInKey)
        defer {
            UserDefaults.standard.removeObject(forKey: MacroTelemetryReporter.optInKey)
        }
        // A spec without a `registry` field has no slug to attribute the event
        // to — the reporter must not throw and must not crash on the nil slug.
        let spec = RadioMacroSpec(
            name: "Local-only macro",
            capabilities: RadioMacroCapabilities(),
            args: [],
            steps: []
        )
        await MacroTelemetryReporter.reportIfOptedIn(
            spec: spec,
            outcome: .success(executed: 1, elapsed: 0.1)
        )
        // No throw, no network — the registry holder is nil in test context
        // so the guard returns early. If the early guard regresses, this
        // test crashes with a nil dereference inside the holder.
    }

    func testReportIsNoOpWhenOptInOff() async {
        UserDefaults.standard.set(false, forKey: MacroTelemetryReporter.optInKey)
        let spec = RadioMacroSpec(
            name: "Registry macro",
            capabilities: RadioMacroCapabilities(),
            registry: RegistryRef(slug: "tune-pota", registryVersion: 1, publishedAt: Date()),
            args: [],
            steps: []
        )
        await MacroTelemetryReporter.reportIfOptedIn(
            spec: spec,
            outcome: .success(executed: 1, elapsed: 0.1)
        )
    }
}
