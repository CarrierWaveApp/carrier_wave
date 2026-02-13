import CarrierWaveCore
import SwiftUI

// MARK: - LogsSegment

enum LogsSegment: String, CaseIterable {
    case qsos = "QSOs"
    case potaActivations = "POTA Activations"
    case sessions = "Sessions"
}

// MARK: - LogsContainerView

struct LogsContainerView: View {
    // MARK: Internal

    let potaClient: POTAClient?
    let potaAuth: POTAAuthService
    let lofiClient: LoFiClient
    let qrzClient: QRZClient
    let hamrsClient: HAMRSClient
    let lotwClient: LoTWClient
    let tourState: TourState

    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if availableSegments.count > 1 {
                    segmentedPicker
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }
                selectedContent
            }
        }
    }

    // MARK: Private

    @State private var selectedSegment: LogsSegment = .qsos

    private var availableSegments: [LogsSegment] {
        LogsSegment.allCases
    }

    private var segmentedPicker: some View {
        Picker("Log Type", selection: $selectedSegment) {
            ForEach(availableSegments, id: \.self) { segment in
                Text(segment.rawValue).tag(segment)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSegment {
        case .qsos:
            LogsListContentView(
                lofiClient: lofiClient,
                qrzClient: qrzClient,
                hamrsClient: hamrsClient,
                lotwClient: lotwClient,
                potaAuth: potaAuth,
                tourState: tourState
            )
        case .potaActivations:
            POTAActivationsContentView(
                potaClient: potaClient, potaAuth: potaAuth, tourState: tourState
            )
        case .sessions:
            SessionsView()
        }
    }
}
