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
                Button {
                    showingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(bragStats.currentResult == nil || bragStats.currentResult?.qsoCount == 0)
            }
        }
        .sheet(isPresented: $showingCustomize) {
            BragSheetCustomizeView(bragStats: bragStats)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let result = bragStats.currentResult {
                let config = bragStats.configuration.config(for: bragStats.selectedPeriod)
                let callsign = CallsignAliasService.shared.getCurrentCallsign() ?? "Me"
                BragShareCardSheet(
                    content: .forBragSheet(
                        result: result,
                        config: config,
                        period: bragStats.selectedPeriod,
                        callsign: callsign
                    )
                )
            }
        }
        .task {
            bragStats.compute(from: modelContext.container)
        }
    }

    // MARK: Private

    @State private var showingCustomize = false
    @State private var showingShareSheet = false

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

// MARK: - BragShareCardSheet

/// Sheet showing a preview of the brag sheet share card with a Share button.
struct BragShareCardSheet: View {
    // MARK: Internal

    @Environment(\.dismiss) var dismiss

    let content: ShareCardContent

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview") {
                    ShareCardView(content: content)
                        .scaleEffect(0.6)
                        .frame(height: 320)
                        .frame(maxWidth: .infinity)
                }

                Section {
                    Button {
                        showingShareSheet = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Share", systemImage: "square.and.arrow.up")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Share Brag Sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                BragShareSheetView(content: content)
            }
        }
    }

    // MARK: Private

    @State private var showingShareSheet = false
}

// MARK: - BragShareSheetView

struct BragShareSheetView: UIViewControllerRepresentable {
    let content: ShareCardContent

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let image = ShareCardRenderer.render(content: content) ?? UIImage()
        return UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
