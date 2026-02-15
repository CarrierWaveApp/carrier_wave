// Activation Share Card Components
//
// Reusable component views for activation share cards.

import SwiftUI

// MARK: - ActivationShareCardHeader

struct ActivationShareCardHeader: View {
    var body: some View {
        Text("CARRIER WAVE")
            .font(.headline)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.top, 24)
            .padding(.bottom, 12)
    }
}

// MARK: - ActivationShareCardEmptyMap

struct ActivationShareCardEmptyMap: View {
    var body: some View {
        ZStack {
            Color.white.opacity(0.2)
            VStack(spacing: 8) {
                Image(systemName: "map")
                    .font(.title)
                Text("No grid data available")
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - ActivationShareCardParkInfo

struct ActivationShareCardParkInfo: View {
    let parkReference: String
    let parkName: String?
    let displayDate: String
    var title: String?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "tree.fill")
                    .font(.title3)
                Text(parkReference)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .foregroundStyle(.white)

            if let name = parkName {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .italic()
            }

            Text(displayDate)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
    }
}

// MARK: - ShareCardEquipmentItem

struct ShareCardEquipmentItem: Hashable {
    let icon: String
    let text: String
}

// MARK: - ActivationShareCardStats

struct ActivationShareCardStats: View {
    // MARK: Internal

    let qsoCount: Int
    let duration: String
    let bandsCount: Int
    let modesCount: Int
    var qsoRate: Double?
    var watts: Int?
    var avgDistanceKm: Double?
    var medianDistanceKm: Double?
    var maxDistanceKm: Double?
    var wattsPerMile: Double?
    var radio: String?
    var equipment: [ShareCardEquipmentItem] = []

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = useMetricUnits // Trigger re-render when unit preference changes
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                ShareCardStatItem(value: "\(qsoCount)", label: "QSOs")
                ShareCardStatItem(value: duration, label: "Duration")
                if let rate = qsoRate {
                    ShareCardStatItem(
                        value: String(format: "%.1f", rate),
                        label: "QSOs/hr"
                    )
                }
                ShareCardStatItem(
                    value: "\(bandsCount)",
                    label: bandsCount == 1 ? "Band" : "Bands"
                )
                ShareCardStatItem(
                    value: "\(modesCount)",
                    label: modesCount == 1 ? "Mode" : "Modes"
                )
            }
            if hasDetailRow {
                detailRows
            }
            if !allEquipment.isEmpty {
                equipmentGrid
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.purple.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = false

    private var hasDetailRow: Bool {
        watts != nil || avgDistanceKm != nil || medianDistanceKm != nil
    }

    /// Radio merged with equipment for the grid display
    private var allEquipment: [ShareCardEquipmentItem] {
        var items: [ShareCardEquipmentItem] = []
        if let radio {
            items.append(ShareCardEquipmentItem(icon: "radio", text: radio))
        }
        items.append(contentsOf: equipment)
        return items
    }

    private var detailRows: some View {
        HStack(spacing: 12) {
            if let watts {
                detailBadge("\(watts)W")
            }
            if let wpm = wattsPerMile {
                detailBadge(UnitFormatter.wattsPerDistance(wpm))
            }
            if let median = medianDistanceKm {
                detailBadge(compactDistance(median, label: "p50"))
            } else if let avg = avgDistanceKm {
                detailBadge(compactDistance(avg, label: "avg"))
            }
            if let max = maxDistanceKm {
                detailBadge(compactDistance(max, label: "max"))
            }
        }
    }

    private var equipmentGrid: some View {
        let rows = stride(from: 0, to: allEquipment.count, by: 2).map { i in
            let end = min(i + 2, allEquipment.count)
            return Array(allEquipment[i ..< end])
        }
        return VStack(spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        equipmentBadge(icon: item.icon, text: item.text)
                    }
                }
            }
        }
    }

    private func equipmentBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.15))
        .clipShape(Capsule())
    }

    private func detailBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())
    }

    private func compactDistance(_ km: Double, label: String) -> String {
        UnitFormatter.distanceCompact(km, label: label)
    }
}

// MARK: - ActivationShareCardFooter

struct ActivationShareCardFooter: View {
    let callsign: String

    var body: some View {
        Text(callsign)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.top, 16)
            .padding(.bottom, 24)
    }
}

// MARK: - ShareCardStatItem

struct ShareCardStatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
