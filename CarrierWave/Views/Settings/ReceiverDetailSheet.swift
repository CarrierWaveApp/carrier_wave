import CarrierWaveCore
import SwiftUI

// MARK: - ReceiverDetailSheet

/// Detail sheet showing full receiver info with favorite toggle.
struct ReceiverDetailSheet: View {
    // MARK: Internal

    let receiver: KiwiSDRReceiver
    let enrichment: KiwiSDRStatusFetcher.ReceiverStatus?
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        NavigationStack {
            List {
                headerSection
                receiverInfoSection
                antennaSection
            }
            .navigationTitle(receiver.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private var parsed: ParsedAntenna? {
        enrichment?.parsedAntenna ?? receiver.parsedAntenna
    }

    private var headerSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(receiver.name)
                        .font(.headline)
                    Text(receiver.location)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let dist = receiver.formattedDistance {
                        Text(dist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onToggleFavorite) {
                    Image(
                        systemName: isFavorite
                            ? "star.fill" : "star"
                    )
                    .font(.title2)
                    .foregroundStyle(
                        isFavorite ? .yellow : .secondary
                    )
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    isFavorite
                        ? "Remove from favorites" : "Add to favorites"
                )
            }
        }
    }

    private var receiverInfoSection: some View {
        Section("Receiver") {
            LabeledContent("Host", value: receiver.host)
            LabeledContent("Port", value: "\(receiver.port)")
            LabeledContent("Coverage", value: receiver.bands)

            if let enrichment {
                if let grid = enrichment.grid {
                    LabeledContent("Grid", value: grid)
                }
                availabilityRow(enrichment)
                if let snr = enrichment.snrHF ?? enrichment.snrAll {
                    snrRow(snr)
                }
                if let asl = enrichment.asl {
                    LabeledContent("Altitude", value: "\(asl) m")
                }
                if let uptime = enrichment.uptime {
                    LabeledContent(
                        "Uptime", value: formatUptime(uptime)
                    )
                }
                if let version = enrichment.softwareVersion {
                    LabeledContent("Software", value: version)
                }
                LabeledContent(
                    "Antenna Connected",
                    value: enrichment.antConnected ? "Yes" : "No"
                )
            }
        }
    }

    @ViewBuilder
    private var antennaSection: some View {
        if let parsed {
            Section("Antenna") {
                if let type = parsed.type {
                    LabeledContent("Type", value: type.rawValue)
                }
                if !parsed.bands.isEmpty {
                    LabeledContent(
                        "Bands",
                        value: parsed.bands.joined(separator: ", ")
                    )
                }
                if let dir = parsed.directionality {
                    LabeledContent("Direction", value: dir)
                }
                if let model = parsed.modelName {
                    LabeledContent("Model", value: model)
                }
                if !parsed.rawDescription.isEmpty {
                    LabeledContent("Raw") {
                        Text(parsed.rawDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func availabilityRow(
        _ enrichment: KiwiSDRStatusFetcher.ReceiverStatus
    ) -> some View {
        LabeledContent("Users") {
            HStack(spacing: 4) {
                Circle()
                    .fill(
                        enrichment.users < enrichment.usersMax
                            ? Color.green : Color.red
                    )
                    .frame(width: 8, height: 8)
                Text("\(enrichment.users)/\(enrichment.usersMax)")
            }
        }
    }

    private func snrRow(_ snr: Int) -> some View {
        let color: Color = snr < 15 ? .red : snr < 25 ? .yellow : .green
        return LabeledContent("SNR") {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text("\(snr)")
                    .monospacedDigit()
            }
        }
    }

    private func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        return "\(hours)h"
    }
}
