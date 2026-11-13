import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ReportInaccuracyView

/// Form for reporting a stats inaccuracy. Collects user input and generates
/// a diagnostic bundle that can be shared with the developer.
struct ReportInaccuracyView: View {
    // MARK: Internal

    /// Dashboard stat category for detailed filter trace (nil for awards).
    let category: StatCategoryType?
    /// Display title for the category (used when category is nil).
    var categoryTitle: String?
    let identifier: String?
    let computedValue: Int

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    var body: some View {
        NavigationStack {
            Form {
                statSection
                userInputSection
                flaggedCallsignsSection
            }
            .navigationTitle("Report Inaccuracy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") { generateReport() }
                        .disabled(expectedValueText.isEmpty)
                }
            }
            .overlay {
                if isGenerating {
                    reportGeneratingOverlay
                }
            }
            .sheet(item: $reportData) { data in
                ReportShareSheetView(item: data.url)
            }
        }
    }

    // MARK: Private

    @State private var expectedValueText = ""
    @State private var comment = ""
    @State private var flaggedCallsignText = ""
    @State private var isGenerating = false
    @State private var reportData: ShareableReport?

    private var displayTitle: String {
        categoryTitle ?? category?.title ?? "Unknown"
    }

    private var statSection: some View {
        Section("Statistic") {
            LabeledContent("Category", value: displayTitle)
            if let identifier {
                LabeledContent("Item", value: identifier)
            }
            LabeledContent("Current Value", value: "\(computedValue)")
        }
    }

    private var userInputSection: some View {
        Section("What do you expect?") {
            TextField("Expected value", text: $expectedValueText)
                .keyboardType(.numberPad)
            TextField("What seems wrong? (optional)", text: $comment, axis: .vertical)
                .lineLimit(3 ... 6)
        }
    }

    private var flaggedCallsignsSection: some View {
        Section {
            TextField(
                "e.g. W1ABC, K2DEF",
                text: $flaggedCallsignText,
                axis: .vertical
            )
            .lineLimit(2 ... 4)
            .autocapitalization(.allCharacters)
        } header: {
            Text("Callsigns that seem miscounted (optional)")
        } footer: {
            Text("Comma-separated. These will be traced in detail.")
        }
    }

    private var reportGeneratingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("Generating report...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func generateReport() {
        guard let expected = Int(expectedValueText) else {
            return
        }
        isGenerating = true

        let flagged = parseFlaggedCallsigns()
        let userReport = UserReport(
            category: displayTitle,
            identifier: identifier,
            computedValue: computedValue,
            expectedValue: expected,
            flaggedCallsigns: flagged,
            comment: comment
        )

        Task {
            await buildAndShareReport(
                userReport: userReport,
                container: modelContext.container
            )
        }
    }

    private func buildAndShareReport(
        userReport: UserReport,
        container: ModelContainer
    ) async {
        do {
            let builder = StatsReportBuilder()
            // Use .bands as fallback for general trace when no
            // specific dashboard category applies (e.g., awards).
            let traceCategory = category ?? .bands
            let report = try await builder.buildReport(
                container: container,
                userReport: userReport,
                category: traceCategory
            )
            let jsonData = try StatsReportBuilder.exportJSON(report: report)
            let url = try writeToTempFile(jsonData)

            await MainActor.run {
                isGenerating = false
                reportData = ShareableReport(url: url)
            }
        } catch {
            await MainActor.run {
                isGenerating = false
            }
        }
    }

    private func parseFlaggedCallsigns() -> [String] {
        flaggedCallsignText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
    }

    private func writeToTempFile(_ data: Data) throws -> URL {
        let fileName = "stats-report-\(dateStamp()).json"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        try data.write(to: url)
        return url
    }

    private func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}

// MARK: - ShareableReport

/// Identifiable wrapper for share sheet presentation.
private struct ShareableReport: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - ReportShareSheetView

/// UIActivityViewController wrapper for sharing report files.
private struct ReportShareSheetView: UIViewControllerRepresentable {
    let item: URL

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [item], applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
