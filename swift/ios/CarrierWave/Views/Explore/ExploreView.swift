import CarrierWaveData
import SwiftUI

// MARK: - ExploreView

/// Feature gallery — the single "front door" for discovering what the app
/// can do (docs/ux-north-star.md). One curated card per marquee feature:
/// a 5-second pitch, a "find it" hint, and an inline enable toggle for
/// hidden experiments. Reached from the More tab and the Getting Started
/// card; the What's New sheet should deep-link here for new features.
struct ExploreView: View {
    var body: some View {
        List {
            Section {
                ForEach(ExploreFeature.readyToUse) { feature in
                    ExploreFeatureRow(feature: feature)
                }
            } header: {
                Text("Ready to Use")
            } footer: {
                Text("These are on for everyone — the hint shows where each one lives.")
            }

            Section {
                ForEach(ExploreFeature.optIn) { feature in
                    ExploreFeatureRow(feature: feature)
                }
            } header: {
                Text("Worth Trying (Opt In)")
            } footer: {
                Text(
                    "Early features — flip one on to try it. The full list, "
                        + "including rougher alphas, lives in Experiments."
                )
            }

            Section {
                NavigationLink {
                    ExperimentsView()
                } label: {
                    Text("All Experiments")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Explore")
    }
}

// MARK: - ExploreFeatureRow

/// One feature card: tinted icon, title + maturity badge, pitch, find-it
/// hint, and — for hidden experiments — an inline enable toggle.
private struct ExploreFeatureRow: View {
    // MARK: Internal

    let feature: ExploreFeature

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.icon)
                .font(.title3)
                .foregroundStyle(feature.tint)
                .frame(width: 32, height: 32)
                .background(feature.tint.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(feature.title)
                        .font(.subheadline.weight(.semibold))
                    if let experiment = feature.experiment {
                        ExperimentalBadge(feature: experiment)
                    }
                }

                Text(feature.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text(feature.whereToFind)
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            if needsOptIn {
                Toggle("", isOn: enableBinding)
                    .labelsHidden()
                    .accessibilityLabel("Enable \(feature.title)")
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Private

    /// Local mirror so the toggle updates immediately — `ExperimentalFeature`
    /// is UserDefaults-backed and not observable.
    @State private var enabledOverride: Bool?

    private var isEnabled: Bool {
        guard let experiment = feature.experiment else {
            return true
        }
        return enabledOverride ?? ExperimentalFeature.isEnabled(experiment)
    }

    private var needsOptIn: Bool {
        feature.experiment?.isHiddenByDefault == true
    }

    private var enableBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                guard let experiment = feature.experiment else {
                    return
                }
                ExperimentalFeature.setEnabled(experiment, enabled: newValue)
                enabledOverride = newValue
            }
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ExploreView()
    }
}
