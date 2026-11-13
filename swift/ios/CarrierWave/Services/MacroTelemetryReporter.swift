import CarrierWaveData
import Foundation

// MARK: - MacroTelemetryReporter

/// Forwards macro completion events to the registry's `run-event`
/// endpoint when the user has opted in. Gated by the
/// `macrosTelemetryOptIn` UserDefaults bool (default `false`) — no
/// network traffic happens unless the user explicitly toggles it on.
///
/// Tombstoned and locally-authored macros are skipped: telemetry only
/// makes sense for registry-installed macros.
enum MacroTelemetryReporter {
    nonisolated static let optInKey = "macrosTelemetryOptIn"

    static func reportIfOptedIn(spec: RadioMacroSpec, outcome: MacroExecutionOutcome) async {
        guard UserDefaults.standard.bool(forKey: optInKey) else {
            return
        }
        guard let slug = spec.registry?.slug else {
            return
        }
        guard let client = MacrosRegistryHolder.shared.client else {
            return
        }
        let body = RegistryRunEventBody.from(outcome: outcome)
        try? await client.reportRunEvent(slug: slug, body: body)
    }
}
