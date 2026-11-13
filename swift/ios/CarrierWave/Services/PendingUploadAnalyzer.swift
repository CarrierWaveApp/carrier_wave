import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - PendingUploadItem

/// A single QSO × service combination with its pending reason.
struct PendingUploadItem: Identifiable {
    let id: UUID
    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let timestamp: Date
    let myCallsign: String
    let parkReference: String?
    var services: [ServiceType]
    var reason: PendingUploadReason
    var detail: String
    let qsoID: PersistentIdentifier

    /// Section grouping based on reason category
    var section: PendingUploadSection {
        if reason.isActionable {
            .needsAttention
        } else if reason.isTransient {
            .willRetry
        } else {
            .excluded
        }
    }

    /// Merge another service into this item, keeping the higher-priority reason.
    mutating func mergeService(
        _ service: ServiceType,
        reason newReason: PendingUploadReason,
        detail newDetail: String
    ) {
        if !services.contains(service) {
            services.append(service)
        }
        if newReason.sortPriority < reason.sortPriority {
            reason = newReason
            detail = newDetail
        }
    }
}

// MARK: - PendingUploadSection

enum PendingUploadSection: String, CaseIterable {
    case needsAttention
    case willRetry
    case excluded

    // MARK: Internal

    var title: String {
        switch self {
        case .needsAttention: "Needs Attention"
        case .willRetry: "Will Retry"
        case .excluded: "Excluded from Upload"
        }
    }

    var iconName: String {
        switch self {
        case .needsAttention: "exclamationmark.triangle"
        case .willRetry: "arrow.triangle.2.circlepath"
        case .excluded: "minus.circle"
        }
    }

    var sortOrder: Int {
        switch self {
        case .needsAttention: 0
        case .willRetry: 1
        case .excluded: 2
        }
    }
}

// MARK: - PendingUploadAnalyzer

/// Analyzes QSOs with pending uploads and classifies the reason for each.
/// Must be called on MainActor since it accesses model context and CallsignAliasService.
@MainActor
final class PendingUploadAnalyzer {
    // MARK: Internal

    /// Maximum items to display (performance cap)
    static let displayLimit = 200

    /// Analyze pending uploads and return classified items.
    /// - Parameters:
    ///   - context: SwiftData model context
    ///   - serviceFilter: Optional filter to a specific service
    /// - Returns: Classified pending upload items, sorted by priority
    func analyze(
        context: ModelContext,
        serviceFilter: ServiceType? = nil
    ) -> PendingUploadResult {
        let presenceRecords = fetchPendingPresence(context: context)
        let primaryCallsign = CallsignAliasService.shared.getCurrentCallsign()?.uppercased()
        let configuredServices = CarrierWaveData.ServiceConfiguration.configuredUploadServices()

        let (itemsByQSO, totalCount) = buildItemMap(
            presenceRecords: presenceRecords,
            serviceFilter: serviceFilter,
            primaryCallsign: primaryCallsign,
            configuredServices: configuredServices
        )

        let sorted = sortByPriority(Array(itemsByQSO.values))
        let capped = Array(sorted.prefix(Self.displayLimit))

        return PendingUploadResult(
            items: capped,
            totalCount: totalCount,
            truncated: sorted.count > Self.displayLimit
        )
    }

