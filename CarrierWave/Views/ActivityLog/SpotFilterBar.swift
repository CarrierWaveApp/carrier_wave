import SwiftUI

// MARK: - SpotFilterBar

/// Horizontal scrolling filter chips for active spot filters.
/// Only renders when there are active filters to display.
struct SpotFilterBar: View {
    // MARK: Internal

    @Binding var filters: SpotFilters

    var body: some View {
        if hasChipsToShow {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    sourceChips
                    bandChips
                    modeChips

                    if filters.hideWorked {
                        activeChip(label: "Hide Worked") {
                            filters.hideWorked = false
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: Private

    private var hasChipsToShow: Bool {
        filters.hasActiveFilters
    }

    private var sourceChips: some View {
        ForEach(SpotFilters.SourceFilter.allCases, id: \.self) { source in
            if filters.sources.contains(source) {
                activeChip(label: source.label) {
                    filters.sources.remove(source)
                }
            }
        }
    }

    private var bandChips: some View {
        ForEach(filters.bands.sorted(), id: \.self) { band in
            activeChip(label: band) {
                filters.bands.remove(band)
            }
        }
    }

    private var modeChips: some View {
        ForEach(filters.modes.sorted(), id: \.self) { mode in
            activeChip(label: mode) {
                filters.modes.remove(mode)
            }
        }
    }

    private func activeChip(label: String, onRemove: @escaping () -> Void) -> some View {
        Button {
            onRemove()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.15))
            .clipShape(Capsule())
        }
        .accessibilityLabel("Remove \(label) filter")
    }
}
