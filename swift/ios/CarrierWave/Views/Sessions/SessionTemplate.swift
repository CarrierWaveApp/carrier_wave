import CarrierWaveData
import Foundation

// MARK: - SessionTemplate

struct SessionTemplate: Identifiable {
    // MARK: Internal

    let id: String
    let activationType: ActivationType
    let title: String
    let subtitle: String?
    let mode: String
    let power: Int?
    let parkReference: String?
    let programsRaw: String?
    let count: Int

    static func fromRecentSessions(
        _ sessions: [LoggingSession],
        limit: Int
    ) -> [SessionTemplate] {
        var countsByKey: [String: Int] = [:]
        for session in sessions {
            let key = templateKey(for: session)
            countsByKey[key, default: 0] += 1
        }

        var seen = Set<String>()
        var templates: [SessionTemplate] = []

        for session in sessions {
            let key = templateKey(for: session)
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)

            let subtitle = buildSubtitle(for: session)
            templates.append(SessionTemplate(
                id: key,
                activationType: session.activationType,
                title: templateTitle(for: session),
                subtitle: subtitle,
                mode: session.mode,
                power: session.power,
                parkReference: session.parkReference,
                programsRaw: session.programsRawValue,
                count: countsByKey[key] ?? 1
            ))

            if templates.count >= limit {
                break
            }
        }
        return templates
    }

    // MARK: Private

    private static func templateKey(for session: LoggingSession) -> String {
        let type = session.activationType.rawValue
        let mode = session.mode
        let ref = session.parkReference ?? session.sotaReference ?? ""
        return "\(type)-\(mode)-\(ref)"
    }

    private static func templateTitle(
        for session: LoggingSession
    ) -> String {
        let type = session.activationType
        switch type {
        case .pota:
            if let park = session.parkReference {
                return "POTA \(park)"
            }
            return "POTA Activation"
        case .sota:
            if let summit = session.sotaReference {
                return "SOTA \(summit)"
            }
            return "SOTA Activation"
        case .wwff:
            if let ref = session.wwffReference {
                return "WWFF \(ref)"
            }
            return "WWFF Activation"
        case .tota:
            if let grid = session.myGrid, !grid.isEmpty {
                return "TOTA \(grid)"
            }
            return "TOTA Activation"
        case .aoa,
             .casual:
            return "\(type.displayName) \(session.mode)"
        }
    }

    private static func buildSubtitle(
        for session: LoggingSession
    ) -> String? {
        var parts: [String] = []
        parts.append(session.mode)
        if let power = session.power {
            parts.append("\(power)W")
        }
        if let rig = session.myRig, !rig.isEmpty {
            parts.append(rig)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }
}
