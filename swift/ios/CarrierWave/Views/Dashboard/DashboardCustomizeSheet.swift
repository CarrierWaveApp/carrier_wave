import CarrierWaveData
import SwiftUI

// MARK: - DashboardCustomizeSheet

/// Sheet for choosing which cards appear on the dashboard.
///
/// The dashboard ships lean (essentials only); this sheet is how the user *adds*
/// the optional cards back. Most toggles therefore start in the off position.
struct DashboardCustomizeSheet: View {
    // MARK: Internal

    @Binding var hiddenCardsRaw: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Your dashboard starts light. Turn on the cards you want — the rest stay one tap away.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(DashboardSectionID.allCases) { section in
                    let cards = availableCards(in: section)
                    if !cards.isEmpty {
                        Section(section.title) {
                            ForEach(cards) { card in
                                Toggle(isOn: cardVisibleBinding(card)) {
                                    Label(card.displayName, systemImage: card.icon)
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }

                Section {
                    Button("Reset to Default Layout") {
                        withAnimation {
                            hiddenCardsRaw = ""
                        }
                    }
                    .foregroundStyle(.red)
                } footer: {
                    Text("Restores the light default with only the essential cards.")
                }
            }
            .navigationTitle("Customize Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    /// All cards the user can toggle, across every section, filtered by experiment
    /// availability. Used to materialize the full hidden set on first customization.
    private var allAvailableCards: [DashboardCardID] {
        DashboardSectionID.allCases.flatMap { availableCards(in: $0) }
    }

    private func availableCards(in section: DashboardSectionID) -> [DashboardCardID] {
        section.cards.filter { card in
            guard let experiment = card.requiredExperiment else {
                return true
            }
            return ExperimentalFeature.isEnabled(experiment)
        }
    }

    private func cardVisibleBinding(_ card: DashboardCardID) -> Binding<Bool> {
        Binding(
            get: {
                DashboardLayoutPrefs.isCardVisible(card, hiddenRaw: hiddenCardsRaw)
            },
            set: { visible in
                hiddenCardsRaw = DashboardLayoutPrefs.setCardVisible(
                    card,
                    visible: visible,
                    in: hiddenCardsRaw,
                    available: allAvailableCards
                )
            }
        )
    }
}
