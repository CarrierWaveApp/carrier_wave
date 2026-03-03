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

                    if filters.clubOnly {
                        activeChip(label: "Club Only") {
                            filters.clubOnly = false
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .overlay(alignment: .bottom) {
                if showSourceWarning {
                    Text("At least one spot source is required")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.darkGray))
                        .clipShape(Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: Private

    @State private var showSourceWarning = false

    private var hasChipsToShow: Bool {
        filters.hasActiveFilters
    }

    private var sourceChips: some View {
        ForEach(SpotFilters.SourceFilter.allCases, id: \.self) { source in
            if filters.sources.contains(source) {
                let isLast = filters.sources.count == 1
                activeChip(label: source.label) {
                    if isLast {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSourceWarning = true
                        }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSourceWarning = false
                            }
                        }
                    } else {
                        filters.sources.remove(source)
                    }
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
            .fixedSize()
            .foregroundStyle(.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.15))
            .clipShape(Capsule())
        }
        .accessibilityLabel("Remove \(label) filter")
    }
}