    /// Count pending uploads per service (for badge display).
    /// Only counts services that are actually configured with credentials.
    func countByService(context: ModelContext) -> [ServiceType: Int] {
        let configured = CarrierWaveData.ServiceConfiguration.configuredUploadServices()
        var counts: [ServiceType: Int] = [:]
        for service in ServiceType.allCases
            where service.supportsUpload && configured.contains(service)
        {
            let raw = service.rawValue
            let predicate = #Predicate<ServicePresence> {
                $0.needsUpload == true && $0.serviceTypeRawValue == raw
            }
            counts[service] = (try? context.boundedCount(
                ServicePresence.self,
                predicate: predicate
            )) ?? 0
        }
        return counts
    }

    // MARK: Private

    private func buildItemMap(
        presenceRecords: [ServicePresence],
        serviceFilter: ServiceType?,
        primaryCallsign: String?,
        configuredServices: Set<ServiceType>
    ) -> (items: [PersistentIdentifier: PendingUploadItem], totalCount: Int) {
        var itemsByQSO: [PersistentIdentifier: PendingUploadItem] = [:]
        var totalCount = 0

        for presence in presenceRecords {
            guard let qso = presence.qso else {
                continue
            }
            let service = presence.serviceType
            if !configuredServices.contains(service) {
                continue
            }
            if let filter = serviceFilter, service != filter {
                continue
            }

            totalCount += 1
            let qsoID = qso.persistentModelID

            let reason = classifyReason(
                qso: qso, presence: presence, primaryCallsign: primaryCallsign,
                configuredServices: configuredServices
            )
            let detail = buildDetail(
                qso: qso, presence: presence, reason: reason,
                primaryCallsign: primaryCallsign
            )

            if itemsByQSO[qsoID] != nil {
                itemsByQSO[qsoID]?.mergeService(service, reason: reason, detail: detail)
            } else {
                itemsByQSO[qsoID] = makeItem(qso: qso, service: service, reason: reason, detail: detail)
            }
        }
        return (itemsByQSO, totalCount)
    }

    private func makeItem(
        qso: QSO, service: ServiceType, reason: PendingUploadReason, detail: String
    ) -> PendingUploadItem {
        PendingUploadItem(
            id: UUID(),
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            frequency: qso.frequency,
            timestamp: qso.timestamp,
            myCallsign: qso.myCallsign,
            parkReference: qso.parkReference,
            services: [service],
            reason: reason,
            detail: detail,
            qsoID: qso.persistentModelID
        )
    }

    private func sortByPriority(_ items: [PendingUploadItem]) -> [PendingUploadItem] {
        items.sorted { lhs, rhs in
            if lhs.reason.sortPriority != rhs.reason.sortPriority {
                return lhs.reason.sortPriority < rhs.reason.sortPriority
            }
            return lhs.timestamp > rhs.timestamp
        }
    }

    private func fetchPendingPresence(context: ModelContext) -> [ServicePresence] {
        let descriptor = BoundedDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> { $0.needsUpload == true },
            limit: BoundedDescriptor<ServicePresence>.maxLimit
        )
        return (try? context.boundedFetch(descriptor)) ?? []
    }

    private func classifyReason(
        qso: QSO,
        presence: ServicePresence,
        primaryCallsign: String?,
        configuredServices: Set<ServiceType>
    ) -> PendingUploadReason {
        // Check most specific/permanent reasons first

        if qso.isHidden {
            return .hidden
        }

        if QSOMode.isMetadata(qso.mode) {
            return .metadataMode
        }

        // Check if the service is actually configured
        if !configuredServices.contains(presence.serviceType) {
            return .serviceNotConfigured
        }

        if presence.uploadRejected {
            return .invalidParkReference
        }

        if presence.isSubmitted {
            return .awaitingConfirmation
        }

        if qso.stationCallsign != nil {
            return .clubStation
        }

        if let primary = primaryCallsign {
            let myCall = qso.myCallsign.uppercased()
            if !myCall.isEmpty, myCall != primary {
                return .callsignMismatch
            }
        }

        if !qso.hasRequiredFieldsForUpload {
            return .missingFields
        }

        let service = presence.serviceType
        if service == .pota {
            if qso.parkReference?.isEmpty ?? true {
                return .missingParkReference
            }
        }

        return .notYetAttempted
    }

    private func buildDetail(
        qso: QSO,
        presence: ServicePresence,
        reason: PendingUploadReason,
        primaryCallsign: String?
    ) -> String {
        switch reason {
        case .missingFields:
            var missing: [String] = []
            if qso.band.isEmpty || qso.band.uppercased() == "UNKNOWN" {
                missing.append("band")
            }
            if qso.frequency == nil {
                missing.append("frequency")
            }
            return "Missing: \(missing.joined(separator: ", "))"

        case .missingParkReference:
            return "No park reference set"

        case .invalidParkReference:
            let park = presence.parkReference ?? qso.parkReference ?? "unknown"
            return "Rejected: \(park)"

        case .callsignMismatch:
            let primary = primaryCallsign ?? "unknown"
            return "Logged as \(qso.myCallsign), primary is \(primary)"

        case .clubStation:
            return "Station: \(qso.stationCallsign ?? "unknown")"

        case .metadataMode:
            return "Mode: \(qso.mode)"

        case .awaitingConfirmation:
            return "Submitted, waiting for POTA job result"

        case .notYetAttempted,
             .serviceNotConfigured,
             .uploadFailed,
             .hidden:
            return ""
        }
    }
}

// MARK: - PendingUploadResult

/// Result of pending upload analysis.
struct PendingUploadResult {
    let items: [PendingUploadItem]
    let totalCount: Int
    let truncated: Bool

    var isEmpty: Bool {
        items.isEmpty
    }

    var sectionedItems: [(PendingUploadSection, [PendingUploadItem])] {
        let grouped = Dictionary(grouping: items, by: \.section)
        return PendingUploadSection.allCases.compactMap { section in
            guard let sectionItems = grouped[section], !sectionItems.isEmpty else {
                return nil
            }
            return (section, sectionItems)
        }
    }

    var needsAttentionCount: Int {
        items.filter(\.reason.isActionable).count
    }

    var willRetryCount: Int {
        items.filter(\.reason.isTransient).count
    }
}
