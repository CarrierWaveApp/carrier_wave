import SwiftUI

// MARK: - TuneInStrategySheet

/// ViewModifier that presents a strategy selection dialog for Tune In.
/// Lets the user choose how to pick a KiwiSDR receiver before connecting.
struct TuneInStrategySheet: ViewModifier {
    // MARK: Internal

    let manager: TuneInManager

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Listening Strategy",
                isPresented: Binding(
                    get: { manager.showStrategyPicker },
                    set: {
                        if !$0 {
                            manager.dismissStrategyPicker()
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                ForEach(TuneInStrategy.allCases, id: \.self) { strategy in
                    Button {
                        guard let spot = manager.pendingStrategySpot else {
                            return
                        }
                        manager.dismissStrategyPicker()
                        Task {
                            await manager.tuneIn(
                                to: spot,
                                modelContext: modelContext,
                                strategy: strategy
                            )
                        }
                    } label: {
                        Label(strategy.title, systemImage: strategy.systemImage)
                    }
                }

                Button("Cancel", role: .cancel) {
                    manager.dismissStrategyPicker()
                }
            } message: {
                Text("Choose how to select a receiver")
            }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
}

extension View {
    func tuneInStrategySheet(manager: TuneInManager) -> some View {
        modifier(TuneInStrategySheet(manager: manager))
    }
}
