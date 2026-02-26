import SwiftData
import SwiftUI

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
        }
        .sheet(isPresented: $showingCustomize) {
            BragSheetCustomizeView(bragStats: bragStats)
        }
        .task {
            bragStats.compute(from: modelContext.container)
        }
    }

    // MARK: Private

    @State private var showingCustomize = false

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
}
