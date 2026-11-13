import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - AboutMeView

/// Operator profile page. Card-based layout following the Carrier Wave
/// design language — identity hero, earned badges strip, club numbers,
/// and actions. Editing the profile happens in a dedicated sheet.
struct AboutMeView: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext

    var onRequestOnboarding: (() -> Void)?

    @State var callsignChangeNote: String?

    @State var profile: UserProfile?

    // Club numbers (populated from ClubsSyncService)
    @State var myClubMembers: [FfiClubMember] = []
    @State var pendingNumbers: [String: String] = [:]
    @State var skccBadgeForMyCallsign: String?

    @State var showError = false
    @State var errorMessage = ""

    // Actions card flow
    @State var isRefreshing = false
    @State var isChangingCallsign = false
    @State var newCallsign = ""
    @State var isLookingUpNewCallsign = false
    @State var showSaveSuccess = false
    @State var showRefreshConfirmation = false
    @State var showCallsignChangeGuide = false

    /// Callsign lookup (QRZ-first via CallsignLookupService) — feeds the
    /// identity card's nickname / displayName so the operator sees the
    /// same enriched identity as on CallsignHistoryView.
    @State var callsignInfo: CallsignInfo?

    let profileService = UserProfileService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let profile {
                    identityCard(profile)
                    badgesCard(profile)
                    CallsignNotesSection(
                        callsign: profile.callsign,
                        callsignInfo: callsignInfo
                    )
                    clubNumbersCard
                    actionsCard
                } else {
                    noProfileCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("About Me")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if profile != nil {
                    Button("Edit") {
                        showEditSheet = true
                    }
                    .accessibilityLabel("Edit profile")
                }
            }
        }
        .onAppear {
            loadProfile()
        }
        .task(id: profile?.callsign) {
            await loadClubNumbers()
            await refreshCallsignInfo()
        }
        .onDisappear {
            Task { await saveAllClubNumbers() }
        }
        .sheet(isPresented: $showEditSheet) {
            if let profile {
                EditProfileSheet(profile: profile) { updated in
                    saveProfile(updated)
                }
            }
        }
        .sheet(isPresented: $showCallsignChangeGuide) {
            NavigationStack {
                CallsignChangeGuideView()
            }
        }
        .alert("Profile Updated", isPresented: $showSaveSuccess) {
            Button("OK") {}
        } message: {
            Text("Your profile has been updated.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Refresh Profile?", isPresented: $showRefreshConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Refresh") {
                Task { await refreshProfile() }
            }
        } message: {
            Text("This will look up your information from HamDB and update your profile.")
        }
    }

    func loadProfile() {
        profile = profileService.getProfile()
    }

    // MARK: Private

    @State private var showEditSheet = false

    /// Run a callsign lookup for the operator's own callsign so we can
    /// surface the QRZ nickname / displayName / emoji on the identity
    /// card. Streams the cached row first (instant from disk) and a
    /// second emission once QRZ/HamDB enriches.
    private func refreshCallsignInfo() async {
        guard let callsign = profile?.callsign, !callsign.isEmpty else {
            callsignInfo = nil
            return
        }
        let service = CallsignLookupService(modelContext: modelContext)
        for await result in service.lookupStream(callsign) {
            guard !Task.isCancelled else {
                return
            }
            if let info = result.info {
                callsignInfo = info
            }
        }
    }

    private func saveProfile(_ updated: UserProfile) {
        do {
            try profileService.saveProfile(updated)
            profile = updated
            showSaveSuccess = true
        } catch {
            errorMessage = "Failed to save profile: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AboutMeView()
    }
}
