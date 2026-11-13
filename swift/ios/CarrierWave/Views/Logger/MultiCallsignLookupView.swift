import SwiftUI

// MARK: - MultiCallsignLookupView

/// Displays compact chips for multiple looked-up callsigns with an expandable detail card.
/// Tap a chip to see its full LoggerCallsignCard below.
struct MultiCallsignLookupView: View {
    // MARK: Internal

    let lookupStates: [MultiCallsignLookupState]
    @Binding var selectedIndex: Int

    var myGrid: String?

    var body: some View {
        VStack(spacing: 8) {
            chipRow
            expandedCard
        }
        .onChange(of: lookupStates.count) {
            // Clamp selection when a callsign is removed
            if selectedIndex >= lookupStates.count {
                selectedIndex = max(0, lookupStates.count - 1)
            }
        }
    }

    // MARK: Private

    private var chipRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(lookupStates.enumerated()), id: \.offset) { index, state in
                callsignChip(state: state, isSelected: index == selectedIndex)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedIndex = index
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var expandedCard: some View {
        let safeIndex = min(selectedIndex, lookupStates.count - 1)
        let state = lookupStates[max(0, safeIndex)]

        switch state {
        case .loading:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Looking up \(state.callsign)...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        case let .found(info, previousQSOCount):
            LoggerCallsignCard(
                info: info,
                previousQSOCount: previousQSOCount,
                myGrid: myGrid
            )
            .transition(.opacity)

        case .notFound:
            notFoundCard(callsign: state.callsign)

        case let .error(_, lookupError):
            errorCard(callsign: state.callsign, error: lookupError)
        }
    }

    private func callsignChip(
        state: MultiCallsignLookupState,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 4) {
            if state.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }

            Text(state.callsign)
                .font(.caption.monospaced().weight(.semibold))

            if let info = state.info,
               let flag = CallsignFlagHelper.countryFlag(for: info.callsign)
            {
                Text(flag)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.2)
                : Color(.tertiarySystemGroupedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.clear,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(chipAccessibilityLabel(for: state))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func notFoundCard(callsign: String) -> some View {
        HStack(spacing: 6) {
            Text(callsign)
                .font(.headline.weight(.bold).monospaced())
            Spacer()
            Text("Not found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func errorCard(
        callsign: String,
        error: CallsignLookupError
    ) -> some View {
        HStack(spacing: 6) {
            Text(callsign)
                .font(.headline.weight(.bold).monospaced())
            Spacer()
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func chipAccessibilityLabel(
        for state: MultiCallsignLookupState
    ) -> String {
        switch state {
        case let .loading(callsign):
            return "\(callsign), loading"
        case let .found(info, _):
            let country = info.country ?? ""
            return "\(info.callsign), \(country), tap to expand details"
        case let .notFound(callsign):
            return "\(callsign), not found"
        case let .error(callsign, _):
            return "\(callsign), lookup error"
        }
    }
}
