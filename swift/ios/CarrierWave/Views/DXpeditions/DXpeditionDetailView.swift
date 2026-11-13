import CarrierWaveCore
import SwiftUI

// MARK: - DXpeditionDetailView

/// Detail view showing full day grid, status, and live RBN spots for a DXpedition.
struct DXpeditionDetailView: View {
    // MARK: Internal

    let expedition: Ham365DXpedition
    let daysInMonth: Int

    var body: some View {
        List {
            headerSection
            if expedition.isOnAir {
                liveSpotsSection
            }
            calendarSection
            infoSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(expedition.callsign)
        .task {
            if expedition.isOnAir {
                await fetchSpots()
            }
        }
        .refreshable {
            if expedition.isOnAir {
                await fetchSpots()
            }
        }
    }

    // MARK: Private

    @State private var spots: [RBNSpot] = []
    @State private var isSpotsLoading = false
    @State private var spotsError: String?

    private let rbnClient = RBNClient()

    private var headerSection: some View {
        Section {
            VStack(alignment: .center, spacing: 12) {
                Text(expedition.callsign)
                    .font(.largeTitle.monospaced().bold())

                Text(expedition.entity)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if expedition.isOnAir {
                    Label("On Air Now", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.green, in: Capsule())
                } else if expedition.isActiveToday {
                    Label("Active Today", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var calendarSection: some View {
        Section("Activity Calendar") {
            dayGrid
                .padding(.vertical, 8)
        }
    }

    private var dayGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
            spacing: 4
        ) {
            ForEach(1 ... daysInMonth, id: \.self) { day in
                let isActive = expedition.activeDays.contains(day)
                Text("\(day)")
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(
                        isActive ? Color.orange.opacity(0.8) : Color(.systemGray6),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .foregroundStyle(isActive ? .white : .secondary)
            }
        }
    }

    private var infoSection: some View {
        Section("Details") {
            LabeledContent("Date Range", value: expedition.dateRange)
            LabeledContent("Active Days", value: "\(expedition.activeDays.count)")
            LabeledContent("On Air", value: expedition.isOnAir ? "Yes" : "No")
        }
    }

    private var liveSpotsSection: some View {
        Section {
            if isSpotsLoading, spots.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading spots…")
                    Spacer()
                }
            } else if let spotsError {
                Label(spotsError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if spots.isEmpty {
                Text("No recent RBN spots")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                bandModeSummary
                ForEach(spots.prefix(15)) { spot in
                    spotRow(spot)
                }
            }
        } header: {
            HStack {
                Text("Live Spots")
                Spacer()
                Text("\(spots.count) reports")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Band/mode summary pills at the top of the spots section.
    private var bandModeSummary: some View {
        let grouped = DXpeditionSpotGrouper.group(spots)
        return FlowLayout(spacing: 6) {
            ForEach(grouped, id: \.label) { entry in
                Text(entry.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Color.green.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
        }
        .padding(.vertical, 4)
    }

    private func spotRow(_ spot: RBNSpot) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.formattedFrequency)
                    .font(.subheadline.monospacedDigit())
                Text(spot.mode)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.green)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text("SNR \(spot.snr)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let wpm = spot.wpm {
                        Text("\(wpm) WPM")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(spot.spotter)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(spot.timeAgo)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func fetchSpots() async {
        isSpotsLoading = true
        spotsError = nil
        do {
            spots = try await rbnClient.spots(
                forVariants: expedition.searchCallsigns,
                hours: 1, limit: 50
            )
        } catch {
            spotsError = error.localizedDescription
        }
        isSpotsLoading = false
    }
}
