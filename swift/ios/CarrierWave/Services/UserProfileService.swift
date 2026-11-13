// User Profile Service
//
// Manages persistence and retrieval of the user's amateur radio profile.
// Profile data is stored in the keychain for security and persistence.

import CarrierWaveData
import Foundation
import OSLog

// MARK: - UserProfileService

/// Service for managing the user's profile
@MainActor
final class UserProfileService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    /// Result of a profile lookup with optional callsign change detection
    struct ProfileLookupResult {
        let profile: UserProfile?
        /// Note when HamDB shows a different name than QRZ (callsign recently changed owners)
        let callsignChangeNote: String?
    }

    static let shared = UserProfileService()

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "UserProfileService"
    )

    /// Get the user's profile
    func getProfile() -> UserProfile? {
        do {
            let data = try keychain.read(for: KeychainHelper.Keys.userProfile)
            return try JSONDecoder().decode(UserProfile.self, from: data)
        } catch {
            return nil
        }
    }

    /// Save the user's profile
    func saveProfile(_ profile: UserProfile) throws {
        let data = try JSONEncoder().encode(profile)
        try keychain.save(data, for: KeychainHelper.Keys.userProfile)

        // Keep CallsignAliasService in sync
        let aliasService = CallsignAliasService.shared
        if aliasService.getCurrentCallsign() != profile.callsign {
            try aliasService.saveCurrentCallsign(profile.callsign)
        }

        // Update AppStorage values for license class and grid
        if let licenseClass = profile.licenseClass {
            UserDefaults.standard.set(licenseClass.rawValue, forKey: "userLicenseClass")
        }
        if let grid = profile.grid {
            UserDefaults.standard.set(grid, forKey: "loggerDefaultGrid")
        }
        UserDefaults.standard.set(profile.callsign, forKey: "loggerDefaultCallsign")

        // Mirror the operator's first name into UserDefaults so the CW keyer
        // (and any other UI that needs synchronous access) can resolve
        // `{MYNAME}` without round-tripping through the keychain.
        let firstName = profile.firstName?.trimmingCharacters(in: .whitespaces) ?? ""
        if firstName.isEmpty {
            UserDefaults.standard.removeObject(forKey: "loggerDefaultName")
        } else {
            UserDefaults.standard.set(firstName, forKey: "loggerDefaultName")
        }
    }

    /// Clear the user's profile
    func clearProfile() throws {
        try keychain.delete(for: KeychainHelper.Keys.userProfile)
    }

    /// Check if a profile exists
    func hasProfile() -> Bool {
        getProfile() != nil
    }

    /// One-shot backfill so screens that read identity defaults (e.g. the
    /// CW keyer's `{MYNAME}` macro) work for users who saved their profile
    /// before `saveProfile` started mirroring `firstName` to UserDefaults.
    /// No-op if the default is already set or the profile lacks a first name.
    func backfillDefaultsFromProfileIfNeeded() {
        let key = "loggerDefaultName"
        let existing = (UserDefaults.standard.string(forKey: key) ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard existing.isEmpty else {
            return
        }
        guard let firstName = getProfile()?.firstName?.trimmingCharacters(in: .whitespaces),
              !firstName.isEmpty
        else {
            return
        }
        UserDefaults.standard.set(firstName, forKey: key)
    }

    /// Reconcile the three callsign stores toward the canonical value.
    ///
    /// `UserProfile.callsign` is the single source of truth. The Keychain
    /// (`currentCallsign`) and UserDefaults (`loggerDefaultCallsign`) are
    /// derived caches — they are only ever written FROM the profile, never
    /// the reverse. This heals any stale or fat-fingered value that landed
    /// in the iCloud-synced Keychain (e.g. a half-typed callsign committed
    /// by an old CW Sweep build) and would otherwise resurrect on every
    /// launch (CAR-287).
    ///
    /// When no profile exists yet, falls back to the legacy Keychain →
    /// UserDefaults sync so fresh installs still pick up a callsign that
    /// survived reinstall in the Keychain.
    func reconcileCallsignStores() {
        let aliasService = CallsignAliasService.shared

        guard let profile = getProfile(), !profile.callsign.isEmpty else {
            aliasService.syncCallsignToUserDefaults()
            return
        }

        let canonical = profile.callsign.uppercased().trimmingCharacters(in: .whitespaces)
        guard !canonical.isEmpty else {
            return
        }

        if aliasService.getCurrentCallsign() != canonical {
            try? aliasService.saveCurrentCallsign(canonical)
        }
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "loggerDefaultCallsign") != canonical {
            defaults.set(canonical, forKey: "loggerDefaultCallsign")
        }
        // Purge the legacy phantom "callsign" key. Nothing writes it anymore, but
        // pre-CAR-287 builds left a stale (sometimes fat-fingered) value that a
        // few display surfaces used to read. Clear it so it can never resurface.
        if defaults.object(forKey: "callsign") != nil {
            defaults.removeObject(forKey: "callsign")
        }
    }

    /// Update the canonical callsign from a settings edit, propagating to
    /// the profile (when one exists) and the derived Keychain/UserDefaults
    /// caches. Without a profile, writes the caches directly.
    func setCallsign(_ callsign: String) throws {
        let normalized = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else {
            throw CallsignAliasError.invalidCallsign
        }

        if let existingProfile = getProfile() {
            guard existingProfile.callsign != normalized else {
                return
            }
            let updatedProfile = UserProfile(
                callsign: normalized,
                firstName: existingProfile.firstName,
                lastName: existingProfile.lastName,
                city: existingProfile.city,
                state: existingProfile.state,
                country: existingProfile.country,
                grid: existingProfile.grid,
                licenseClass: existingProfile.licenseClass,
                licenseExpires: existingProfile.licenseExpires
            )
            try saveProfile(updatedProfile)
        } else {
            try CallsignAliasService.shared.saveCurrentCallsign(normalized)
        }
    }

    /// Detect if a callsign from QRZ differs from the stored current callsign,
    /// and propagate the change to all stores (alias service, profile, UserDefaults).
    /// Returns the old callsign if a change was applied, nil if no change needed.
    @discardableResult
    func applyCallsignChangeIfNeeded(newCallsign: String) throws -> String? {
        let normalized = newCallsign.uppercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else {
            return nil
        }

        let aliasService = CallsignAliasService.shared
        let currentCallsign = aliasService.getCurrentCallsign()

        // No change needed — callsigns match or first-time setup
        guard let currentCallsign, currentCallsign != normalized else {
            if currentCallsign == nil {
                try aliasService.saveCurrentCallsign(normalized)
                updateDefaultCallsign(normalized)
            }
            return nil
        }

        // Move old callsign to previous callsigns list. If the user is
        // deliberately switching back to a callsign they had retired, it is
        // current again, so it must leave the previous list — otherwise the
        // detected-callsign guard above would treat it as stale.
        try aliasService.addPreviousCallsign(currentCallsign)
        try aliasService.removePreviousCallsign(normalized)

        // Set the new callsign as current
        try aliasService.saveCurrentCallsign(normalized)

        // Surface the connected-services checklist (QRZ keys, LoTW cert,
        // eQSL account, …) until the user works through it
        CallsignChangeGuide.shared.begin(
            oldCallsign: currentCallsign, newCallsign: normalized
        )

        // Update UserProfile with new callsign (preserve other fields)
        if let existingProfile = getProfile() {
            let updatedProfile = UserProfile(
                callsign: normalized,
                firstName: existingProfile.firstName,
                lastName: existingProfile.lastName,
                city: existingProfile.city,
                state: existingProfile.state,
                country: existingProfile.country,
                grid: existingProfile.grid,
                licenseClass: existingProfile.licenseClass,
                licenseExpires: existingProfile.licenseExpires
            )
            try saveProfile(updatedProfile)
        } else {
            // No existing profile — just update UserDefaults
            updateDefaultCallsign(normalized)
        }

        // Sync callsign change to activities server in the background
        Task {
            await syncCallsignChangeToServer(newCallsign: normalized)
        }

        return currentCallsign
    }

    /// Apply a callsign *detected* from a connected service (the callsign a QRZ
    /// Logbook API key belongs to, etc.) rather than typed by the user.
    ///
    /// A detected callsign must never resurrect one the user has explicitly
    /// retired: after Settings → Change Callsign, the QRZ key (and every other
    /// connected service on the change checklist) still reports the OLD call
    /// until the user updates it, and the QRZ sync runs on every launch.
    /// Feeding that value through `applyCallsignChangeIfNeeded` flipped the
    /// profile back on every restart (CAR-349). Returns the old callsign if a
    /// change was applied, nil if the value was ignored or already current.
    @discardableResult
    func applyDetectedCallsignChangeIfNeeded(newCallsign: String) throws -> String? {
        let normalized = newCallsign.uppercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else {
            return nil
        }
        let aliasService = CallsignAliasService.shared
        if aliasService.getCurrentCallsign() != normalized,
           aliasService.getPreviousCallsigns().contains(normalized)
        {
            Self.logger.info(
                "Ignoring detected callsign \(normalized): it is a previous callsign the user moved away from"
            )
            return nil
        }
        return try applyCallsignChangeIfNeeded(newCallsign: normalized)
    }

    /// Notify the activities server about a callsign change.
    /// Best-effort — logs errors but doesn't throw, since the local change already succeeded.
    func syncCallsignChangeToServer(newCallsign: String) async {
        let client = ActivitiesClient()
        // An OAuth session counts: `hasAuthToken()` only sees the legacy `fd_`
        // device token, so OAuth-only accounts never told the server (CAR-349).
        guard await client.hasServerSession() else {
            return
        }

        do {
            let updated = try await client.changeCallsign(to: newCallsign)
            Self.logger.info("Synced callsign change to activities server: \(updated)")
        } catch {
            Self.logger.error("Failed to sync callsign change to server: \(error)")
        }
    }

    /// Look up a callsign via HamDB and create a profile
    func lookupAndCreateProfile(callsign: String) async throws -> UserProfile? {
        let result = try await lookupAndCreateProfileWithChangeDetection(callsign: callsign)
        return result.profile
    }

    /// Look up a callsign via HamDB with QRZ cross-check for callsign change detection
    func lookupAndCreateProfileWithChangeDetection(
        callsign: String
    ) async throws -> ProfileLookupResult {
        let client = HamDBClient()
        let lookupService = CallsignLookupService()

        // Fetch HamDB and QRZ in parallel
        async let hamDBResult = client.lookup(callsign: callsign)
        async let qrzName = lookupService.lookupHamDBComparisonName(callsign: callsign)

        let license = try await hamDBResult
        let qrzFullName = await qrzName

        guard let license else {
            return ProfileLookupResult(
                profile: UserProfile(callsign: callsign),
                callsignChangeNote: nil
            )
        }

        let profile = UserProfile.fromHamDB(license)
        let changeNote = lookupService.detectCallsignChange(
            qrzName: qrzFullName,
            hamDBName: license.fullName
        )

        return ProfileLookupResult(profile: profile, callsignChangeNote: changeNote)
    }

    // MARK: Private

    private let keychain = KeychainHelper.shared

    private func updateDefaultCallsign(_ callsign: String) {
        UserDefaults.standard.set(callsign, forKey: "loggerDefaultCallsign")
    }
}
