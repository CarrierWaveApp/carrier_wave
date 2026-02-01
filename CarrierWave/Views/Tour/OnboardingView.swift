// swiftlint:disable file_length type_body_length
import SwiftUI

// MARK: - OnboardingStep

enum OnboardingStep: Int, CaseIterable {
    case callsign = 0
    case lookupResult
    case connectServices
    case complete

    // MARK: Internal

    var title: String {
        switch self {
        case .callsign: "What's Your Callsign?"
        case .lookupResult: "Welcome!"
        case .connectServices: "Connect Your Services"
        case .complete: "You're All Set!"
        }
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    // MARK: Internal

    @Bindable var tourState: TourState
    @ObservedObject var potaAuth: POTAAuthService

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
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: OnboardingStep = .callsign
    @State private var callsign = ""
    @State private var isLookingUp = false
    @State private var profile: UserProfile?
    @State private var showingError = false
    @State private var errorMessage = ""

    // Service connection state
    @State private var qrzApiKey = ""
    @State private var lotwUsername = ""
    @State private var lotwPassword = ""
    @State private var potaUsername = ""
    @State private var potaPassword = ""
    @State private var isConnectingService = false
    @State private var connectedServices: Set<String> = []

    private let profileService = UserProfileService.shared

    private var stepContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                switch currentStep {
                case .callsign:
                    callsignStep
                case .lookupResult:
                    lookupResultStep
                case .connectServices:
                    connectServicesStep
                case .complete:
                    completeStep
                }
            }
            .padding(24)
        }
    }

    private var callsignStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)

            Text("Let's set up your profile")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter your callsign and we'll look up your information from HamDB.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Callsign", text: $callsign)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
                .autocapitalization(.allCharacters)
                .autocorrectionDisabled()
                .font(.title2.monospaced())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .onSubmit { lookupCallsign() }

            if isLookingUp {
                HStack {
                    ProgressView()
                    Text("Looking up callsign...")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var lookupResultStep: some View {
        if let profile {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)

                Text(profile.callsign)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .monospaced()

                if let name = profile.fullName {
                    Text(name)
                        .font(.title2)
                }

                profileInfoGrid(profile)

                Text("We found your information! You can update this later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)

                Text(callsign.uppercased())
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .monospaced()

                Text(
                    "We couldn't find your callsign in HamDB. This might be a non-US callsign or a new license."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                Text("You can still use the app and update your profile later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var connectServicesStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.circle")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)

            Text("Connect your logging services")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect the services you use to sync your QSOs.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                // LoTW - uses callsign as username
                serviceConnectionCard(
                    name: "LoTW",
                    icon: "checkmark.seal",
                    isConnected: connectedServices.contains("lotw"),
                    content: {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Username")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(callsign.uppercased())
                                    .foregroundStyle(.secondary)
                                    .monospaced()
                            }
                            SecureField("Password", text: $lotwPassword)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
                        }
                    },
                    onConnect: connectLoTW
                )

                // POTA - uses email
                serviceConnectionCard(
                    name: "POTA",
                    icon: "tree",
                    isConnected: connectedServices.contains("pota"),
                    content: {
                        VStack(spacing: 8) {
                            TextField("Email", text: $potaUsername)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                            SecureField("Password", text: $potaPassword)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
                        }
                    },
                    onConnect: connectPOTA
                )

                // QRZ - uses API key
                serviceConnectionCard(
                    name: "QRZ Logbook",
                    icon: "globe",
                    isConnected: connectedServices.contains("qrz"),
                    content: {
                        VStack(spacing: 8) {
                            Text("Get your API key from QRZ Logbook settings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            SecureField("API Key", text: $qrzApiKey)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
                        }
                    },
                    onConnect: connectQRZ
                )
            }

            Text("You can skip this and connect services later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var completeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Welcome, \(profile?.firstName ?? callsign.uppercased())!")
                .font(.title)
                .fontWeight(.bold)

            Text("Your profile is set up and you're ready to start logging contacts.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !connectedServices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connected Services:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(Array(connectedServices).sorted(), id: \.self) { service in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(service.capitalized)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text("You can always update your profile and connect more services in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var navigationButtons: some View {
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
    private var primaryButton: some View {
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
                    currentStep = .complete
                }
            }
            .buttonStyle(.borderedProminent)

        case .complete:
            Button("Get Started") {
                completeOnboarding()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func profileInfoGrid(_ profile: UserProfile) -> some View {
        VStack(spacing: 12) {
            if let location = profile.shortLocation {
                profileInfoRow(icon: "location", label: "QTH", value: location)
            }

            if let grid = profile.grid {
                profileInfoRow(icon: "square.grid.3x3", label: "Grid", value: grid)
            }

            if let licenseClass = profile.licenseClass {
                profileInfoRow(
                    icon: "graduationcap", label: "Class", value: licenseClass.displayName
                )
            }

            if let expires = profile.licenseExpires {
                profileInfoRow(icon: "calendar", label: "Expires", value: expires)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func profileInfoRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func serviceConnectionCard(
        name: String,
        icon: String,
        isConnected: Bool,
        @ViewBuilder content: () -> some View,
        onConnect: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(name)
                    .fontWeight(.medium)
                Spacer()
                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if !isConnected {
                content()

                Button {
                    Task { await onConnect() }
                } label: {
                    if isConnectingService {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Connect")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isConnectingService)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func lookupCallsign() {
        guard !callsign.isEmpty else {
            return
        }

        isLookingUp = true

        Task {
            do {
                let foundProfile = try await profileService.lookupAndCreateProfile(
                    callsign: callsign
                )
                await MainActor.run {
                    profile = foundProfile
                    isLookingUp = false
                    withAnimation {
                        currentStep = .lookupResult
                    }
                }
            } catch {
                await MainActor.run {
                    // Even on error, create a minimal profile
                    profile = UserProfile(callsign: callsign)
                    isLookingUp = false
                    withAnimation {
                        currentStep = .lookupResult
                    }
                }
            }
        }
    }

    private func saveProfileAndContinue() {
        if let profile {
            do {
                try profileService.saveProfile(profile)
            } catch {
                errorMessage = "Failed to save profile: \(error.localizedDescription)"
                showingError = true
                return
            }
        }

        withAnimation {
            currentStep = .connectServices
        }
    }

    private func connectQRZ() async {
        guard !qrzApiKey.isEmpty else {
            return
        }

        isConnectingService = true
        defer { isConnectingService = false }

        do {
            let client = QRZClient()
            let status = try await client.validateApiKey(qrzApiKey)
            try client.saveApiKey(qrzApiKey)
            try client.saveCallsign(status.callsign)
            if let bookId = status.bookId {
                try client.saveBookId(bookId, for: status.callsign)
            }

            await MainActor.run {
                _ = connectedServices.insert("qrz")
            }
        } catch {
            await MainActor.run {
                errorMessage = "QRZ connection failed: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func connectLoTW() async {
        guard !lotwPassword.isEmpty else {
            return
        }

        isConnectingService = true
        defer { isConnectingService = false }

        do {
            let client = LoTWClient()
            // Use callsign as username for LoTW
            try await client.testCredentials(
                username: callsign.uppercased(), password: lotwPassword
            )
            try client.saveCredentials(username: callsign.uppercased(), password: lotwPassword)

            await MainActor.run {
                _ = connectedServices.insert("lotw")
            }
        } catch {
            await MainActor.run {
                errorMessage = "LoTW connection failed: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func connectPOTA() async {
        guard !potaUsername.isEmpty, !potaPassword.isEmpty else {
            return
        }

        isConnectingService = true
        defer { isConnectingService = false }

        do {
            _ = try await potaAuth.performHeadlessLogin(
                username: potaUsername, password: potaPassword
            )
            try potaAuth.saveCredentials(username: potaUsername, password: potaPassword)

            await MainActor.run {
                _ = connectedServices.insert("pota")
            }
        } catch {
            await MainActor.run {
                errorMessage = "POTA connection failed: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func completeOnboarding() {
        tourState.completeOnboarding()
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(tourState: TourState(), potaAuth: POTAAuthService())
}
