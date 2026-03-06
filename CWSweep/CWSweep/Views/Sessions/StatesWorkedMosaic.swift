import SwiftUI

// MARK: - USStates

enum USStates {
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

    static func fullName(for abbreviation: String) -> String? {
        names[abbreviation.uppercased()]
    }
}

// MARK: - StatesWorkedMosaic

struct StatesWorkedMosaic: View {
    // MARK: Internal

    let stateCounts: [String: Int]
    let stateCallsigns: [String: [String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            mosaic
            legend
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("States worked mosaic, \(stateCounts.count) of 50 states")
    }

    // MARK: Private

    @State private var selectedState: String?

    @ScaledMetric(relativeTo: .caption2) private var cellHeight: CGFloat = 22

    private let columns = 10
    private let rows = 5
    private let cellSpacing: CGFloat = 2

    private var maxCount: Int {
        stateCounts.values.max() ?? 1
    }

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

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: Color.green, label: "3+")
            legendItem(color: Color.green.opacity(0.55), label: "1\u{2013}2")
            legendItem(color: Color(nsColor: .separatorColor), label: "None")
        }
        .accessibilityHidden(true)
    }

    private func mosaicCell(state: String, count: Int) -> some View {
        let isWorked = count > 0

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedState = selectedState == state ? nil : state
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(cellColor(count: count))

                if selectedState == state {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.primary.opacity(0.5), lineWidth: 1)
                }

                Text(state)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(
                        isWorked
                            ? Color(nsColor: .windowBackgroundColor)
                            : Color(nsColor: .tertiaryLabelColor)
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { selectedState == state },
                set: {
                    if !$0 {
                        selectedState = nil
                    }
                }
            ),
            arrowEdge: .top
        ) {
            statePopover(state: state, count: count)
        }
        .accessibilityLabel(cellAccessibilityLabel(state: state, count: count))
        .accessibilityHint(count > 0 ? "Tap to see callsigns" : "")
    }

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

    private func cellColor(count: Int) -> Color {
        guard count > 0 else {
            return Color(nsColor: .separatorColor)
        }
        let intensity = 0.4 + min(Double(count) / Double(max(maxCount, 1)), 1.0) * 0.6
        return Color.green.opacity(intensity)
    }

    private func cellAccessibilityLabel(state: String, count: Int) -> String {
        let name = USStates.names[state] ?? state
        if count > 0 {
            return "\(name), \(count) QSO\(count == 1 ? "" : "s")"
        }
        return "\(name), not worked"
    }
}
