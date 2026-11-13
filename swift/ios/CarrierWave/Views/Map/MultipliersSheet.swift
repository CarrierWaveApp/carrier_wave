import SwiftUI

// MARK: - MultipliersSheet

/// Auto-flagged list of multiplier locations found from the overlapping
/// boundary overlays in view. Tapping a row recenters the map on it.
struct MultipliersSheet: View {
    // MARK: Internal

    let candidates: [MultiplierCandidate]
    let isComputing: Bool
    let onSelect: (MultiplierCandidate) -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Multipliers")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @ViewBuilder private var content: some View {
        if isComputing {
            ProgressView("Scanning overlaps…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if candidates.isEmpty {
            emptyState
        } else {
            List {
                Section {
                    ForEach(candidates) { candidate in
                        Button {
                            onSelect(candidate)
                            dismiss()
                        } label: {
                            MultiplierRow(candidate: candidate)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text(
                        "Found by overlap of the layers in view. Zoom in for counties and SOTA zones."
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rosette")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No multipliers in view")
                .font(.headline)
            Text(
                "Turn on POTA, SOTA Zones, WWFF, or Counties and zoom in to flag 2-fers and county-line spots."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - MultiplierRow

private struct MultiplierRow: View {
    let candidate: MultiplierCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(candidate.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(candidate.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(candidate.kinds, id: \.self) { kind in
                    MultiplierBadge(kind: kind)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - MultiplierBadge

private struct MultiplierBadge: View {
    // MARK: Internal

    let kind: MultiplierKind

    var body: some View {
        Label(kind.rawValue, systemImage: kind.systemImage)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    // MARK: Private

    private var tint: Color {
        switch kind {
        case .potaSota: .green
        case .potaWwff: .pink
        case .countyLine: .gray
        }
    }
}
