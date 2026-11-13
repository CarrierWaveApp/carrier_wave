import CarrierWaveData
import SwiftUI

// MARK: - IdentityCardContent

/// Pure data model for the IdentityCard. Surfaces build one of these
/// from whichever source they have (UserProfile, CallsignInfo +
/// Friendship) and hand it to IdentityCard.
struct IdentityCardContent {
    // MARK: Lifecycle

    init(
        callsign: String,
        flag: String? = nil,
        emoji: String? = nil,
        licenseClass: String? = nil,
        heroSubtitle: String? = nil,
        bottomStripText: String? = nil,
        factTiles: [FactTile] = [],
        clubBadges: [String] = [],
        footnote: Footnote? = nil,
        isLookingUp: Bool = false
    ) {
        self.callsign = callsign.uppercased()
        self.flag = flag
        self.emoji = emoji
        self.licenseClass = licenseClass
        self.heroSubtitle = heroSubtitle
        self.bottomStripText = bottomStripText
        self.factTiles = factTiles
        self.clubBadges = clubBadges
        self.footnote = footnote
        self.isLookingUp = isLookingUp
    }

    // MARK: Internal

    struct FactTile: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let value: String
        let tint: Color
    }

    struct Footnote {
        let text: String
        let systemImage: String
        let color: Color
    }

    let callsign: String
    let flag: String?
    let emoji: String?
    let licenseClass: String?
    let heroSubtitle: String?
    let bottomStripText: String?
    let factTiles: [FactTile]
    let clubBadges: [String]
    let footnote: Footnote?
    let isLookingUp: Bool
}

// MARK: - Factories

extension IdentityCardContent {
    /// Build content for the operator's local UserProfile. Used by AboutMeView.
    /// `info` is an optional fresh callsign lookup (QRZ-first via
    /// `CallsignLookupService`) — when present, its nickname/displayName
    /// and emoji take precedence over the local profile's name fields so
    /// the user sees the same identity treatment as on CallsignHistoryView.
    /// `clubs` is the surface's already-fetched club name list. SKCC is
    /// appended automatically.
    static func fromOwnProfile(
        _ profile: UserProfile,
        info: CallsignInfo? = nil,
        changeNote: String? = nil,
        clubs: [String] = []
    ) -> IdentityCardContent {
        let footnote = changeNote.map { note in
            Footnote(
                text: note,
                systemImage: "arrow.triangle.2.circlepath",
                color: .orange
            )
        }
        let previousCallsigns = CallsignAliasService.shared.getPreviousCallsigns()
            .map { $0.uppercased() }
            .filter { $0 != profile.callsign }

        return IdentityCardContent(
            callsign: profile.callsign,
            flag: CallsignFlagHelper.countryFlag(for: profile.callsign),
            emoji: info?.combinedEmoji,
            licenseClass: profile.licenseClass?.displayName ?? info?.licenseClass,
            heroSubtitle: ownProfileSubtitle(profile: profile, info: info),
            bottomStripText: profile.country ?? info?.country,
            factTiles: ownProfileTiles(profile: profile),
            clubBadges: mergedClubMemberships(
                for: profile.callsign,
                explicit: clubs,
                previousCallsigns: previousCallsigns
            ),
            footnote: footnote,
            isLookingUp: false
        )
    }

    /// Build content from a callsign + lookup info + optional friendship
    /// status. Used by CallsignHistoryView for any callsign (own or other).
    /// `clubs` is the surface's already-fetched club name list (from
    /// `ClubMember` rows for this callsign and any previous callsign).
    /// SKCC is appended automatically. `ownProfile`, when supplied (i.e.
    /// the displayed callsign is the operator's own callsign), takes
    /// precedence for subtitle / first-name display so the user sees
    /// their preferred nickname instead of whatever QRZ/HamDB returned.
    static func fromLookup(
        callsign: String,
        info: CallsignInfo?,
        friendship: Friendship?,
        isLookingUp: Bool,
        clubs: [String] = [],
        ownProfile: UserProfile? = nil
    ) -> IdentityCardContent {
        let subtitle: String? = ownProfile.map { ownProfileSubtitle(profile: $0, info: info) }
            ?? info?.displayName
        let previous = lookupPreviousCallsigns(callsign: callsign, info: info, ownProfile: ownProfile)

        return IdentityCardContent(
            callsign: callsign,
            flag: CallsignFlagHelper.countryFlag(for: callsign),
            emoji: info?.combinedEmoji,
            licenseClass: ownProfile?.licenseClass?.displayName ?? info?.licenseClass,
            heroSubtitle: subtitle,
            bottomStripText: ownProfile?.country ?? info?.country,
            factTiles: lookupTiles(info: info),
            clubBadges: mergedClubMemberships(
                for: callsign,
                explicit: clubs,
                previousCallsigns: previous
            ),
            footnote: friendshipFootnote(friendship),
            isLookingUp: isLookingUp
        )
    }

