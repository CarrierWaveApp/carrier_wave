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
        "\(name) \(memberNumber)"
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
            + " at \(wpm) WPM. Learn more at https://carrierwave.app/"
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
    static func checkMembership(
        myCallsign: String,
        theirCallsign: String
    ) async -> QRQCrewSpotInfo? {
        guard let myNotes = await CallsignNotesCache.shared.info(for: myCallsign),
              let theirNotes = await CallsignNotesCache.shared.info(for: theirCallsign)
        else {
            return nil
        }

        guard let myInfo = extractMemberInfo(from: myNotes),
              let theirInfo = extractMemberInfo(from: theirNotes)
        else {
            return nil
        }

        // No park reference needed here; caller supplies it
        return QRQCrewSpotInfo(
            myInfo: myInfo,
            theirInfo: theirInfo,
            parkReference: ""
        )
    }

    // MARK: Private

    /// Extract QRQ Crew member info from a CallsignInfo, if it matches.
    /// Checks matchingSources for "QRQ Crew" and parses name + member number.
    private static func extractMemberInfo(from info: CallsignInfo) -> QRQCrewMemberInfo? {
        // Must have QRQ Crew as a matching source
        guard let sources = info.matchingSources,
              sources.contains(where: { $0 == sourceTitle })
        else {
            return nil
        }

        // Try to extract member number (#NN) from name or note
        let combined = [info.name, info.note].compactMap { $0 }.joined(separator: " ")
        guard let memberNumber = extractMemberNumber(from: combined) else {
            return nil
        }

        // Extract the name (text before the member number)
        let name = extractName(from: combined, memberNumber: memberNumber)
        guard !name.isEmpty else {
            return nil
        }

        return QRQCrewMemberInfo(
            callsign: info.callsign,
            name: name,
            memberNumber: memberNumber
        )
    }

    /// Extract "#NN" member number pattern from text
    private static func extractMemberNumber(from text: String) -> String? {
        guard let range = text.range(of: #"#\d+"#, options: .regularExpression) else {
            return nil
        }
        return String(text[range])
    }

    /// Extract the display name (everything before the member number, cleaned up)
    private static func extractName(from text: String, memberNumber: String) -> String {
        guard let range = text.range(of: memberNumber) else {
            return text.trimmingCharacters(in: .whitespaces)
        }
        return text[..<range.lowerBound]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
    }
}
