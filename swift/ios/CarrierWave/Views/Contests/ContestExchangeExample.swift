import CarrierWaveData
import SwiftUI

// MARK: - ContestExchangeExampleView

/// Shows an example exchange using the user's profile data.
struct ContestExchangeExampleView: View {
    // MARK: Internal

    let exchange: ContestExchange

    var body: some View {
        let profile = UserProfileService.shared.getProfile()
        let myCall = profile?.callsign ?? currentCallsign
        let sent = exchange.sent.map { ExchangeExampleValues.value(for: $0, profile: profile) }
        let received = exchange.received.map { ExchangeExampleValues.value(for: $0, profile: nil) }
        VStack(alignment: .leading, spacing: 4) {
            Text("Example")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            HStack(spacing: 0) {
                Text("\(myCall) sends ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sent.joined(separator: " "))
                    .font(.caption.monospaced().weight(.medium))
            }
            HStack(spacing: 0) {
                Text("N3FJP sends ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(received.joined(separator: " "))
                    .font(.caption.monospaced().weight(.medium))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    private var currentCallsign: String {
        if let call = try? KeychainHelper.shared.readString(
            for: KeychainHelper.Keys.currentCallsign
        ), !call.isEmpty {
            return call
        }
        return "Me"
    }
}

// MARK: - ExchangeExampleValues

enum ExchangeExampleValues {
    // MARK: Internal

    static func value(for field: ContestExchangeField, profile: UserProfile?) -> String {
        if let result = autofillValue(for: field, profile: profile) {
            return result
        }
        return typeBasedValue(for: field, profile: profile)
    }

    // MARK: Private

    private static func autofillValue(
        for field: ContestExchangeField,
        profile: UserProfile?
    ) -> String? {
        guard let autofill = field.autofill, let profile else {
            return nil
        }
        switch autofill {
        case "my_callsign": return profile.callsign
        case "my_state": return profile.state ?? "CA"
        case "my_section": return "SCV"
        case "my_cq_zone": return "3"
        case "my_itu_zone": return "6"
        case "my_grid": return profile.grid ?? "CM87"
        default: return nil
        }
    }

    private static func typeBasedValue(
        for field: ContestExchangeField,
        profile: UserProfile?
    ) -> String {
        switch field.type {
        case .signalReport: "599"
        case .serialNumber: "001"
        case .cqZone: "3"
        case .ituZone: "6"
        case .gridSquare: profile?.grid ?? "FN20"
        case .stateProvince: profile?.state ?? "NY"
        case .arrlSection,
             .sectionList: "ENY"
        case .power: "100"
        case .name: profile?.firstName?.uppercased() ?? "JOHN"
        case .age: "35"
        case .classField: "A"
        case .text: String(field.label.uppercased().prefix(3))
        case .unknown: "?"
        }
    }
}
