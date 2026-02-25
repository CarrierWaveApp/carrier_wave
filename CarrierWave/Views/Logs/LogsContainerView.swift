import CarrierWaveCore
import SwiftUI

// MARK: - LogsContainerView

/// Container for the Logs tab. Shows QSOs list directly (sessions moved to Sessions tab).
struct LogsContainerView: View {
    let potaClient: POTAClient?
    let potaAuth: POTAAuthService
    let lofiClient: LoFiClient
    let qrzClient: QRZClient
    let hamrsClient: HAMRSClient
    let lotwClient: LoTWClient
    let tourState: TourState

    var body: some View {
        NavigationStack {
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
}
