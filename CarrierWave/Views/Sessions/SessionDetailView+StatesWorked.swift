// Session Detail View - States Worked
//
// Signal Mosaic: a compact 10×5 grid of US state cells.
// Worked states glow green (intensity ∝ QSO count).
// Tap a lit cell to see callsigns worked in that state.

import SwiftUI

// MARK: - States Worked Section

extension SessionDetailView {
    @ViewBuilder
    var statesWorkedSection: some View {
        let stateCounts = stateQSOCounts
        let workedCount = stateCounts.count
        if workedCount > 0 {
            Section {
                StatesWorkedMosaic(
                    stateCounts: stateCounts,
                    stateCallsigns: stateCallsignMap
                )
            }
        }
    }

    /// Counts of QSOs per US state abbreviation
    private var stateQSOCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for qso in displayQSOs {
            guard let state = qso.state?.uppercased().trimmingCharacters(
                in: .whitespaces
            ), USStates.abbreviations.contains(state) else {
                continue
            }
            counts[state, default: 0] += 1
        }
        return counts
    }

    /// Callsigns grouped by state
    private var stateCallsignMap: [String: [String]] {
        var map: [String: [String]] = [:]
        for qso in displayQSOs {
            guard let state = qso.state?.uppercased().trimmingCharacters(
                in: .whitespaces
            ), USStates.abbreviations.contains(state) else {
                continue
            }
            map[state, default: []].append(qso.callsign)
        }
        return map
    }
}

// MARK: - US States Reference

enum USStates {
    /// All 50 US state abbreviations, alphabetically sorted
    static let ordered: [String] = [
        "AK", "AL", "AR", "AZ", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA", "MD",
        "ME", "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NE", "NH",
        "NJ", "NM", "NV", "NY", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VA", "VT", "WA", "WI", "WV", "WY",
    ]

    static let abbreviations: Set<String> = Set(ordered)

    static let names: [String: String] = [
        "AK": "Alaska", "AL": "Alabama", "AR": "Arkansas",
        "AZ": "Arizona", "CA": "California", "CO": "Colorado",
        "CT": "Connecticut", "DE": "Delaware", "FL": "Florida",
        "GA": "Georgia", "HI": "Hawaii", "IA": "Iowa",
        "ID": "Idaho", "IL": "Illinois", "IN": "Indiana",
        "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
        "MA": "Massachusetts", "MD": "Maryland", "ME": "Maine",
        "MI": "Michigan", "MN": "Minnesota", "MO": "Missouri",
        "MS": "Mississippi", "MT": "Montana", "NC": "North Carolina",
        "ND": "North Dakota", "NE": "Nebraska", "NH": "New Hampshire",
        "NJ": "New Jersey", "NM": "New Mexico", "NV": "Nevada",
        "NY": "New York", "OH": "Ohio", "OK": "Oklahoma",
        "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island",
        "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee",
        "TX": "Texas", "UT": "Utah", "VA": "Virginia",
        "VT": "Vermont", "WA": "Washington", "WI": "Wisconsin",
        "WV": "West Virginia", "WY": "Wyoming",
    ]
}

// MARK: - StatesWorkedMosaic

struct StatesWorkedMosaic: View {
    let stateCounts: [String: Int]
    let stateCallsigns: [String: [String]]

    @State private var selectedState: String?

    private let columns = 10
    private let rows = 5
    private let cellSpacing: CGFloat = 2

    @ScaledMetric(relativeTo: .caption2) private var cellHeight: CGFloat = 22

    private var maxCount: Int {
        stateCounts.values.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            mosaic
            legend
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "States worked mosaic, \(stateCounts.count) of 50 states"
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("States Worked", systemImage: "map.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(stateCounts.count)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.green) +
                Text(" / 50")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Mosaic Grid

    private var mosaic: some View {
        VStack(spacing: cellSpacing) {
            ForEach(0 ..< rows, id: \.self) { row in
                HStack(spacing: cellSpacing) {
                    ForEach(0 ..< columns, id: \.self) { col in
                        let index = row * columns + col
                        let state = USStates.ordered[index]
                        let count = stateCounts[state] ?? 0
                        mosaicCell(state: state, count: count)
                    }
                }
            }
        }
    }

    private func mosaicCell(state: String, count: Int) -> some View {
        let isSelected = selectedState == state
        let isWorked = count > 0

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedState = selectedState == state ? nil : state
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(cellColor(count: count))

                if isSelected {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(
                            Color(.label).opacity(0.5),
                            lineWidth: 1
                        )
                }

                Text(state)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(
                        isWorked
                            ? Color(.systemBackground)
                            : Color(.tertiaryLabel)
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { selectedState == state },
                set: { if !$0 { selectedState = nil } }
            ),
            arrowEdge: .top
        ) {
            statePopover(state: state, count: count)
        }
        .accessibilityLabel(cellAccessibilityLabel(state: state, count: count))
        .accessibilityHint(count > 0 ? "Tap to see callsigns" : "")
    }

    private func cellColor(count: Int) -> Color {
        guard count > 0 else {
            return Color(.systemGray5)
        }
        let intensity = 0.4 + min(
            Double(count) / Double(max(maxCount, 1)), 1.0
        ) * 0.6
        return Color.green.opacity(intensity)
    }

    // MARK: - Popover

    private func statePopover(state: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(state)
                    .font(.headline.monospaced())
                if let name = USStates.names[state] {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("\(count) QSO\(count == 1 ? "" : "s")")
                .font(.subheadline.weight(.medium))

            if let callsigns = stateCallsigns[state] {
                let unique = Array(Set(callsigns)).sorted()
                Text(unique.joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: Color.green, label: "3+")
            legendItem(
                color: Color.green.opacity(0.55), label: "1\u{2013}2"
            )
            legendItem(color: Color(.systemGray5), label: "None")
        }
        .accessibilityHidden(true)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Accessibility

    private func cellAccessibilityLabel(
        state: String, count: Int
    ) -> String {
        let name = USStates.names[state] ?? state
        if count > 0 {
            return "\(name), \(count) QSO\(count == 1 ? "" : "s")"
        }
        return "\(name), not worked"
    }
}
