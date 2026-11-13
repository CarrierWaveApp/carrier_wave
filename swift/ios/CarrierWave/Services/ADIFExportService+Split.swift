// ADIF Export Service - Split Export
//
// Generates multiple ADIF files by splitting QSOs along dimensions:
// UTC day boundaries, park references (n-fers), and operators (multi-op).

import CarrierWaveData
import Foundation

// MARK: - SplitExportConfig

/// Configuration for split ADIF export
struct SplitExportConfig {
    let snapshots: [QSOExportSnapshot]
    let splitByUTCDay: Bool
    let splitByPark: Bool
    let splitByOperator: Bool
    /// Fallback park when not splitting by park
    let fallbackPark: String?
    /// Fallback callsign when not splitting by operator
    let fallbackCallsign: String
    /// Park name lookup for ADIF headers
    let parkNames: [String: String]
}

// MARK: - SplitExportFile

/// A single file in a split export
struct SplitExportFile: Identifiable {
    // MARK: Internal

    let id = UUID()
    let content: String
    let filename: String
    let qsoCount: Int
    let parkReference: String?
    let callsign: String
    let utcDate: Date

    var displayDate: String {
        Self.dateFormatter.string(from: utcDate)
    }

    // MARK: Private

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()
}

// MARK: - SplitExportGroup

/// Internal grouping used during split generation
struct SplitExportGroup {
    let snapshots: [QSOExportSnapshot]
    let parkReference: String?
    let callsign: String
    let utcDate: Date
}

// MARK: - ADIFExportService + Split

extension ADIFExportService {
    /// Generate multiple ADIF files by splitting QSOs along given dimensions.
    /// Returns one file per unique combination of active split axes.
    func generateSplitADIF(
        for config: SplitExportConfig
    ) async -> [SplitExportFile] {
        let groups = groupSnapshots(config)
        var files: [SplitExportFile] = []

        for group in groups {
            let content = await generateADIF(
                for: group.snapshots,
                parkReference: group.parkReference ?? "",
                parkName: config.parkNames[group.parkReference ?? ""],
                activatorCallsign: group.callsign
            )
            let filename = buildSplitFilename(group: group)
            files.append(SplitExportFile(
                content: content,
                filename: filename,
                qsoCount: group.snapshots.count,
                parkReference: group.parkReference,
                callsign: group.callsign,
                utcDate: group.utcDate
            ))
        }

        return files.sorted { lhs, rhs in
            if lhs.utcDate != rhs.utcDate {
                return lhs.utcDate < rhs.utcDate
            }
            let lhsPark = lhs.parkReference ?? ""
            let rhsPark = rhs.parkReference ?? ""
            if lhsPark != rhsPark {
                return lhsPark < rhsPark
            }
            return lhs.callsign < rhs.callsign
        }
    }

    /// Preview how many files a split config would produce.
    func splitFileCount(for config: SplitExportConfig) -> Int {
        groupSnapshots(config).count
    }
}

// MARK: - Private Helpers

nonisolated private func groupSnapshots(
    _ config: SplitExportConfig
) -> [SplitExportGroup] {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.timeZone = TimeZone(identifier: "UTC")

    let fallbackDateStr: String = dateFormatter.string(
        from: config.snapshots.first?.timestamp ?? Date()
    )

    struct GroupKey: Hashable {
        let park: String?
        let utcDateStr: String
        let callsign: String
    }

    var grouped: [GroupKey: [QSOExportSnapshot]] = [:]
    for snapshot in config.snapshots {
        let parks: [String?] = parksForSplit(snapshot: snapshot, config: config)
        let dateStr = config.splitByUTCDay
            ? dateFormatter.string(from: snapshot.timestamp)
            : fallbackDateStr
        let callsign = config.splitByOperator
            ? snapshot.myCallsign.uppercased()
            : config.fallbackCallsign.uppercased()

        for park in parks {
            let key = GroupKey(
                park: park, utcDateStr: dateStr, callsign: callsign
            )
            grouped[key, default: []].append(snapshot)
        }
    }

    return grouped.map { key, snapshots in
        let date = dateFormatter.date(from: key.utcDateStr) ?? Date()
        return SplitExportGroup(
            snapshots: snapshots.sorted { $0.timestamp < $1.timestamp },
            parkReference: key.park,
            callsign: key.callsign,
            utcDate: date
        )
    }
}

/// When `splitByPark` is on, an N-fer QSO with `"US-1, US-2"` fans out into
/// one entry per park so each park gets its own ADIF file. When off, the
/// fallback park applies (single entry).
nonisolated func parksForSplit(
    snapshot: QSOExportSnapshot,
    config: SplitExportConfig
) -> [String?] {
    guard config.splitByPark else {
        return [config.fallbackPark]
    }
    guard let raw = snapshot.parkReference, !raw.isEmpty else {
        return [nil]
    }
    let parks = ParkReference.split(raw)
    return parks.isEmpty ? [nil] : parks.map { Optional($0) }
}

nonisolated private func buildSplitFilename(
    group: SplitExportGroup
) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.timeZone = TimeZone(identifier: "UTC")
    let dateStr = dateFormatter.string(from: group.utcDate)

    let safeCallsign = group.callsign
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: " ", with: "_")

    if let park = group.parkReference, !park.isEmpty {
        let safePark = park
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        return "\(safeCallsign)_\(safePark)_\(dateStr).adi"
    }
    return "\(safeCallsign)_\(dateStr).adi"
}
