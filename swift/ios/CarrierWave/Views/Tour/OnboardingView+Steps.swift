import CarrierWaveData
import SwiftUI

// MARK: - OnboardingView Step Content Views

extension OnboardingView {
    var callsignStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)

            Text("Welcome to Carrier Wave")
                .font(.title2)
                .fontWeight(.semibold)

            Text(
                "Enter your callsign to get started. We'll look up your info from HamDB — "
                    + "everything else can wait."
            )
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

    /// Persona step: one tap tunes role-aware defaults (Hunter Log landing,
    /// On Air card sections, future first-win routing). Optional — "Get
    /// Started" works without a selection and the app stays neutral.
    var roleStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("How do you operate?")
                .font(.title2)
                .fontWeight(.semibold)

            Text(
                "Carrier Wave tunes its home screen and defaults to match. "
                    + "You can change this anytime in Settings."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                ForEach(OperatorRole.allCases) { role in
                    roleOptionRow(role)
                }
            }
        }
    }

    @ViewBuilder
    var lookupResultStep: some View {
        if let profile {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.largeTitle)
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

                Text(
                    "You're ready to log contacts. Connect logging services and the community later from the dashboard."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        } else {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)

                Text(callsign.uppercased())
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .monospaced()

                Text(
                    "We couldn't find your callsign in HamDB. "
                        + "This might be a non-US callsign or a new license."
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

    // MARK: - Role Option Row

    private func roleOptionRow(_ role: OperatorRole) -> some View {
        let isSelected = selectedRole == role
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedRole = isSelected ? nil : role
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: role.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(role.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(role.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(role.displayName)
        .accessibilityHint(role.blurb)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
