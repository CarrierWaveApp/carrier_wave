import SwiftUI

// MARK: - OnboardingStep

enum OnboardingStep: Int, CaseIterable {
    case callsign = 0
    case lookupResult
    case connectServices
    case activities
    case complete

    // MARK: Internal

    var title: String {
        switch self {
        case .callsign: "What's Your Callsign?"
        case .lookupResult: "Welcome!"
        case .connectServices: "Connect Your Services"
        case .activities: "Community Features"
        case .complete: "You're All Set!"
        }
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    @Bindable var tourState: TourState
    @ObservedObject var potaAuth: POTAAuthService

    @Environment(\.dismiss) var dismiss

    @State var currentStep: OnboardingStep = .callsign
    @State var callsign = ""
    @State var isLookingUp = false
    @State var profile: UserProfile?
    @State var showingError = false
    @State var errorMessage = ""

    // Service connection state
    @State var qrzApiKey = ""
    @State var lotwUsername = ""
    @State var lotwPassword = ""
    @State var potaUsername = ""
    @State var potaPassword = ""
    @State var isConnectingService = false
    @State var connectedServices: Set<String> = []

    // Activities opt-in state
    @State var activitiesOptIn = true
    @State var isRegistering = false

    let profileService = UserProfileService.shared
    let activitiesSourceURL = "https://activities.carrierwave.app"

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

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
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onAppear { detectExistingConnections() }
    }

    var stepContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                switch currentStep {
                case .callsign:
                    callsignStep
                case .lookupResult:
                    lookupResultStep
                case .connectServices:
                    connectServicesStep
                case .activities:
                    activitiesStep
                case .complete:
                    completeStep
                }
            }
            .padding(24)
        }
    }

    var navigationButtons: some View {
        HStack {
            if currentStep == .callsign {
                Button("Later") {
                    dismiss()
                }
                .foregroundStyle(.secondary)
            } else if currentStep != .complete {
                Button("Back") {
                    withAnimation {
                        if let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                            currentStep = previous
                        }
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(currentStep.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            primaryButton
        }
    }

    @ViewBuilder
    var primaryButton: some View {
        switch currentStep {
        case .callsign:
            Button {
                lookupCallsign()
            } label: {
                if isLookingUp {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Look Up")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(callsign.isEmpty || isLookingUp)

        case .lookupResult:
            Button("Next") {
                saveProfileAndContinue()
            }
            .buttonStyle(.borderedProminent)

        case .connectServices:
            Button(connectedServices.isEmpty ? "Skip" : "Next") {
                withAnimation {
                    currentStep = .activities
                }
            }
            .buttonStyle(.borderedProminent)

        case .activities:
            Button("Next") {
                registerAndContinue()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRegistering)

        case .complete:
            Button("Get Started") {
                completeOnboarding()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(tourState: TourState(), potaAuth: POTAAuthService())
}
