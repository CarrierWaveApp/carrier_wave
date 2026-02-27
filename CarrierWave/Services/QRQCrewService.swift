// QRQ Crew Service
//
// Detects QRQ Crew membership from callsign notes and posts spot messages
// when both operators in a QSO are members during a POTA activation.
// Membership is checked by downloading the members list by URL,
// independent of callsign notes cache titles.

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
    /// Fastest WPM seen from RBN spots (auto-populated into the speed field)
    let rbnWPM: Int?

    /// Build the spot comment for a given WPM
    func spotComment(wpm: Int) -> String {
        "\(myInfo.displayLabel) just worked \(theirInfo.displayLabel)"
            + " at \(wpm) WPM. Learn more at https://qrqcrew.club/"
    }
}

// MARK: - QRQCrewMemberCache

/// Caches the set of QRQ Crew member callsigns loaded directly from the URL.
/// Independent of the callsign notes cache and its source titles.
actor QRQCrewMemberCache {
    // MARK: Internal

    static let shared = QRQCrewMemberCache()

    func ensureLoaded() async {
        guard !isLoaded else {
            return
        }
        isLoaded = true

        guard let url = URL(string: QRQCrewService.membersURL) else {
            return
        }
        do {
            entries = try await PoloNotesParser.load(from: url)
        } catch {
            print("QRQCrewMemberCache: failed to load: \(error)")
        }
    }

    func isMember(_ callsign: String) -> Bool {
        entries[callsign.uppercased()] != nil
    }

    func info(for callsign: String) -> CallsignInfo? {
        entries[callsign.uppercased()]
    }

    // MARK: Private

    /// Parsed member entries keyed by uppercase callsign
    private var entries: [String: CallsignInfo] = [:]
    private var isLoaded = false
}

// MARK: - QRQCrewService

enum QRQCrewService {
    // MARK: Internal

    nonisolated static let sourceTitle = "QRQ Crew"
    nonisolated static let membersURL = "https://qrqcrew.club/members.txt"
    /// Minimum CW speed for a valid QRQ Crew contact
    nonisolated static let minimumWPM = 35

    /// Seed the QRQ Crew callsign notes source if it doesn't already exist.
    /// If the URL exists but with a different title, corrects the title.
    @MainActor
    static func seedNotesSourceIfNeeded(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<CallsignNotesSource>()
        guard let sources = try? modelContext.fetch(descriptor) else {
            return
        }

        if let existing = sources.first(where: { $0.url == membersURL }) {
            if existing.title != sourceTitle {
                existing.title = sourceTitle
                try? modelContext.save()
            }
            return
        }

        let source = CallsignNotesSource(title: sourceTitle, url: membersURL)
        modelContext.insert(source)
        try? modelContext.save()
    }

    /// Check if both the user and the other operator are QRQ Crew members.
    /// Returns spot info only if both are members AND both have a QRZ
    /// nickname and a QRQ Crew member number. Returns nil otherwise.
    static func checkMembership(
        myCallsign: String,
        theirCallsign: String,
        myQRZInfo: CallsignInfo? = nil,
        theirQRZInfo: CallsignInfo? = nil
    ) async -> QRQCrewSpotInfo? {
        let myBase = extractBaseCallsign(myCallsign)
        let theirBase = extractBaseCallsign(theirCallsign)

        // Check membership from the QRQ Crew URL directly
        let cache = QRQCrewMemberCache.shared
        await cache.ensureLoaded()

        guard await cache.isMember(myBase),
              await cache.isMember(theirBase)
        else {
            return nil
        }

        // Build member info — requires both nickname and member number
        guard let myInfo = await memberInfo(callsign: myBase, qrzInfo: myQRZInfo),
              let theirInfo = await memberInfo(callsign: theirBase, qrzInfo: theirQRZInfo)
        else {
            return nil
        }

        return QRQCrewSpotInfo(
            myInfo: myInfo,
            theirInfo: theirInfo,
            parkReference: "",
            rbnWPM: nil
        )
    }

    // MARK: Private

    /// Build member info from QRZ nickname and QRQ Crew member number.
    /// Returns nil if either the QRZ nickname or QRQ member number is missing.
    private static func memberInfo(
        callsign: String,
        qrzInfo: CallsignInfo?
    ) async -> QRQCrewMemberInfo? {
        // QRQ Crew member cache — authoritative for member data
        let qrqInfo = await QRQCrewMemberCache.shared.info(for: callsign)

        // Require QRQ Crew member number
        let qrqText = [qrqInfo?.name, qrqInfo?.note]
            .compactMap { $0 }.joined(separator: " ")
        guard let memberNumber = extractMemberNumber(from: qrqText) else {
            return nil
        }

        // Require QRZ nickname
        guard let nickname = qrzInfo?.nickname ?? qrzInfo?.firstName else {
            return nil
        }

        return QRQCrewMemberInfo(
            callsign: callsign,
            name: nickname.capitalized,
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

    /// Extract display name from QRQ Crew entry, stripping "QC" and "#NN".
    /// e.g., "James S QC #10" → "James S"
    private static func extractDisplayName(from info: CallsignInfo?) -> String? {
        guard let name = info?.name, !name.isEmpty else {
            return nil
        }
        let cleaned = name
            .replacingOccurrences(of: #"\s*#\d+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\bQC\b"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Extract member designation from text, e.g., "QC #10" from "James S QC #10"
    private static func extractMemberNumber(from text: String) -> String? {
        // Try "QC #NN" first, then bare "#NN"
        if let range = text.range(of: #"QC\s*#\d+"#, options: .regularExpression) {
            return String(text[range])
        }
        guard let range = text.range(of: #"#\d+"#, options: .regularExpression) else {
            return nil
        }
        return String(text[range])
    }
}
