import CarrierWaveData
import SwiftData
import SwiftUI
import UIKit

// MARK: - BragSheetView

/// Full brag sheet view showing computed stats across periods with customization.
struct BragSheetView: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext
    @Bindable var bragStats: AsyncBragSheetStats

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                periodPicker

                if bragStats.isComputing, !bragStats.hasComputed {
                    loadingView
                } else if let result = bragStats.currentResult, result.qsoCount > 0 {
                    heroSection
                    statGrid
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Brag Sheet")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCustomize = true
                } label: {
                    Text("Customize")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if isGeneratingShareImage {
                    ProgressView()
                } else {
                    Button {
                        Task { await generateShareImage() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(
                        bragStats.currentResult == nil
                            || bragStats.currentResult?.qsoCount == 0
                    )
                }
            }
        }
        .sheet(isPresented: $showingCustomize) {
            BragSheetCustomizeView(bragStats: bragStats)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = renderedShareImage {
                BragShareImageSheet(image: image)
            }
        }
        .task {
            bragStats.compute(from: modelContext.container)
        }
    }

    // MARK: Private

    @AppStorage("statisticianMode") private var statisticianMode = false
    @State private var showingCustomize = false
    @State private var showingShareSheet = false
    @State private var isGeneratingShareImage = false
    @State private var renderedShareImage: UIImage?

    // MARK: - Period Picker

    private var periodPicker: some View {
        VStack(spacing: 4) {
            Picker("Period", selection: $bragStats.selectedPeriod) {
                ForEach(BragSheetPeriod.allCases) { period in
                    Text(period.shortName).tag(period)
                }
            }
            .pickerStyle(.segmented)

            Text(bragStats.selectedPeriod.periodLabel())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Computing stats...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Stats Yet")
                .font(.headline)
            Text("Make some contacts to see your brag sheet stats.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func generateShareImage() async {
        guard let result = bragStats.currentResult else {
            return
        }
        isGeneratingShareImage = true
        let period = bragStats.selectedPeriod
        let config = bragStats.configuration.config(for: period)
        let callsign = CallsignAliasService.shared.getCurrentCallsign() ?? "Me"
        let stats = statisticianData(for: period)
        let snapshots = filteredSnapshots(for: period)

        let image = await BragSheetShareRenderer.renderWithMap(
            input: .init(
                result: result,
                config: config,
                period: period,
                callsign: callsign,
                statisticianStats: stats,
                snapshots: snapshots
            )
        )

        isGeneratingShareImage = false
        renderedShareImage = image
        if image != nil {
            showingShareSheet = true
        }
    }

    private func filteredSnapshots(
        for period: BragSheetPeriod
    ) -> [BragSheetQSOSnapshot] {
        guard let snapshots = bragStats.cachedSnapshots else {
            return []
        }
        guard period != .allTime else {
            return snapshots
        }
        let dateRange = period.dateRange()
        return snapshots.filter {
            $0.timestamp >= dateRange.start && $0.timestamp <= dateRange.end
        }
    }

    private func statisticianData(
        for period: BragSheetPeriod
    ) -> BragSheetStatisticianData? {
        guard statisticianMode,
              let snapshots = bragStats.cachedSnapshots
        else {
            return nil
        }
        let dateRange = period.dateRange()
        let filtered = period == .allTime
            ? snapshots
            : snapshots.filter {
                $0.timestamp >= dateRange.start && $0.timestamp <= dateRange.end
            }
        return BragSheetStatisticianData.compute(from: filtered)
    }
}

// MARK: - BragShareImageSheet

/// Sheet showing the pre-rendered brag sheet image with a Share button.
struct BragShareImageSheet: View {
    @Environment(\.dismiss) var dismiss

    let image: UIImage

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    .padding()
            }
            .safeAreaInset(edge: .bottom) {
                ShareLink(
                    item: ShareableImage(uiImage: image),
                    preview: SharePreview(
                        "Brag Sheet", image: Image(uiImage: image)
                    )
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.bar)
            }
            .navigationTitle("Share Brag Sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
