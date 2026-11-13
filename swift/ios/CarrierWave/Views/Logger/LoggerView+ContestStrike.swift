import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import SwiftUI

// MARK: - Contest Strike Card

//
// Unified contest-mode logging surface that combines the operator
// identity card (membership chips, location, prior contacts, dupe
// state) with the exchange input fields and a compact score footer.
// Sized to fit above the keyboard fold during a 100-QSO/hour CWT
// session, so the next action — type NAME and IDENTIFIER — is always
// reachable without scrolling. Replaces both `callsignLookupDisplay`
// and `contestExchangeSection` while a contest session is active.

extension LoggerView {
    /// One-card replacement for `callsignLookupDisplay` +
    /// `contestExchangeSection` during contest sessions. The full QRZ
    /// card stays in use outside contest sessions.
    @ViewBuilder
    var contestStrikeCard: some View {
        if isContestSession, let definition = contestManager?.definition {
            VStack(alignment: .leading, spacing: 10) {
                strikeHeaderRow
                strikeStatusRow
                Divider()
                    .opacity(0.35)
                strikeExchangeRow(definition: definition)
                strikeScoreFooter
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Header

    /// Header: callsign + membership chips + dupe / new-mult badge.
    private var strikeHeaderRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(strikeCallsignLabel)
                .font(.title3.bold().monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ForEach(strikeMemberships, id: \.sourceSlug) { membership in
                StrikeMembershipChip(membership: membership)
            }

            if let flag = CallsignFlagHelper.countryFlag(for: strikeCallsignLabel) {
                Text(flag)
                    .font(.subheadline)
            }

            Spacer(minLength: 8)

            strikeDupeBadge
        }
    }

    // MARK: - Status line

    /// Single dense line summarising "who is this": nickname, state,
    /// grid, distance, bearing, prior contact count. Joined by middle
    /// dots to keep one line as long as possible.
    @ViewBuilder
    private var strikeStatusRow: some View {
        let fragments = strikeStatusFragments
        if !fragments.isEmpty {
            Text(fragments.joined(separator: " · "))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
        }
    }

    // MARK: - Exchange inputs

    /// Two big monospaced fields — NAME and IDENTIFIER (CWops # or S/P/C).
    /// Tall (50pt) and centered for thumb targeting at 100 QSOs/hour.
    @ViewBuilder
    private func strikeExchangeRow(
        definition: ContestDefinition
    ) -> some View {
        let fields = definition.exchange.received.filter { $0.type != .signalReport }
        if !fields.isEmpty {
            HStack(spacing: 10) {
                ForEach(fields) { field in
                    strikeFieldInput(field)
                }
            }
        }
    }

    private func strikeFieldInput(
        _ field: ContestExchangeField
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.6)

            TextField(
                field.defaultValue?.stringValue ?? "",
                text: contestStrikeBinding(for: field.name)
            )
            .font(.title3.bold().monospaced())
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(strikeKeyboard(for: field.type))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Score footer

    /// `47Q · 47P · 12M · 564`  with an optional `MY #N` on the right
    /// for serial-number contests.
    @ViewBuilder
    private var strikeScoreFooter: some View {
        if let manager = contestManager, manager.isActive {
            let sc = manager.score
            HStack(spacing: 0) {
                Text(strikeScoreLine(
                    qsos: sc.totalQSOs,
                    points: sc.totalPoints,
                    mults: sc.multiplierCount,
                    score: sc.finalScore
                ))
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)

                Spacer()

                if let serial = contestManager?.currentSerial,
                   manager.definition?.exchange.sent.contains(where: {
                       $0.type == .serialNumber
                   }) == true
                {
                    Text("MY #\(serial)")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Helpers

    private var strikeCallsignLabel: String {
        let typed = callsignInput
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
        if !typed.isEmpty {
            return typed
        }
        return lookupResult?.callsign ?? "—"
    }

    private var strikeMemberships: [CallsignEnrichmentMembership] {
        lookupResult?.memberships ?? []
    }

    private var strikeStatusFragments: [String] {
        var parts: [String] = []
        if let info = lookupResult {
            if let name = info.displayName {
                parts.append(name)
            }
            if let state = info.state, !state.isEmpty {
                parts.append(state)
            }
            if let grid = info.grid, !grid.isEmpty {
                parts.append(grid)
            }
            if let km = strikeDistanceKm {
                parts.append(UnitFormatter.distance(km))
            }
            if let deg = strikeBearingDegrees {
                parts.append("\(Int(deg.rounded()))°")
            }
        }
        if previousQSOCount > 0 {
            parts.append("\(previousQSOCount) prior")
        }
        return parts
    }

    @ViewBuilder
    private var strikeDupeBadge: some View {
        if let status = contestManager?.lastDupeStatus {
            switch status {
            case .dupe:
                Text("DUPE")
                    .font(.caption.bold().monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.18), in: Capsule())
                    .foregroundStyle(.red)
            case let .newMultiplier(_, value):
                Text("NEW \(value)")
                    .font(.caption.bold().monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
            case .newStation:
                EmptyView()
            }
        }
    }

    private func contestStrikeBinding(
        for fieldName: String
    ) -> Binding<String> {
        Binding(
            get: { contestExchangeValues[fieldName] ?? "" },
            set: { contestExchangeValues[fieldName] = $0 }
        )
    }

    private func strikeKeyboard(
        for type: ContestExchangeFieldType
    ) -> UIKeyboardType {
        switch type {
        case .serialNumber,
             .cqZone,
             .ituZone,
             .age,
             .signalReport:
            .numberPad
        default:
            .default
        }
    }

    private func strikeScoreLine(
        qsos: Int,
        points: Int,
        mults: Int,
        score: Int
    ) -> String {
        "\(qsos)Q · \(points)P · \(mults)M · \(strikeFormatScore(score))"
    }

    private func strikeFormatScore(_ score: Int) -> String {
        if score >= 1_000_000 {
            return String(format: "%.1fM", Double(score) / 1_000_000)
        }
        if score >= 1_000 {
            return String(format: "%.1fK", Double(score) / 1_000)
        }
        return "\(score)"
    }

    /// Distance from session grid → station grid, in km.
    private var strikeDistanceKm: Double? {
        guard let myGrid = strikeMyGrid,
              let theirGrid = lookupResult?.grid, !theirGrid.isEmpty,
              let myCoord = MaidenheadConverter.coordinate(from: myGrid),
              let theirCoord = MaidenheadConverter.coordinate(from: theirGrid)
        else {
            return nil
        }
        let myLoc = CLLocation(
            latitude: myCoord.latitude,
            longitude: myCoord.longitude
        )
        let theirLoc = CLLocation(
            latitude: theirCoord.latitude,
            longitude: theirCoord.longitude
        )
        return myLoc.distance(from: theirLoc) / 1_000.0
    }

    private var strikeBearingDegrees: Double? {
        guard let myGrid = strikeMyGrid,
              let theirGrid = lookupResult?.grid, !theirGrid.isEmpty,
              let myCoord = MaidenheadConverter.coordinate(from: myGrid),
              let theirCoord = MaidenheadConverter.coordinate(from: theirGrid)
        else {
            return nil
        }
        let lat1 = myCoord.latitude * .pi / 180
        let lat2 = theirCoord.latitude * .pi / 180
        let dLon = (theirCoord.longitude - myCoord.longitude) * .pi / 180
        let yComp = sin(dLon) * cos(lat2)
        let xComp = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(yComp, xComp)
        return (radians * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private var strikeMyGrid: String? {
        sessionManager?.activeSession?.myGrid
            ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")
    }
}

// MARK: - StrikeMembershipChip

/// Compact membership chip for the strike header. Renders `🎹 #3573` —
/// drops the source name (implied by emoji + contest type) so the
/// header stays one line.
private struct StrikeMembershipChip: View {
    let membership: CallsignEnrichmentMembership

    var body: some View {
        HStack(spacing: 3) {
            if let emoji = membership.emoji {
                Text(emoji)
            }
            if let number = membership.memberNumber, !number.isEmpty {
                Text("#\(number)")
                    .monospacedDigit()
            } else {
                Text(membership.sourceName)
            }
        }
        .font(.caption.weight(.medium).monospaced())
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.blue.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
