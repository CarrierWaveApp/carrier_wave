import CarrierWaveCore
import SwiftUI

/// Contester layout: Entry bar + band map + recent QSOs + rate display
struct ContesterLayout: View {
    // MARK: Internal

    let radioManager: RadioManager

    var body: some View {
        VStack(spacing: 0) {
            if contestManager.isActive {
                // Entry bar at top
                ParsedEntryView(radioManager: radioManager)
                    .padding()

                Divider()

                HSplitView {
                    // Left: Recent QSOs + rate
                    VStack(spacing: 0) {
                        QSOLogTableView(showContestColumns: true)

                        Divider()

                        // Rate display bar
                        HStack {
                            // Operating mode indicator
                            Button {
                                contestManager.toggleOperatingMode()
                            } label: {
                                Text(contestManager.operatingMode == .cq ? "CQ" : "S&P")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        contestManager.operatingMode == .cq ? Color.blue : Color.orange,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                "Operating mode: \(contestManager.operatingMode == .cq ? "CQ" : "Search and Pounce")"
                            )
                            .accessibilityHint("Toggle between CQ and S&P modes")
                            .help("Toggle CQ/S&P (Ctrl+S)")

                            Divider()
                                .frame(height: 30)

                            VStack(alignment: .leading) {
                                Text("QSOs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(contestManager.score.totalQSOs)")
                                    .font(.title3.monospacedDigit())
                            }
                            .accessibilityElement(children: .combine)

                            Divider()
                                .frame(height: 30)

                            VStack(alignment: .leading) {
                                Text("Rate")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(Int(currentRate)) /hr")
                                    .font(.title3.monospacedDigit())
                            }
                            .accessibilityElement(children: .combine)

                            Divider()
                                .frame(height: 30)

                            VStack(alignment: .leading) {
                                Text("Mults")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(contestManager.score.multiplierCount)")
                                    .font(.title3.monospacedDigit())
                            }
                            .accessibilityElement(children: .combine)

                            Divider()
                                .frame(height: 30)

                            VStack(alignment: .leading) {
                                Text("Score")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(formattedScore)
                                    .font(.title3.monospacedDigit().bold())
                            }
                            .accessibilityElement(children: .combine)

                            if contestManager.score.dupeCount > 0 {
                                Divider()
                                    .frame(height: 30)

                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                    VStack(alignment: .leading) {
                                        Text("Dupes")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(contestManager.score.dupeCount)")
                                            .font(.title3.monospacedDigit())
                                            .foregroundStyle(.red)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }

                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.bar)
                    }
                    .frame(minWidth: 300)

                    // Right: Band map
                    BandMapView()
                        .frame(minWidth: 200)
                }
            } else {
                // No active contest
                VStack(spacing: 0) {
                    ParsedEntryView(radioManager: radioManager)
                        .padding()

                    Divider()

                    HSplitView {
                        VStack(spacing: 0) {
                            QSOLogTableView()

                            Divider()

                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Rate")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("0 QSOs/hr")
                                        .font(.title3.monospacedDigit())
                                }

                                Divider()
                                    .frame(height: 30)

                                VStack(alignment: .leading) {
                                    Text("Score")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("0")
                                        .font(.title3.monospacedDigit())
                                }

                                Spacer()

                                Button("Start Contest...") {
                                    // Will be wired via focused value in WI-8
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(.bar)
                        }
                        .frame(minWidth: 300)

                        BandMapView()
                            .frame(minWidth: 200)
                    }
                }
            }
        }
        .task(id: contestManager.score.totalQSOs) {
            if contestManager.isActive {
                currentRate = await contestManager.rate()
            }
        }
        .onChange(of: radioManager.frequency) { _, newFreq in
            if contestManager.isActive, let band = BandUtilities.deriveBand(from: newFreq * 1_000) {
                contestManager.rememberBand(band, frequency: newFreq)
            }
        }
        .background(
            Button("") { contestManager.toggleOperatingMode() }
                .keyboardShortcut("s", modifiers: .control)
                .hidden()
                .accessibilityHidden(true)
        )
    }

    // MARK: Private

    @Environment(ContestManager.self) private var contestManager
    @State private var currentRate: Double = 0

    private var formattedScore: String {
        let score = contestManager.score.finalScore
        if score >= 1_000_000 {
            return String(format: "%.1fM", Double(score) / 1_000_000)
        } else if score >= 1_000 {
            return String(format: "%.1fK", Double(score) / 1_000)
        }
        return "\(score)"
    }
}
