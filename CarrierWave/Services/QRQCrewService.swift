// QRQ Crew Service
//
// Detects QRQ Crew membership from callsign notes and posts spot messages
// when both operators in a QSO are members during a POTA activation.

import Foundation
import SwiftData

// MARK: - QRQCrewMemberInfo

/// Extracted QRQ Crew member info from callsign notes
struct QRQCrewMemberInfo: Sendable {
    let callsign: String
    let name: String
    let memberNumber: String

    /// Display string for spot message (e.g., "Jay #10")
    var displayLabel: String {
        if !memberNumber.isEmpty, name.contains(memberNumber) {
            return name
        }
        return "\(name) \(memberNumber)"
    }
}

// MARK: - QRQCrewSpotInfo

/// Pending QRQ Crew spot data, ready for posting
struct QRQCrewSpotInfo {
    let myInfo: QRQCrewMemberInfo
    let theirInfo: QRQCrewMemberInfo
    let parkReference: String

    /// Build the spot comment for a given WPM
    func spotComment(wpm: Int) -> String {
        "\(myInfo.displayLabel) just worked \(theirInfo.displayLabel)"
            + " at \(wpm) WPM. Learn more at https://qrqcrew.club/"
    }
}

// MARK: - QRQCrewService

enum QRQCrewService {
    // MARK: Internal

    static let sourceTitle = "QRQ Crew"
    static let membersURL = "https://qrqcrew.club/members.txt"

    /// Seed the QRQ Crew callsign notes source if it doesn't already exist.
    /// Must be called on @MainActor.
    @MainActor
    static func seedNotesSourceIfNeeded(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<CallsignNotesSource>()
        guard let sources = try? modelContext.fetch(descriptor) else {
            return
        }

        let alreadyExists = sources.contains { $0.url == membersURL }
        guard !alreadyExists else {
            return
        }

        let source = CallsignNotesSource(title: sourceTitle, url: membersURL)
        modelContext.insert(source)
        try? modelContext.save()
    }

    /// Check if both the user and the other operator are QRQ Crew members.
    /// Returns spot info if both are members, nil otherwise.
    /// Uses the callsign notes cache (matchingSources) for membership
    /// and nicknames for display names.
    static func checkMembership(
        myCallsign: String,
        theirCallsign: String
    ) async -> QRQCrewSpotInfo? {
        let myBase = extractBaseCallsign(myCallsign)
        let theirBase = extractBaseCallsign(theirCallsign)

        let myNotes = await lookupNotes(myCallsign, base: myBase)
        let theirNotes = await lookupNotes(theirCallsign, base: theirBase)

        guard let myNotes, isMember(myNotes),
              let theirNotes, isMember(theirNotes)
        else {
            return nil
        }

        let myInfo = memberInfo(callsign: myBase, from: myNotes)
        let theirInfo = memberInfo(callsign: theirBase, from: theirNotes)

        return QRQCrewSpotInfo(
            myInfo: myInfo,
            theirInfo: theirInfo,
            parkReference: ""
        )
    }

    // MARK: Private

    /// Look up callsign in notes cache, falling back to base callsign
    private static func lookupNotes(
        _ callsign: String,
        base: String
    ) async -> CallsignInfo? {
        if let info = await CallsignNotesCache.shared.info(for: callsign) {
            return info
        }
        if base != callsign.uppercased() {
            return await CallsignNotesCache.shared.info(for: base)
        }
        return nil
    }

    /// Check if a notes entry has QRQ Crew as a matching source
    private static func isMember(_ info: CallsignInfo) -> Bool {
        info.matchingSources?.contains(sourceTitle) ?? false
    }

    /// Build member info from notes entry, using nickname for display name
    private static func memberInfo(
        callsign: String,
        from info: CallsignInfo
    ) -> QRQCrewMemberInfo {
        // Extract member number from name/note text if available
        let combined = [info.name, info.note].compactMap { $0 }.joined(separator: " ")
        let memberNumber = extractMemberNumber(from: combined) ?? ""

        // Prefer nickname > firstName > name from notes
        let displayName = info.nickname?.capitalized
            ?? info.firstName?.capitalized
            ?? info.displayName
            ?? callsign

        return QRQCrewMemberInfo(
            callsign: callsign,
            name: displayName,
            memberNumber: memberNumber
        )
    }

    /// Extract base callsign by stripping known prefix/suffix patterns
    private static func extractBaseCallsign(_ callsign: String) -> String {
        let parts = callsign.uppercased().split(separator: "/").map(String.init)
        guard parts.count > 1 else {
            return callsign.uppercased()
        }

        let knownSuffixes: Set<String> = [
            "P", "M", "MM", "AM", "QRP", "R", "A", "B", "LH", "LGT",
        ]

        if parts.count == 2 {
            let first = parts[0]
            let second = parts[1]
            if knownSuffixes.contains(second) || second.count <= 2 {
                return first
            }
            if first.count <= 3, !first.contains(where: \.isNumber) {
                return second
            }
            return first.count >= second.count ? first : second
        }

        return parts.max(by: { $0.count < $1.count }) ?? callsign.uppercased()
    }

    /// Extract "#NN" member number pattern from text
    private static func extractMemberNumber(from text: String) -> String? {
        guard let range = text.range(of: #"#\d+"#, options: .regularExpression) else {
            return nil
        }
        return String(text[range])
    }
}
