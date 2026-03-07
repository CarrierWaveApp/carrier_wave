import CarrierWaveData
import SwiftUI

// MARK: - TuneInCellularAlert

/// ViewModifier that presents a cellular data warning alert for Tune In.
/// Shows on first use over cellular (~5 MB/hour).
struct TuneInCellularAlert: ViewModifier {
    // MARK: Internal

    let manager: TuneInManager

    func body(content: Content) -> some View {
        content
            .alert(
                "Cellular Data",
                isPresented: Binding(
                    get: { manager.showCellularWarning },
                    set: {
                        if !$0 {
                            manager.dismissCellularWarning()
                        }
                    }
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

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
}

extension View {
    func tuneInCellularAlert(manager: TuneInManager) -> some View {
        modifier(TuneInCellularAlert(manager: manager))
    }
}

// MARK: - TuneInErrorAlert

/// ViewModifier that presents an error alert when Tune In fails
/// (e.g. no receivers available or all connections failed).
struct TuneInErrorAlert: ViewModifier {
    let manager: TuneInManager

    func body(content: Content) -> some View {
        content
            .alert(
                "Tune In Unavailable",
                isPresented: Binding(
                    get: { manager.errorMessage != nil },
                    set: {
                        if !$0 {
                            manager.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    manager.errorMessage = nil
                }
            } message: {
                if let message = manager.errorMessage {
                    Text(message)
                }
            }
    }
}

extension View {
    func tuneInErrorAlert(manager: TuneInManager) -> some View {
        modifier(TuneInErrorAlert(manager: manager))
    }
}
