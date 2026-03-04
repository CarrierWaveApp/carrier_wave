import SwiftUI

// MARK: - LoggerTourOverlay + Mock Content Helpers

extension LoggerTourOverlay {
    var mockCommands: [MockCommand] {
        [
            MockCommand(name: "FREQ", icon: "antenna.radiowaves.left.and.right", desc: "Set frequency"),
            MockCommand(name: "MODE", icon: "waveform", desc: "Change mode"),
            MockCommand(name: "SPOT", icon: "mappin.and.ellipse", desc: "Self-spot to POTA"),
            MockCommand(name: "RBN", icon: "dot.radiowaves.up.forward", desc: "Reverse Beacon Network"),
            MockCommand(name: "HUNT", icon: "binoculars", desc: "Find activator spots"),
            MockCommand(name: "MAP", icon: "map", desc: "Session QSO map"),
            MockCommand(name: "SOLAR", icon: "sun.max", desc: "Solar conditions"),
            MockCommand(name: "SDR", icon: "radio", desc: "WebSDR recording"),
        ]
    }

    // MARK: - Mock SDR Pill

    var mockSDRPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "waveform")
                .font(.system(size: 8))
                .foregroundStyle(.red)
            Text("SDR")
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.red.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Mock Command Help

    var mockCommandHelpOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(mockCommands, id: \.name) { cmd in
                HStack(spacing: 10) {
                    Image(systemName: cmd.icon)
                        .font(.caption)
                        .frame(width: 20)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cmd.name)
                            .font(.caption.weight(.semibold).monospaced())
                        Text(cmd.desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Mock SDR Banner

    var mockSDRBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)

            Text("Recording from KiwiSDR Tucson")
                .font(.subheadline)

            Spacer()

            Text("0:01:47")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Mock QSO List

    @ViewBuilder
    var mockQSOList: some View {
        let qsos = tourManager.visibleQSOs
        if !qsos.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(qsos.enumerated()), id: \.element.id) { index, qso in
                    mockQSORow(qso)
                    if index < qsos.count - 1 {
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    func mockCapsule(
        _ text: String,
        color: Color,
        monospaced: Bool = false
    ) -> some View {
        Text(text)
            .font(monospaced ? .caption.monospaced().weight(.medium) : .caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
    }

    func mockQSORow(_ qso: MockTourQSO) -> some View {
        HStack(spacing: 10) {
            // QSO number
            Text("#\(tourManager.visibleQSOs.firstIndex(where: { $0.id == qso.id }).map { $0 + 1 } ?? 0)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(qso.callsign)
                        .font(.subheadline.weight(.semibold).monospaced())

                    if qso.isDuplicate {
                        Text("DUPE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.orange)
                            .clipShape(Capsule())
                    }

                    if qso.isParkToPark, let park = qso.theirPark {
                        Text("P2P \(park)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text("\(qso.rstSent)/\(qso.rstReceived)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(qso.qth)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(qso.grid)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(qso.time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
