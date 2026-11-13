import CarrierWaveData
import SwiftUI

// MARK: - Connection Section

extension EquipmentItemDetailView {
    /// Connection profile row + sheet trigger. Renders only for radios
    /// — non-radio items have no auto-connect concept.
    @ViewBuilder
    func connectionSection(_ item: EquipmentItem) -> some View {
        if item.category == .radio {
            Section {
                Button {
                    showConnectionSheet = true
                } label: {
                    HStack {
                        Label(
                            connectionSummary(item),
                            systemImage: connectionIcon(item)
                        )
                        .foregroundStyle(
                            item.connectionProfile != nil ? .primary : .secondary
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                if item.connectionProfile == nil {
                    Text(
                        "Configure how Carrier Wave reaches this radio. "
                            + "Sessions that select this radio will "
                            + "auto-connect on start."
                    )
                }
            }
            .sheet(isPresented: $showConnectionSheet) {
                RadioConnectionSheet(itemID: item.id) {
                    onUpdate?()
                }
            }
        }
    }

    // MARK: Helpers

    private func connectionSummary(_ item: EquipmentItem) -> String {
        if let profile = item.connectionProfile, profile.isConfigured {
            return profile.summary
        }
        if item.connectionProfile != nil {
            return "Incomplete \u{2014} tap to finish"
        }
        return "Not configured"
    }

    private func connectionIcon(_ item: EquipmentItem) -> String {
        guard let profile = item.connectionProfile, profile.isConfigured else {
            return "antenna.radiowaves.left.and.right.slash"
        }
        switch profile.transport {
        case .ble: return "dot.radiowaves.left.and.right"
        case .wifi: return "wifi"
        case .flex: return "network"
        case .scuLan10: return "network"
        }
    }
}
