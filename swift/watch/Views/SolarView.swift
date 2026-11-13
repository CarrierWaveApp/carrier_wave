import SwiftUI

/// Solar conditions page showing K-index, A-index, SFI gauges and propagation rating.
struct SolarView: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding()
            } else if let solar {
                VStack(spacing: 8) {
                    headerRow(solar)
                    gaugeRow(solar)
                    updatedRow(solar)
                }
                .padding(.horizontal, 4)
            } else {
                noDataView
            }
        }
        .task { await loadSolar() }
    }

    // MARK: Private

    @State private var solar: WatchSolarSnapshot?
    @State private var isLoading = false

    // MARK: - No data

    private var noDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "sun.max.trianglebadge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Solar Data")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Check network connection")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    // MARK: - Header

    private func headerRow(_ solar: WatchSolarSnapshot) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.max.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
            Text("Solar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let rating = solar.propagationRating {
                Text(rating)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ratingColor(rating))
            }
        }
    }

    // MARK: - Gauges

    private func gaugeRow(_ solar: WatchSolarSnapshot) -> some View {
        HStack(spacing: 0) {
            if let k = solar.kIndex {
                solarGauge(
                    label: "K",
                    value: String(format: "%.0f", k),
                    level: kLevel(k),
                    color: kColor(k)
                )
            }

            if let aIdx = solar.aIndex {
                Spacer()
                solarGauge(
                    label: "A",
                    value: "\(aIdx)",
                    level: aLevel(aIdx),
                    color: aColor(aIdx)
                )
            }

            if let sfi = solar.solarFlux {
                Spacer()
                solarGauge(
                    label: "SFI",
                    value: "\(Int(sfi))",
                    level: sfiLevel(sfi),
                    color: sfiColor(sfi)
                )
            }
        }
    }

    private func solarGauge(
        label: String, value: String, level: Int, color: Color
    ) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: Double(level) / 5.0)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(x: -1, y: 1)
                Text(value)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            .frame(width: 36, height: 36)

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Updated timestamp

    private func updatedRow(_ solar: WatchSolarSnapshot) -> some View {
        Text("Updated \(solar.updatedAt, style: .relative) ago")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }

    private func loadSolar() async {
        // Try App Group first (fast)
        if let cached = SharedDataReader.readSolar() {
            solar = cached
            return
        }

        // Fetch directly from network
        isLoading = true
        solar = await WatchNetworkService.fetchSolar()
        isLoading = false
    }

    // MARK: - Propagation level helpers

    private func kLevel(_ k: Double) -> Int {
        switch k {
        case ..<2: 5
        case ..<3: 4
        case ..<4: 3
        case ..<5: 2
        default: 1
        }
    }

    private func kColor(_ k: Double) -> Color {
        switch k {
        case ..<3: .green
        case ..<4: .yellow
        case ..<5: .orange
        default: .red
        }
    }

    private func aLevel(_ aIndex: Int) -> Int {
        switch aIndex {
        case ..<7: 5
        case ..<15: 4
        case ..<30: 3
        case ..<50: 2
        default: 1
        }
    }

    private func aColor(_ aIndex: Int) -> Color {
        switch aIndex {
        case ..<15: .green
        case ..<30: .yellow
        case ..<50: .orange
        default: .red
        }
    }

    private func sfiLevel(_ sfi: Double) -> Int {
        switch sfi {
        case ..<70: 1
        case ..<90: 2
        case ..<120: 3
        case ..<200: 4
        default: 5
        }
    }

    private func sfiColor(_ sfi: Double) -> Color {
        switch sfi {
        case ..<70: .red
        case ..<90: .orange
        case ..<120: .yellow
        default: .green
        }
    }

    private func ratingColor(_ rating: String) -> Color {
        switch rating {
        case "Excellent",
             "Good": .green
        case "Fair": .yellow
        case "Poor": .orange
        default: .red
        }
    }
}
