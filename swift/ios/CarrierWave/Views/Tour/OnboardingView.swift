import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - OnboardingView

/// Minimum viable onboarding: collect the user's callsign, show the looked-up
/// profile inline, ask how they operate (`OperatorRole`), and drop them into
/// the app. Everything else (service connections, community opt-in, region
/// confirmation) lives on the dashboard Getting Started card or is
/// auto-detected silently, so it can be tackled at the user's pace.
struct OnboardingView: View {
    @Bindable var tourState: TourState

    @Environment(\.dismiss) var dismiss

    @State var callsign = ""
    @State var isLookingUp = false
    @State var profile: UserProfile?
    @State var showingError = false
    @State var errorMessage = ""
    @State var showingRoleStep = false
    @State var selectedRole: OperatorRole?

    let profileService = UserProfileService.shared

    var body: some View {
        ZStack {
            Color.primary.opacity(0.4)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        if showingRoleStep {
                            roleStep
                        } else if profile == nil {
                            callsignStep
                        } else {
                            lookupResultStep
                        }
                    }
                    .padding(24)
                }
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
    }

    var navigationButtons: some View {
        HStack {
            if showingRoleStep {
                Button("Back") {
                    withAnimation {
                        showingRoleStep = false
                    }
                }
                .foregroundStyle(.secondary)
            } else if profile == nil {
                Button("Later") {
                    dismiss()
                }
                .foregroundStyle(.secondary)
            } else {
                Button("Edit") {
                    withAnimation {
                        profile = nil
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            primaryButton
        }
    }

    @ViewBuilder
    var primaryButton: some View {
        if showingRoleStep {
            Button("Get Started") {
                saveAndFinish()
            }
            .buttonStyle(.borderedProminent)
        } else if profile == nil {
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
        } else {
            Button("Continue") {
                withAnimation {
                    showingRoleStep = true
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(tourState: TourState())
}
