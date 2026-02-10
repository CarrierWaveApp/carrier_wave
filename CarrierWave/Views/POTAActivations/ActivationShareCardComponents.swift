// Activation Share Card Components
//
// Reusable component views for activation share cards.

import SwiftUI

// MARK: - ActivationShareCardHeader

struct ActivationShareCardHeader: View {
    var body: some View {
        HStack {
            Image(systemName: "tree.fill")
                .font(.title2)
            Text("CARRIER WAVE")
                .font(.headline)
                .fontWeight(.bold)
        }
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
            Text(parkReference)
                .font(.title2)
                .fontWeight(.bold)
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

// MARK: - ActivationShareCardStats

struct ActivationShareCardStats: View {
    // MARK: Internal

    let qsoCount: Int
    let duration: String
    let bandsCount: Int
    let modesCount: Int
    var watts: Int?
    var avgDistanceKm: Double?
    var maxDistanceKm: Double?
    var wattsPerMile: Double?
    var radio: String?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 24) {
                ShareCardStatItem(value: "\(qsoCount)", label: "QSOs")
                ShareCardStatItem(value: duration, label: "Duration")
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
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.purple.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: Private

    private var hasDetailRow: Bool {
        watts != nil || avgDistanceKm != nil || radio != nil
    }

    @ViewBuilder
    private var detailRows: some View {
        HStack(spacing: 12) {
            if let watts {
                detailBadge("\(watts)W")
            }
            if let wpm = wattsPerMile {
                detailBadge(String(format: "%.2f W/mi", wpm))
            }
            if let avg = avgDistanceKm {
                detailBadge(compactDistance(avg, label: "avg"))
            }
            if let max = maxDistanceKm {
                detailBadge(compactDistance(max, label: "max"))
            }
        }
        if let radio {
            detailBadge(radio)
        }
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
        let mi = km * 0.621371
        if mi >= 1_000 {
            return String(format: "%.\(mi >= 10_000 ? "0" : "1")fk mi %@", mi / 1_000, label)
        }
        return String(format: "%.0f mi %@", mi, label)
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
