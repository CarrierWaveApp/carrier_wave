// User Profile Model
//
// Stores the user's amateur radio profile information, populated from HamDB lookup
// and editable by the user. Used throughout the app for pre-filling forms and services.

import CarrierWaveData
import Foundation

// MARK: - UserProfile

/// The user's amateur radio profile
struct UserProfile: Codable, Equatable {
    // MARK: Lifecycle

    init(
        callsign: String,
        firstName: String? = nil,
        lastName: String? = nil,
        city: String? = nil,
        state: String? = nil,
        country: String? = nil,
        grid: String? = nil,
        licenseClass: LicenseClass? = nil,
        licenseExpires: String? = nil
    ) {
        self.callsign = callsign.uppercased()
        self.firstName = firstName
        self.lastName = lastName
        self.city = city
        self.state = state
        self.country = country
        self.grid = grid
        self.licenseClass = licenseClass
        self.licenseExpires = licenseExpires
    }

    // MARK: Internal

    /// The user's callsign (always uppercase)
    let callsign: String

    /// First name
    var firstName: String?

    /// Last name
    var lastName: String?

    /// City/QTH
    var city: String?

    /// State/province
    var state: String?

    /// Country
    var country: String?

    /// Grid square (Maidenhead)
    var grid: String?

    /// License class
    var licenseClass: LicenseClass?

    /// License expiration date (from FCC)
    var licenseExpires: String?

    /// Full name (first + last)
    var fullName: String? {
        let parts = [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Full location (city, state, country)
    var fullLocation: String? {
        let parts = [city, state, country].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Short location (city, state) or just country if no city/state
    var shortLocation: String? {
        let cityState = [city, state].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !cityState.isEmpty {
            return cityState.joined(separator: ", ")
        }
        return country
    }
}

// MARK: - UserProfile + HamDB

extension UserProfile {
    /// Create a UserProfile from a HamDB license lookup result
    static func fromHamDB(_ license: HamDBLicense) -> UserProfile? {
        guard let callsign = license.call, !callsign.isEmpty else {
            return nil
        }

        return UserProfile(
            callsign: callsign,
            firstName: license.fname,
            lastName: license.name,
            city: license.city,
            state: license.state,
            country: license.country,
            grid: license.grid,
            licenseClass: license.parsedLicenseClass,
            licenseExpires: license.expires
        )
    }
}
