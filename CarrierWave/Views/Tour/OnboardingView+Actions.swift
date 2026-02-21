import SwiftUI

// MARK: - OnboardingView Helper Views & Actions

extension OnboardingView {
    // MARK: - Helper Views

    func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }

    func profileInfoGrid(_ profile: UserProfile) -> some View {
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

    func profileInfoRow(icon: String, label: String, value: String) -> some View {
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

    func serviceConnectionCard(
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

    // MARK: - Actions

    func lookupCallsign() {
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

    func saveProfileAndContinue() {
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

    func connectQRZ() async {
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

    func connectLoTW() async {
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

    func connectPOTA() async {
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

    func registerAndContinue() {
        // Save preference
        UserDefaults.standard.set(activitiesOptIn, forKey: "activitiesServerEnabled")

        guard activitiesOptIn, !callsign.isEmpty else {
            withAnimation { currentStep = .complete }
            return
        }

        isRegistering = true
        Task {
            defer {
                isRegistering = false
                withAnimation { currentStep = .complete }
            }
            do {
                let client = ActivitiesClient()
                _ = try await client.register(
                    callsign: callsign.uppercased(),
                    deviceName: UIDevice.current.name,
                    sourceURL: activitiesSourceURL
                )
            } catch {
                // Non-fatal — user can register later via sync
                print("[Onboarding] Activities registration failed: \(error)")
            }
        }
    }

    func completeOnboarding() {
        tourState.completeOnboarding()
        dismiss()
    }
}
