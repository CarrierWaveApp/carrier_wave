import CarrierWaveData
import SwiftUI

// MARK: - IntroTourStep

enum IntroTourStep: Int, CaseIterable {
    case welcome = 0
    case syncExplanation
    case qrzSetup
    case otherServices
    case statistics
    case mapView
    case activity
    case feedback

    // MARK: Internal

    var title: String {
        switch self {
        case .welcome: "Welcome to Carrier Wave"
        case .syncExplanation: "Keep Your Logs in Sync"
        case .qrzSetup: "Connect to QRZ"
        case .otherServices: "More Services Available"
        case .statistics: "Track Your Progress"
        case .mapView: "See Your Contacts"
        case .activity: "Connect with the Community"
        case .feedback: "You're All Set!"
        }
    }
}

// MARK: - IntroTourView

struct IntroTourView: View {
    // MARK: Internal

    @Bindable var tourState: TourState

    var body: some View {
        ZStack {
            // Blurred background
            Color.black.opacity(0.4)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            // Content card
            VStack(spacing: 0) {
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                navigationButtons
                    .padding()
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
            .padding(.horizontal, 24)
            .padding(.vertical, 60)
        }
        .sheet(isPresented: $showingOtherServicesSheet) {
            IntroTourOtherServicesSheet(isPresented: $showingOtherServicesSheet)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: IntroTourStep = .welcome
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var qrzConnected = false
    @State private var connectedCallsign: String?
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var showingOtherServicesSheet = false

    private let qrzClient = QRZClient()

    private var stepContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                switch currentStep {
                case .welcome:
                    IntroTourWelcomeStep()
                case .syncExplanation:
                    IntroTourSyncStep()
                case .qrzSetup:
                    IntroTourQRZStep(
                        apiKey: $apiKey,
                        qrzConnected: qrzConnected,
                        connectedCallsign: connectedCallsign,
                        onShowOtherServices: { showingOtherServicesSheet = true }
                    )
                case .otherServices:
                    IntroTourServicesStep()
                case .statistics:
                    IntroTourStatisticsStep()
                case .mapView:
                    IntroTourMapStep()
                case .activity:
                    IntroTourActivityStep()
                case .feedback:
                    IntroTourFeedbackStep()
                }
            }
            .padding(24)
        }
    }

    private var navigationButtons: some View {
        HStack {
            if currentStep != .welcome {
                Button("Back") {
                    withAnimation {
                        if let previous = IntroTourStep(rawValue: currentStep.rawValue - 1) {
                            currentStep = previous
                        }
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(currentStep.rawValue + 1) of \(IntroTourStep.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch currentStep {
        case .welcome,
             .syncExplanation,
             .otherServices,
             .statistics,
             .mapView,
             .activity:
            nextButton
        case .qrzSetup:
            qrzSetupButton
        case .feedback:
            getStartedButton
        }
    }

    private var nextButton: some View {
        Button("Next") {
            withAnimation { advanceStep() }
        }
        .buttonStyle(.borderedProminent)
    }

    private var getStartedButton: some View {
        Button("Get Started") { completeTour() }
            .buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private var qrzSetupButton: some View {
        if qrzConnected {
            nextButton
        } else if apiKey.isEmpty {
            Button("Skip") {
                withAnimation { advanceStep() }
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                Task { await validateAndConnect() }
            } label: {
                if isValidating {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isValidating)
        }
    }

    private func advanceStep() {
        if let next = IntroTourStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }

    private func validateAndConnect() async {
        isValidating = true
        defer { isValidating = false }

        do {
            let status = try await qrzClient.validateApiKey(apiKey)
            try qrzClient.saveApiKey(apiKey)
            try qrzClient.saveCallsign(status.callsign)
            if let bookId = status.bookId {
                try qrzClient.saveBookId(bookId, for: status.callsign)
            }
            qrzConnected = true
            connectedCallsign = status.callsign

            let aliasService = CallsignAliasService.shared
            if aliasService.getCurrentCallsign() == nil {
                try aliasService.saveCurrentCallsign(status.callsign)
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func completeTour() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        tourState.completeIntroTour(version: version)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    IntroTourView(tourState: TourState())
}
