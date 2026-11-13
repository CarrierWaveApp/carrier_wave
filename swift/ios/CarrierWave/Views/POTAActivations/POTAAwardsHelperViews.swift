// POTA Awards Helper Views
//
// Reusable stat pill, progress row, and completed row components
// used by POTAAwardsView.

import SwiftUI

// MARK: - POTAAwardStatPill

struct POTAAwardStatPill: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    var category: POTAAwardCategory?
    var numericValue: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .potaAwardInfoMenu(category: category, value: numericValue)
    }
}

// MARK: - POTAAwardProgressRow

struct POTAAwardProgressRow: View {
    let title: String
    let current: Int
    let target: Int
    let currentTier: String?
    let nextTier: String
    var category: POTAAwardCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(current)/\(target)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(
                value: min(Double(current) / Double(target), 1.0)
            )
            .tint(current >= target ? .green : .blue)

            HStack {
                if let tier = currentTier {
                    Text(tier)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Text("Next: \(nextTier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .potaAwardInfoMenu(category: category, value: current)
    }
}

// MARK: - POTAAwardCompletedRow

struct POTAAwardCompletedRow: View {
    let title: String
    let value: Int
    let tier: String
    var category: POTAAwardCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(value)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.green)
            }
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text(tier)
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .potaAwardInfoMenu(category: category, value: value)
    }
}

// MARK: - POTAAwardsProgressKey

private struct POTAAwardsProgressKey: EnvironmentKey {
    static let defaultValue: POTAAwardsProgress? = nil
}

extension EnvironmentValues {
    var potaAwardsProgress: POTAAwardsProgress? {
        get { self[POTAAwardsProgressKey.self] }
        set { self[POTAAwardsProgressKey.self] = newValue }
    }
}

// MARK: - POTA Award Info Context Menu

extension View {
    @ViewBuilder
    func potaAwardInfoMenu(
        category: POTAAwardCategory?,
        value: Int = 0
    ) -> some View {
        if let category {
            modifier(POTAAwardInfoModifier(
                category: category, value: value
            ))
        } else {
            self
        }
    }
}

// MARK: - POTAAwardInfoModifier

struct POTAAwardInfoModifier: ViewModifier {
    // MARK: Internal

    let category: POTAAwardCategory
    var value: Int = 0

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    showingInfo = true
                } label: {
                    Label("What's This?", systemImage: "info.circle")
                }

                Button {
                    showingReport = true
                } label: {
                    Label(
                        "Report Inaccuracy",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
            .sheet(isPresented: $showingInfo) {
                StatExplanationSheet(
                    methodology: category.detailedExplanation,
                    filterPipeline: pipeline
                )
            }
            .sheet(isPresented: $showingReport) {
                ReportInaccuracyView(
                    category: nil,
                    categoryTitle: category.detailedExplanation.title,
                    identifier: nil,
                    computedValue: value
                )
            }
    }

    // MARK: Private

    @Environment(\.potaAwardsProgress) private var progress
    @State private var showingInfo = false
    @State private var showingReport = false

    private var pipeline: [StatFilterStage] {
        guard let progress else {
            return []
        }
        return category.filterPipeline(from: progress)
    }
}
