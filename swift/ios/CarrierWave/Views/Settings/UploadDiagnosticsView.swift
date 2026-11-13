import CarrierWaveCore
import SwiftUI

// MARK: - UploadDiagnosticsView

/// Detail view showing grouped upload errors with actionable guidance.
struct UploadDiagnosticsView: View {
    // MARK: Internal

    var store: UploadDiagnosticStore

    var body: some View {
        List {
            if actionRequired.isEmpty, willRetry.isEmpty {
                emptyState
            }

            if !actionRequired.isEmpty {
                Section {
                    ForEach(actionRequired, id: \.0) { category, items in
                        diagnosticRow(category: category, items: items)
                    }
                } header: {
                    Text("Needs Attention")
                }
            }

            if !willRetry.isEmpty {
                Section {
                    ForEach(willRetry, id: \.0) { category, items in
                        diagnosticRow(category: category, items: items)
                    }
                } header: {
                    Text("Will Retry Automatically")
                }
            }

            if store.hasIssues {
                Section {
                    Button("Clear All", role: .destructive) {
                        store.clearAll()
                    }
                }
            }
        }
        .navigationTitle("Sync Issues")
    }

    // MARK: Private

    private var actionRequired: [(UploadErrorCategory, [UploadErrorDiagnostic])] {
        store.groupedByCategory.filter { !$0.0.isTransient }
    }

    private var willRetry: [(UploadErrorCategory, [UploadErrorDiagnostic])] {
        store.groupedByCategory.filter(\.0.isTransient)
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("No sync issues")
                    .font(.headline)
                Text("All services are syncing successfully.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private func diagnosticRow(
        category: UploadErrorCategory,
        items: [UploadErrorDiagnostic]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Category header with icon
            Label(category.title, systemImage: category.iconName)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(category.isTransient ? Color.secondary : Color.orange)

            // Per-service breakdown
            ForEach(Array(items)) { (item: UploadErrorDiagnostic) in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.service.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(affectedText(item.affectedCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(item.guidance)
                        .font(.caption)
                        .foregroundStyle(category.isTransient ? Color.secondary : Color.blue)
                }
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 4)
    }

    private func affectedText(_ count: Int) -> String {
        switch count {
        case 0: "Download failed"
        case 1: "1 QSO affected"
        default: "\(count) QSOs affected"
        }
    }
}
