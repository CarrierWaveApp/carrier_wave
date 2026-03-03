import SwiftUI

// MARK: - TuneInCellularAlert

/// ViewModifier that presents a cellular data warning alert for Tune In.
/// Shows on first use over cellular (~5 MB/hour).
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
                Button("Cancel", role: .cancel) {
                    manager.dismissCellularWarning()
                }
                Button("Continue") {
                    Task {
                        await manager.confirmCellular(modelContext: modelContext)
                    }
                }
            } message: {
                Text(
                    "Tune In streams audio over your cellular connection. "
                        + "This uses about 5 MB per hour."
                )
            }
    }
}

extension View {
    func tuneInCellularAlert(manager: TuneInManager) -> some View {
        modifier(TuneInCellularAlert(manager: manager))
    }
}
