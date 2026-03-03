import SwiftUI

// MARK: - TuneInCellularAlert

/// View modifier that presents a cellular data warning on first Tune In use over cellular.
struct TuneInCellularAlert: ViewModifier {
    let manager: TuneInManager
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .alert(
                "Cellular Data",
                isPresented: Binding(
                    get: { manager.showCellularWarning },
                    set: { if !$0 { manager.dismissCellularWarning() } }
                )
            ) {
                Button("Continue") {
                    Task {
                        await manager.confirmCellular(modelContext: modelContext)
                    }
                }
                Button("Cancel", role: .cancel) {
                    manager.dismissCellularWarning()
                }
            } message: {
                Text(
                    "Tune In streams audio over the network (~5 MB/hour). "
                        + "You're currently on cellular data."
                )
            }
    }
}

extension View {
    func tuneInCellularAlert(manager: TuneInManager) -> some View {
        modifier(TuneInCellularAlert(manager: manager))
    }
}
