// User Profile Service
//
// Manages persistence and retrieval of the user's amateur radio profile.
// Profile data is stored in the keychain for security and persistence.

import Foundation

// MARK: - UserProfileService

/// Service for managing the user's profile
@MainActor
final class UserProfileService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = UserProfileService()

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
    }

    /// Clear the user's profile
    func clearProfile() throws {
        try keychain.delete(for: KeychainHelper.Keys.userProfile)
    }

    /// Check if a profile exists
    func hasProfile() -> Bool {
        getProfile() != nil
    }

    /// Result of a profile lookup with optional callsign change detection
    struct ProfileLookupResult {
        let profile: UserProfile?
        /// Note when HamDB shows a different name than QRZ (callsign recently changed owners)
        let callsignChangeNote: String?
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
}
