import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import SwiftUI

// MARK: - PSKReporterSenderSection

/// Section in SessionDetailView showing "Who heard me?" data from PSK Reporter.
/// Fetches reception reports for the session operator's callsign on-demand.
/// Only relevant for sessions that used digital modes (FT8, FT4).
struct PSKReporterSenderSection: View {
    // MARK: Internal

    let session: LoggingSession

    var body: some View {
        if shouldShow {
            Section {
                DisclosureGroup(isExpanded: $isExpanded) {
                    innerContent
                } label: {
                    sectionLabel
                }
            }
            .task {
                if receivers.isEmpty, !hasFetched {
                    await fetchSenderSpots()
                }
            }
        }
    }

    // MARK: Private

    @State private var receivers: [ReceiverReport] = []
    @State private var isLoading = false
    @State private var isExpanded = false
    @State private var hasFetched = false
    @State private var errorMessage: String?

    /// Only show for sessions that have digital mode QSOs
    private var shouldShow: Bool {
        let digitalModes: Set = ["FT8", "FT4", "JS8", "WSPR"]
        let sessionMode = session.mode.uppercased()
        return digitalModes.contains(sessionMode)
    }

    private var sectionLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .foregroundStyle(.purple)
                .font(.caption)
            Text("Who Heard Me")
            if !receivers.isEmpty {
                Text("(\(receivers.count))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var innerContent: some View {
        if isLoading {
            HStack {
                ProgressView()
                Text("Checking PSK Reporter…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        } else if let error = errorMessage {
            errorRow(error)
        } else if receivers.isEmpty, hasFetched {
            emptyRow
        } else {
            receiverList
        }
    }

    private var receiverList: some View {
        ForEach(receivers) { receiver in
            ReceiverRow(
                receiver: receiver,
                operatorGrid: session.myGrid
            )
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .foregroundStyle(.tertiary)
            Text("No reception reports found")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await fetchSenderSpots() }
                }
                .font(.caption)
            }
        }
        .frame(minHeight: 44)
    }

    private func fetchSenderSpots() async {
        isLoading = true
        errorMessage = nil

        let client = PSKReporterClient()
        let callsign = session.stationCallsign ?? session.myCallsign

        // Look back up to 2 hours for session data
        let lookback = min(
            Int(Date().timeIntervalSince(session.startedAt)),
            7_200
        )

        do {
            let spots = try await client.fetchSenderSpots(
                callsign: callsign,
                seconds: -lookback
            )

            // Deduplicate by receiver — keep best SNR per receiver
            var bestByReceiver: [String: PSKReporterSpot] = [:]
            for spot in spots {
                let key = spot.receiverCallsign.uppercased()
                if let existing = bestByReceiver[key] {
                    if let newSNR = spot.snr, let oldSNR = existing.snr, newSNR > oldSNR {
                        bestByReceiver[key] = spot
                    }
                } else {
                    bestByReceiver[key] = spot
                }
            }

            receivers = buildReceiverReports(
                from: bestByReceiver,
                operatorGrid: session.myGrid
            )
        } catch PSKReporterError.rateLimited {
            errorMessage = "PSK Reporter rate limit (5 min). Try again shortly."
        } catch {
            errorMessage = "Could not reach PSK Reporter"
        }

        hasFetched = true
        isLoading = false
    }

    private func buildReceiverReports(
        from bestByReceiver: [String: PSKReporterSpot],
        operatorGrid: String?
    ) -> [ReceiverReport] {
        let operatorCoord = operatorGrid.flatMap {
            MaidenheadConverter.coordinate(from: $0)
        }

        return bestByReceiver.values
            .map { spot in
                let receiverCoord = spot.receiverLocator.flatMap {
                    MaidenheadConverter.coordinate(from: $0)
                }

                let distance: Double? = if let op = operatorCoord, let rx = receiverCoord {
                    CLLocation(latitude: op.latitude, longitude: op.longitude)
                        .distance(from: CLLocation(
                            latitude: rx.latitude, longitude: rx.longitude
                        ))
                } else {
                    nil
                }

                return ReceiverReport(
                    callsign: spot.receiverCallsign,
                    grid: spot.receiverLocator,
                    snr: spot.snr,
                    frequency: spot.frequencyKHz,
                    mode: spot.mode,
                    timestamp: spot.timestamp,
                    distanceMeters: distance
                )
            }
            .sorted { ($0.distanceMeters ?? 0) > ($1.distanceMeters ?? 0) }
    }
}

// MARK: - ReceiverReport

/// A station that received our signal, for display.
struct ReceiverReport: Identifiable {
    let callsign: String
    let grid: String?
    let snr: Int?
    let frequency: Double // kHz
    let mode: String
    let timestamp: Date
    let distanceMeters: Double?

    var id: String {
        callsign
    }

    var distanceKm: Double? {
        distanceMeters.map { $0 / 1_000.0 }
    }
}

// MARK: - ReceiverRow

/// Row displaying a single station that heard the operator.
private struct ReceiverRow: View {
    // MARK: Internal

    let receiver: ReceiverReport
    let operatorGrid: String?

    var body: some View {
        HStack(spacing: 10) {
            // SNR indicator
            snrIndicator

            VStack(alignment: .leading, spacing: 3) {
                // Top: callsign + mode badge
                HStack(spacing: 6) {
                    Text(receiver.callsign)
                        .font(.subheadline.weight(.semibold).monospaced())

                    Text(receiver.mode)
                        .font(.caption2)
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                // Bottom: grid + distance + time
                HStack(spacing: 8) {
                    if let grid = receiver.grid {
                        Text(grid)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    if let km = receiver.distanceKm {
                        Text(UnitFormatter.distance(km))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(receiver.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(minHeight: 44)
    }

    // MARK: Private

    private var snrIndicator: some View {
        VStack(spacing: 2) {
            if let snr = receiver.snr {
                Text("\(snr)")
                    .font(.caption.weight(.bold).monospaced())
                    .foregroundStyle(snrColor(snr))
                Text("dB")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 30)
    }

    private func snrColor(_ snr: Int) -> Color {
        switch snr {
        case 10...: .green
        case 0...: .blue
        case (-10)...: .orange
        default: .red
        }
    }
}
