import CarrierWaveData
import SwiftUI

// MARK: - AboutMeView + Actions Card

extension AboutMeView {
    /// Refresh + Change Callsign actions, formatted as a compact card with
    /// two stacked buttons. The change-callsign flow expands inline so the
    /// user doesn't lose context with a sheet over a sheet.
    var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Actions")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            VStack(spacing: 0) {
                refreshButton
                Divider().background(Color(.separator).opacity(0.6))
                if isChangingCallsign {
                    changeCallsignFields
                } else {
                    changeCallsignButton
                }
            }
            Text(
                "Refresh re-fetches your information from HamDB.org. "
                    + "Change Callsign updates your callsign, looks up the new "
                    + "profile, and walks you through updating your connected "
                    + "services."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func refreshProfile() async {
        guard let existingProfile = profile else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await profileService.lookupAndCreateProfileWithChangeDetection(
                callsign: existingProfile.callsign
            )

            if let newProfile = result.profile {
                try profileService.saveProfile(newProfile)

                await MainActor.run {
                    profile = newProfile
                    callsignChangeNote = result.callsignChangeNote
                    loadProfile()
                    showSaveSuccess = true
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to refresh profile: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    func changeCallsign() async {
        let trimmed = newCallsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count >= 3 else {
            return
        }

        isLookingUpNewCallsign = true
        defer { isLookingUpNewCallsign = false }

        do {
            try UserProfileService.shared.applyCallsignChangeIfNeeded(
                newCallsign: trimmed
            )

            let result = try await profileService.lookupAndCreateProfileWithChangeDetection(
                callsign: trimmed
            )

            if let newProfile = result.profile {
                try profileService.saveProfile(newProfile)
                profile = newProfile
                callsignChangeNote = result.callsignChangeNote
                loadProfile()
                await loadClubNumbers()
            }

            isChangingCallsign = false
            newCallsign = ""
            // Walk through the connected services that still reference the
            // old callsign instead of just flashing a success alert
            if CallsignChangeGuide.shared.pending != nil {
                showCallsignChangeGuide = true
            } else {
                showSaveSuccess = true
            }
        } catch {
            errorMessage = "Failed to change callsign: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: Private

    private var refreshButton: some View {
        Button {
            showRefreshConfirmation = true
        } label: {
            HStack(spacing: 10) {
                if isRefreshing {
                    ProgressView()
                        .frame(width: 18)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                        .frame(width: 18)
                }
                Text(isRefreshing ? "Refreshing…" : "Refresh from HamDB")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing || isLookingUpNewCallsign)
        .accessibilityLabel("Refresh profile from HamDB")
    }

    private var changeCallsignButton: some View {
        Button {
            isChangingCallsign = true
            newCallsign = ""
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.key")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                    .frame(width: 18)
                Text("Change Callsign")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change your callsign")
    }

    private var changeCallsignFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.key")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                TextField("New Callsign", text: $newCallsign)
                    .font(.subheadline.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                Button("Cancel") {
                    isChangingCallsign = false
                    newCallsign = ""
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minHeight: 36)
                Spacer()
                Button {
                    Task { await changeCallsign() }
                } label: {
                    if isLookingUpNewCallsign {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Look Up & Update")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    newCallsign.trimmingCharacters(in: .whitespaces).count < 3
                        || isLookingUpNewCallsign
                )
            }
        }
        .padding(.vertical, 8)
    }
}
