import CarrierWaveData
import SwiftUI

// MARK: - SCULAN10DebugView

/// Diagnostic view shown under the SCU-LAN10 connection row while a Yaesu
/// network adapter is connected. Surfaces per-UDP-channel packet counters
/// and the waterfall pipeline so the user can tell at a glance which leg of
/// the chain is silent — radio scope off, NAT blocking a port, packets
/// arriving but not parsing, or the renderer not receiving lines.
struct SCULAN10DebugView: View {
    // MARK: Internal

    let stats: SCULAN10DebugStats
    let store: WaterfallStore
    let pendingLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            channelsTable
            Divider()
            pipelineRow
        }
        .padding(8)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .font(.caption)
    }

    // MARK: Private

    /// Channel rows in the order they're displayed.
    private var rows: [ChannelRow] {
        [
            ChannelRow(
                name: "Control",
                kind: .alwaysExpected,
                received: stats.controlReceived,
                sent: nil,
                errors: nil,
                hint: "Keepalives + status. Should always tick up."
            ),
            ChannelRow(
                name: "CAT",
                kind: .alwaysExpected,
                received: stats.catReceived,
                sent: stats.catSent,
                errors: stats.catSendErrors,
                hint: "Radio CAT command/response traffic."
            ),
            ChannelRow(
                name: "Scope",
                kind: .silentMeansProblem(
                    "Radio's scope display is off, or UDP "
                        + "\(scopePortHint) is blocked."
                ),
                received: stats.scopeReceived,
                sent: nil,
                errors: nil,
                hint: "Spectrum frames from the radio. Drives the waterfall."
            ),
            ChannelRow(
                name: "Audio",
                kind: .optional,
                received: stats.audioReceived,
                sent: nil,
                errors: nil,
                hint: "Audio stream. Only flows when audio is enabled."
            ),
        ]
    }

    private var scopePortHint: String {
        // Scope channel is always controlPort + 3; default control is 50000.
        // Surfacing the literal port helps users debug NAT/firewall.
        "50003"
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: store.isReceiving ? "waveform" : "waveform.slash")
                .foregroundStyle(store.isReceiving ? .green : .secondary)
            Text(store.isReceiving
                ? "Receiving spectrum from \(store.source.label)"
                : "Not receiving spectrum yet")
                .fontWeight(.medium)
        }
    }

    private var channelsTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("Channel")
                Text("Received").gridColumnAlignment(.trailing)
                Text("Sent").gridColumnAlignment(.trailing)
                Text("Errors").gridColumnAlignment(.trailing)
                Text("")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            ForEach(rows) { row in
                GridRow {
                    Text(row.name)
                        .fontWeight(row.isAlerting ? .semibold : .regular)
                        .foregroundStyle(row.isAlerting ? .orange : .primary)
                    Text(numericLabel(row.received))
                        .monospacedDigit()
                        .foregroundStyle(row.isAlerting ? .orange : .primary)
                    Text(row.sent.map(numericLabel) ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(row.errors.map(numericLabel) ?? "—")
                        .monospacedDigit()
                        .foregroundStyle((row.errors ?? 0) > 0 ? .red : .secondary)
                    if row.isAlerting, let problem = row.alertText {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.orange)
                            .font(.caption2)
                    } else {
                        Text(row.hint)
                            .foregroundStyle(.tertiary)
                            .font(.caption2)
                    }
                }
            }
        }
    }

    private var pipelineRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Waterfall pipeline")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                pipelineStage(
                    label: "Buffered",
                    value: "\(pendingLines) lines"
                )
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                pipelineStage(
                    label: "On screen",
                    value: "\(store.magnitudes.count) lines × \(store.activeBinCount) bins"
                )
            }
        }
    }

    private func pipelineStage(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .monospacedDigit()
        }
    }

    private func numericLabel(_ value: Int) -> String {
        value.formatted(.number)
    }
}

// MARK: - ChannelRow

private struct ChannelRow: Identifiable {
    enum Kind {
        /// Channel is expected to always have packets when connected.
        /// Zero counts trigger an alert with the supplied explanation.
        case alwaysExpected
        /// Channel only flows when actively in use (e.g. audio when
        /// audio streaming is on); zero is fine.
        case optional
        /// Channel's silence indicates a likely diagnosis worth showing.
        case silentMeansProblem(String)
    }

    let name: String
    let kind: Kind
    let received: Int
    let sent: Int?
    let errors: Int?
    let hint: String

    var id: String {
        name
    }

    var isAlerting: Bool {
        switch kind {
        case .alwaysExpected: received == 0
        case .optional: false
        case .silentMeansProblem: received <= 1
        }
    }

    var alertText: String? {
        switch kind {
        case .alwaysExpected: received == 0 ? "No packets — connection may be stale" : nil
        case .optional: nil
        case let .silentMeansProblem(reason): received <= 1 ? reason : nil
        }
    }
}
