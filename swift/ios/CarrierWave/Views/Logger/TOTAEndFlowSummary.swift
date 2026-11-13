// Condensed TOTA score card for the end-of-session summary.
// Shows tile name, total estimate, bonus chips, and last-chance edits
// (winter override + first-ever-tile checkbox). Full ledger lives in
// SessionDetailView+TOTA.

import CarrierWaveCore
import CarrierWaveData
import SwiftUI

struct TOTAEndFlowSummary: View {
    // MARK: Internal

    let session: LoggingSession
    let qsos: [QSO]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            lastChanceControls
            footer
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .task {
            // Refresh the cached tile list so the score line above reflects the
            // session as it stands right now (track + QSOs may have grown).
            _ = TOTAEnrichmentService.recomputeTiles(for: session, qsos: qsos)
            // T3 spot snapshot in the background — failure is fine (offline).
            await TOTAEnrichmentService.refreshT3Snapshot(
                for: session,
                qsos: qsos,
                client: TOTAClient.shared
            )
        }
    }

    // MARK: Private

    private var inputs: TOTAScoringInputs {
        TOTAEnrichmentService.makeScoringInputs(for: session, qsos: qsos)
    }

    private var result: TOTAScoringResult {
        TOTAScoringEngine.score(inputs)
    }

    private var winterBinding: Binding<Bool> {
        Binding(
            get: {
                session.winterActivationOverride
                    ?? TOTAWinterDetector.isWinter(
                        latitude: session.activationLatitude,
                        date: session.startedAt
                    )
            },
            set: { newValue in
                session.winterActivationOverride = newValue
            }
        )
    }

    private var firstEverBinding: Binding<Bool> {
        Binding(
            get: { session.firstActivationOfTileEver },
            set: { session.firstActivationOfTileEver = $0 }
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "square.grid.3x3.fill")
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("TOTA")
                    .font(.subheadline.weight(.bold))
                if !session.tilesActivated.isEmpty {
                    Text(session.tilesActivated.joined(separator: ", "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f", result.total))
                    .font(.title3.weight(.bold))
                Text("est. pts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lastChanceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last chance")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Toggle(isOn: winterBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Winter activation (+20%)")
                        .font(.subheadline)
                    if session.winterActivationOverride == nil {
                        Text("Auto-detected from coords + date.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Toggle(isOn: firstEverBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("First activation of this tile, ever (+10)")
                        .font(.subheadline)
                    Text("Server is authoritative; the bonus credits if true.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        Text(
            "Pre-upload estimate. Server may add T3 + first-in-quarter bonuses on submission."
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
