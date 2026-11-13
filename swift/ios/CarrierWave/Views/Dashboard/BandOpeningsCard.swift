import CarrierWaveCore
import SwiftUI

// MARK: - BandOpeningsCard

/// Dashboard card showing current HF band propagation conditions
/// with human-readable explanations of why bands are open or closed.
struct BandOpeningsCard: View {
    // MARK: Internal

    var body: some View {
        cardContent
            .task {
                await loadData()
            }
    }

    // MARK: Private

    @State private var solarData: HamQSLSolarData?
    @State private var bandEstimates: [BandPropagation] = []
    @State private var conditionSummary: String = ""
    @State private var isLoading = true
    @State private var selectedBand: BandPropagation?

    // MARK: - Helpers

    private var currentUTCHour: Int {
        Calendar(identifier: .gregorian).component(.hour, from: Date())
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            mainContent
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var headerRow: some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            Text("Band Openings")
                .font(.headline)

            Spacer()

            if let data = solarData {
                Text(data.propagationRating)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ratingColor(data.propagationRating))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ratingColor(data.propagationRating).opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isLoading {
            loadingPlaceholder
        } else if solarData != nil {
            conditionSummaryRow
            bandQualitySection
            selectedBandExplanation
            solarIndicesRow
            timestampFooter
        } else {
            emptyState
        }
    }

    private var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("--")
                .font(.subheadline)
            HStack(spacing: 4) {
                ForEach(0 ..< 5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                        .frame(height: 36)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(0.6)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("Unable to load band conditions")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
    }

    private var conditionSummaryRow: some View {
        Text(conditionSummary)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bandQualitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Band Quality")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 8), count: 2
            )
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(bandEstimates) { band in
                    BandQualityGaugeRow(
                        bandName: band.band,
                        qualityIndex: band.quality.rawValue,
                        isSelected: selectedBand?.band == band.band,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedBand = selectedBand?.band == band.band
                                    ? nil : band
                            }
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var selectedBandExplanation: some View {
        if let selected = selectedBand,
           let data = solarData
        {
            let explanation = PropagationEstimator.bandExplanation(
                band: selected,
                kIndex: data.kIndex,
                utcHour: currentUTCHour
            )
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text("\(selected.band): \(explanation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedBand = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Dismiss band detail")
            }
            .padding(8)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var solarIndicesRow: some View {
        if let data = solarData {
            VStack(spacing: 6) {
                if let sfi = data.solarFlux {
                    SFIGaugeBar(sfi: sfi)
                }

                KIndexGaugeBar(kIndex: data.kIndex)

                if let aIndex = data.aIndex {
                    AIndexGaugeBar(aIndex: aIndex)
                }
            }
        }
    }

    @ViewBuilder
    private var timestampFooter: some View {
        if let data = solarData {
            Text(
                "Updated: \(data.timestamp.formatted(date: .omitted, time: .shortened))"
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
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

    private func loadData() async {
        let client = HamQSLClient()
        solarData = try? await client.fetchSolarData()

        if let data = solarData, let sfi = data.solarFlux {
            let utcHour = currentUTCHour
            bandEstimates = PropagationEstimator.estimate(
                sfi: sfi, kIndex: data.kIndex, utcHour: utcHour
            )
            conditionSummary = PropagationEstimator.conditionSummary(
                sfi: sfi, kIndex: data.kIndex, utcHour: utcHour
            )
        }

        isLoading = false
    }
}
