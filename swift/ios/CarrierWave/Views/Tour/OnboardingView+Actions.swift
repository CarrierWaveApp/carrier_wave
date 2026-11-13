import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - OnboardingView Helper Views & Actions

extension OnboardingView {
    // MARK: - Helper Views

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
                    withAnimation {
                        profile = foundProfile
                    }
                    isLookingUp = false
                }
            } catch {
                await MainActor.run {
                    // Even on error, create a minimal profile so the user can proceed
                    withAnimation {
                        profile = UserProfile(callsign: callsign)
                    }
                    isLookingUp = false
                }
            }
        }
    }

    func saveAndFinish() {
        if let profile {
            do {
                try profileService.saveProfile(profile)
            } catch {
                errorMessage = "Failed to save profile: \(error.localizedDescription)"
                showingError = true
                return
            }
        }
        selectedRole?.persist()
        persistInferredRegion()
        tourState.completeOnboarding()
        dismiss()
    }

    /// Silently persist the IARU region inferred from the operator's callsign
    /// so band plans, awards, and units pick up regional defaults on first
    /// launch. The user can override in Settings if the inference is wrong —
    /// no dedicated onboarding screen needed for the common case.
    private func persistInferredRegion() {
        guard UserDefaults.standard.string(forKey: "userIARURegionOverride") == nil,
              let region = UserRegionProfile.primaryIARURegion
        else {
            return
        }
        UserDefaults.standard.set(region.rawValue, forKey: "userIARURegionOverride")
    }
}
