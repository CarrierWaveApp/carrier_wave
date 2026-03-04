import CarrierWaveData
import Foundation

// MARK: - QueryCompiler Date & Status Field Compilation

extension QueryCompiler {
    // MARK: - Date Matching

    static func compileDateMatch(field: QueryField, condition: TermCondition) -> (QSO) ->
        Bool
    {
        switch condition {
        case let .dateEquals(dateMatch):
            let (start, end) = dateMatch.resolve()
            return { $0.timestamp >= start && $0.timestamp < end }

        case let .dateAfter(dateMatch):
            let (start, _) = dateMatch.resolve()
            return { $0.timestamp >= start }

        case let .dateBefore(dateMatch):
            let (_, end) = dateMatch.resolve()
            return { $0.timestamp < end }

        case let .dateRange(startMatch, endMatch):
            let (start, _) = startMatch.resolve()
            let (_, end) = endMatch.resolve()
            return { $0.timestamp >= start && $0.timestamp < end }

        default:
            return { _ in true }
        }
    }

    // MARK: - Status Matching

    static func compileConfirmedMatch(_ condition: TermCondition) -> (QSO) -> Bool {
        switch condition {
        case let .boolean(value):
            if value {
                // Confirmed on ANY service
                { $0.qrzConfirmed || $0.lotwConfirmed }
            } else {
                // Not confirmed anywhere
                { !$0.qrzConfirmed && !$0.lotwConfirmed }
            }

        case let .service(service):
            switch service {
            case .lotw:
                { $0.lotwConfirmed }
            case .qrz:
                { $0.qrzConfirmed }
            default:
                { _ in false } // Only LoTW and QRZ have confirmation
            }

        default:
            { _ in true }
        }
    }

    static func compileSyncedMatch(_ condition: TermCondition) -> (QSO) -> Bool {
        switch condition {
        case let .boolean(value):
            if value {
                { $0.servicePresence.contains(where: \.isPresent) }
            } else {
                { !$0.servicePresence.contains(where: \.isPresent) }
            }

        case let .service(service):
            { $0.isPresent(in: service) }

        default:
            { _ in true }
        }
    }

    static func compilePendingMatch(_ condition: TermCondition) -> (QSO) -> Bool {
        switch condition {
        case let .boolean(value):
            if value {
                { $0.servicePresence.contains(where: \.needsUpload) }
            } else {
                { !$0.servicePresence.contains(where: \.needsUpload) }
            }

        case let .service(service):
            { $0.needsUpload(to: service) }

        default:
            { _ in true }
        }
    }

    static func compileSourceMatch(_ condition: TermCondition) -> (QSO) -> Bool {
        switch condition {
        case let .service(service):
            let importSource: ImportSource =
                switch service {
                case .qrz:
                    .qrz
                case .pota:
                    .pota
                case .lofi:
                    .lofi
                case .hamrs:
                    .hamrs
                case .lotw:
                    .lotw
                case .clublog:
                    .clublog
                }
            return { $0.importSource == importSource }

        case let .equals(value):
            if value.lowercased() == "manual" || value.lowercased() == "logger" {
                return { $0.importSource == .logger }
            }
            return { _ in false }

        default:
            return { _ in true }
        }
    }

    // MARK: - Bare Term (Multi-field Search)

    static func compileBareSearchTerm(condition: TermCondition) -> (QSO) -> Bool {
        // Bare terms search across callsign, park, SOTA, and notes
        switch condition {
        case let .contains(value):
            let lowered = value.lowercased()
            return { qso in
                qso.callsign.lowercased().contains(lowered)
                    || (qso.parkReference?.lowercased().contains(lowered) ?? false)
                    || (qso.sotaRef?.lowercased().contains(lowered) ?? false)
                    || (qso.notes?.lowercased().contains(lowered) ?? false)
            }

        case let .equals(value):
            let lowered = value.lowercased()
            return { qso in
                qso.callsign.lowercased() == lowered
                    || qso.parkReference?.lowercased() == lowered
                    || qso.sotaRef?.lowercased() == lowered
            }

        case let .prefix(value):
            let lowered = value.lowercased()
            return { qso in
                qso.callsign.lowercased().hasPrefix(lowered)
                    || (qso.parkReference?.lowercased().hasPrefix(lowered) ?? false)
                    || (qso.sotaRef?.lowercased().hasPrefix(lowered) ?? false)
            }

        case let .suffix(value):
            let lowered = value.lowercased()
            return { qso in
                qso.callsign.lowercased().hasSuffix(lowered)
                    || (qso.parkReference?.lowercased().hasSuffix(lowered) ?? false)
                    || (qso.sotaRef?.lowercased().hasSuffix(lowered) ?? false)
            }

        default:
            return { _ in true }
        }
    }
}
