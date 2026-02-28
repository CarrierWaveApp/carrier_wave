import CarrierWaveCore
import SwiftUI

// MARK: - LogsContainerView

/// Container for the Logs tab. Shows QSOs list directly (sessions moved to Sessions tab).
struct LogsContainerView: View {
    // MARK: Internal

    let potaClient: POTAClient?
    let potaAuth: POTAAuthService
    let lofiClient: LoFiClient
    let qrzClient: QRZClient
    let hamrsClient: HAMRSClient
    let lotwClient: LoTWClient
    let tourState: TourState

    /// When true, the view is already inside a navigation context (e.g., TabView on iOS 26
    /// or "More" tab) and should not add its own NavigationStack.
    var isInNavigationContext: Bool = false

    var body: some View {
        if isInNavigationContext {
            logsContent
        } else {
            NavigationStack {
                logsContent
            }
        }
    }

    // MARK: Private

    private var logsContent: some View {
        LogsListContentView(
            lofiClient: lofiClient,
            qrzClient: qrzClient,
            hamrsClient: hamrsClient,
            lotwClient: lotwClient,
            potaAuth: potaAuth,
            tourState: tourState
        )
    }
}