    /// For the operator's own profile, prefer their locally-edited
    /// nickname / first name (in `UserProfile`) over whatever QRZ or
    /// HamDB returned. The user explicitly typed it; respect it.
    static func ownProfileSubtitle(profile: UserProfile, info: CallsignInfo?) -> String? {
        let trimmed = profile.firstName?.trimmingCharacters(in: .whitespaces) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        if let nickname = info?.nickname, !nickname.isEmpty {
            return nickname.capitalized
        }
        return profile.fullName ?? info?.displayName
    }

    private static func ownProfileTiles(profile: UserProfile) -> [FactTile] {
        var tiles: [FactTile] = []
        if let grid = profile.grid, !grid.isEmpty {
            tiles.append(FactTile(icon: "square.grid.3x3", label: "Grid", value: grid, tint: .blue))
        }
        if let city = profile.city, !city.isEmpty {
            tiles.append(FactTile(icon: "building.2", label: "City", value: city, tint: .blue))
        }
        if let state = profile.state, !state.isEmpty {
            tiles.append(FactTile(icon: "map", label: "State", value: state, tint: .blue))
        }
        if let expires = profile.licenseExpires, !expires.isEmpty {
            tiles.append(FactTile(icon: "calendar", label: "Expires", value: expires, tint: .purple))
        }
        return tiles
    }

    private static func lookupTiles(info: CallsignInfo?) -> [FactTile] {
        var tiles: [FactTile] = []
        if let grid = info?.grid, !grid.isEmpty {
            tiles.append(FactTile(icon: "square.grid.3x3", label: "Grid", value: grid, tint: .blue))
        }
        if let qth = info?.qth, !qth.isEmpty {
            tiles.append(FactTile(icon: "building.2", label: "City", value: qth, tint: .blue))
        }
        if let state = info?.state, !state.isEmpty {
            tiles.append(FactTile(icon: "map", label: "State", value: state, tint: .blue))
        }
        if let previous = info?.previousCallsign, !previous.isEmpty {
            tiles.append(
                FactTile(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Was",
                    value: previous,
                    tint: .purple
                )
            )
        }
        return tiles
    }

    private static func lookupPreviousCallsigns(
        callsign: String,
        info: CallsignInfo?,
        ownProfile: UserProfile?
    ) -> [String] {
        var previous: [String] = []
        if ownProfile != nil {
            previous += CallsignAliasService.shared.getPreviousCallsigns()
                .map { $0.uppercased() }
        }
        if let prev = info?.previousCallsign?.uppercased(), !prev.isEmpty {
            previous.append(prev)
        }
        return Array(Set(previous).subtracting([callsign.uppercased()]))
    }

    /// Merge the surface-supplied club list with the in-memory cache and
    /// the SKCC roster. Surfaces that have a fresh SwiftData fetch should
    /// pass it via `explicit`; surfaces that don't can pass an empty
    /// list and rely on `ClubsSyncService.shared.clubs(for:)`.
    /// `previousCallsigns` extends the SKCC and cache lookups to cover
    /// callsigns the user used before — important when the SKCC roster
    /// has them under an old call that the alias resolution hasn't
    /// caught up to.
    private static func mergedClubMemberships(
        for callsign: String,
        explicit: [String],
        previousCallsigns: [String] = []
    ) -> [String] {
        var clubs = explicit
        if clubs.isEmpty {
            clubs = ClubsSyncService.shared.clubs(for: callsign)
            for previous in previousCallsigns {
                let extra = ClubsSyncService.shared.clubs(for: previous)
                for name in extra where !clubs.contains(name) {
                    clubs.append(name)
                }
            }
        }
        var seen = Set<String>(clubs.map { $0.uppercased() })
        let skccCandidates = [callsign] + previousCallsigns
        let inSKCC = skccCandidates.contains { call in
            SKCCMembershipStore.shared.member(for: call) != nil
        }
        if inSKCC, !seen.contains("SKCC") {
            clubs.append("SKCC")
            seen.insert("SKCC")
        }
        return clubs
    }

    private static func friendshipFootnote(_ friendship: Friendship?) -> Footnote? {
        guard let friendship else {
            return nil
        }
        if friendship.isAccepted {
            let dateText = friendship.acceptedAt?
                .formatted(date: .abbreviated, time: .omitted) ?? "recently"
            return Footnote(
                text: "Friends since \(dateText)",
                systemImage: "person.2.fill",
                color: .secondary
            )
        }
        if friendship.isPending {
            return Footnote(
                text: friendship.isOutgoing ? "Friend request sent" : "Friend request received",
                systemImage: "clock",
                color: .secondary
            )
        }
        return nil
    }
}
