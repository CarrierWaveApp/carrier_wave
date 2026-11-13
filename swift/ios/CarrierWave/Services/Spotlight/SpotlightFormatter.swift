import UIKit

// MARK: - SpotlightFormatter

/// Pure formatting helpers for building CoreSpotlight titles, descriptions,
/// and keywords from snapshot value types.
///
/// Separated from the snapshots so the building logic can be unit tested and
/// so the snapshot files stay focused on data shape.
///
/// `nonisolated` so the helpers can be called from the snapshot types'
/// `makeAttributeSet()` methods, which run on background actors during
/// Spotlight reindexing. The iOS target uses `SWIFT_DEFAULT_ACTOR_ISOLATION
/// =MainActor`, so without this annotation the static methods would be
/// inferred as `@MainActor`.
nonisolated enum SpotlightFormatter {
    // MARK: Internal

    // MARK: - QSO

    static func qsoTitle(callsign: String, band: String, mode: String) -> String {
        var parts: [String] = [callsign]
        if !band.isEmpty {
            parts.append(band)
        }
        if !mode.isEmpty {
            parts.append(mode.uppercased())
        }
        return parts.joined(separator: " · ")
    }

    static func qsoDescription(snapshot: QSOSpotlightSnapshot) -> String {
        var parts: [String] = []
        parts.append(descriptionDateFormatter.string(from: snapshot.timestamp))

        if let sent = snapshot.rstSent?.trimmed, let received = snapshot.rstReceived?.trimmed {
            parts.append("RST \(sent)/\(received)")
        } else if let sent = snapshot.rstSent?.trimmed {
            parts.append("Sent \(sent)")
        } else if let received = snapshot.rstReceived?.trimmed {
            parts.append("Rcvd \(received)")
        }

        if let name = snapshot.name?.trimmed {
            parts.append(name)
        }
        if let location = joinLocation(
            qth: snapshot.qth, state: snapshot.state, country: snapshot.country
        ) {
            parts.append(location)
        }
        if let park = snapshot.parkReference?.trimmed {
            parts.append(park)
        }
        return parts.joined(separator: " • ")
    }

    static func qsoKeywords(snapshot: QSOSpotlightSnapshot) -> [String] {
        var keywords: Set<String> = []
        keywords.insert(snapshot.callsign)
        keywords.insert(snapshot.myCallsign)
        if !snapshot.band.isEmpty {
            keywords.insert(snapshot.band)
        }
        if !snapshot.mode.isEmpty {
            keywords.insert(snapshot.mode)
        }
        [
            snapshot.parkReference,
            snapshot.sotaRef,
            snapshot.wwffRef,
            snapshot.myGrid,
            snapshot.theirGrid,
            snapshot.state,
            snapshot.country,
        ].forEach { value in
            if let trimmed = value?.trimmed {
                keywords.insert(trimmed)
            }
        }
        if let dxcc = snapshot.dxcc {
            keywords.insert("DXCC\(dxcc)")
        }
        return keywords.filter { !$0.isEmpty }.sorted()
    }

    // MARK: - Session

    static func sessionTitle(
        programDisplayName: String,
        parkReference: String?,
        sotaReference: String?,
        customTitle: String?,
        startedAt: Date
    ) -> String {
        if let custom = customTitle?.trimmed {
            return custom
        }
        let reference = parkReference?.trimmed ?? sotaReference?.trimmed
        let dateString = sessionDateFormatter.string(from: startedAt)
        if let reference {
            return "\(programDisplayName): \(reference) (\(dateString))"
        }
        return "\(programDisplayName) session (\(dateString))"
    }

    static func sessionDescription(snapshot: SessionSpotlightSnapshot) -> String {
        var parts: [String] = []
        parts.append(snapshot.myCallsign)
        parts.append("\(snapshot.qsoCount) QSO\(snapshot.qsoCount == 1 ? "" : "s")")
        if !snapshot.mode.isEmpty {
            parts.append(snapshot.mode.uppercased())
        }
        if let rig = snapshot.myRig?.trimmed {
            parts.append(rig)
        }
        if let antenna = snapshot.myAntenna?.trimmed {
            parts.append(antenna)
        }
        if let key = snapshot.myKey?.trimmed {
            parts.append(key)
        }
        return parts.joined(separator: " • ")
    }

    static func sessionKeywords(snapshot: SessionSpotlightSnapshot) -> [String] {
        var keywords: Set<String> = []
        keywords.insert(snapshot.myCallsign)
        keywords.insert(snapshot.programDisplayName)
        keywords.insert(snapshot.activationTypeRaw)
        if !snapshot.mode.isEmpty {
            keywords.insert(snapshot.mode)
        }
        [
            snapshot.parkReference,
            snapshot.sotaReference,
            snapshot.wwffReference,
            snapshot.missionReference,
            snapshot.myRig,
            snapshot.myAntenna,
        ].forEach { value in
            if let trimmed = value?.trimmed {
                keywords.insert(trimmed)
            }
        }
        return keywords.filter { !$0.isEmpty }.sorted()
    }

    // MARK: Private

    // MARK: - Formatters

    private static let descriptionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static func joinLocation(
        qth: String?, state: String?, country: String?
    ) -> String? {
        let parts = [qth, state, country]
            .compactMap { $0?.trimmed }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - String helpers

private extension String {
    nonisolated var trimmed: String? {
        let result = trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
