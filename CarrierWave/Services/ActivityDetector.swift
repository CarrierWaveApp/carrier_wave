import CarrierWaveCore
import CoreLocation
import Foundation
import SwiftData

// MARK: - ActivityDetector

@MainActor
final class ActivityDetector {
    // MARK: Lifecycle

    init(modelContext: ModelContext, userCallsign: String) {
        self.modelContext = modelContext
        self.userCallsign = userCallsign
    }

    // MARK: Internal

    let modelContext: ModelContext
    let userCallsign: String

    /// Distance threshold for DX contacts (5000km)
    let dxDistanceThresholdKm: Double = 5_000

    /// Streak milestones that trigger an activity
    let streakMilestones: [Int] = [7, 14, 30, 60, 90, 100, 180, 365]

    /// Minimum QSOs for a POTA activation
    let potaActivationThreshold = 10

    /// Minimum QSOs for a SOTA activation
    let sotaActivationThreshold = 4

    // MARK: Internal Static

    /// Build a dedup key for an existing ActivityItem (callable from background threads)
    nonisolated static func dedupKeyForItem(_ item: ActivityItem) -> String {
        let type = item.activityType.rawValue
        let details = item.details
        switch item.activityType {
        case .newDXCCEntity:
            return "\(type):\(details?.entityCode ?? "")"
        case .newBand:
            return "\(type):\(details?.band ?? "")"
        case .newMode:
            return "\(type):\(details?.mode ?? "")"
        case .dxContact:
            let day = dayStringFrom(item.timestamp)
            return "\(type):\(details?.workedCallsign ?? ""):\(day)"
        case .potaActivation,
             .sotaActivation:
            let day = dayStringFrom(item.timestamp)
            return "\(type):\(details?.parkReference ?? ""):\(day)"
        case .dailyStreak,
             .potaDailyStreak:
            return "\(type):\(details?.streakDays ?? 0)"
        case .personalBest:
            return "\(type):\(details?.recordType ?? "")"
        case .challengeTierUnlock,
             .challengeCompletion:
            return "\(type):\(item.challengeId?.uuidString ?? "challenge")"
        }
    }

    nonisolated static func dayStringFrom(_ date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    /// Analyze a batch of new QSOs and return detected activities
    func detectActivities(for qsos: [QSO]) -> [DetectedActivity] {
        var activities: [DetectedActivity] = []

        // Load historical data for comparison
        let historicalData = loadHistoricalData(excluding: qsos)

        for qso in qsos {
            // Check for new DXCC entity
            if let activity = detectNewDXCC(qso: qso, historical: historicalData) {
                activities.append(activity)
            }

            // Check for new band
            if let activity = detectNewBand(qso: qso, historical: historicalData) {
                activities.append(activity)
            }

            // Check for new mode
            if let activity = detectNewMode(qso: qso, historical: historicalData) {
                activities.append(activity)
            }

            // Check for DX contact (>5000km)
            if let activity = detectDXContact(qso: qso) {
                activities.append(activity)
            }
        }

        // Check for POTA activations (grouped by park)
        activities.append(contentsOf: detectPOTAActivations(qsos: qsos))

        // Check for SOTA activations
        activities.append(contentsOf: detectSOTAActivations(qsos: qsos))

        // Check for streak milestones
        if let activity = detectDailyStreakMilestone(newQSOs: qsos, historical: historicalData) {
            activities.append(activity)
        }

        if let activity = detectPOTAStreakMilestone(newQSOs: qsos, historical: historicalData) {
            activities.append(activity)
        }

        // Check for personal bests
        activities.append(contentsOf: detectPersonalBests(qsos: qsos, historical: historicalData))

        return activities
    }

    /// Create ActivityItem records from detected activities, skipping duplicates
    func createActivityItems(from detected: [DetectedActivity]) {
        // Load existing own activities for dedup
        let existingItems = loadExistingOwnActivities()

        for activity in detected {
            if isDuplicate(activity, existingItems: existingItems) {
                continue
            }

            let item = ActivityItem(
                callsign: userCallsign,
                activityType: activity.type,
                timestamp: activity.timestamp,
                isOwn: true
            )

            var details = ActivityDetails()
            populateDetails(&details, from: activity)

            item.details = details
            modelContext.insert(item)
        }

        try? modelContext.save()
    }

    // MARK: Private

    private static func dedupKeyForDetected(_ activity: DetectedActivity) -> String {
        let type = activity.type.rawValue
        switch activity.type {
        case .newDXCCEntity:
            return "\(type):\(activity.entityCode ?? "")"
        case .newBand:
            return "\(type):\(activity.band ?? "")"
        case .newMode:
            return "\(type):\(activity.mode ?? "")"
        case .dxContact:
            let day = dayStringFrom(activity.timestamp)
            return "\(type):\(activity.workedCallsign ?? ""):\(day)"
        case .potaActivation,
             .sotaActivation:
            let day = dayStringFrom(activity.timestamp)
            return "\(type):\(activity.parkReference ?? ""):\(day)"
        case .dailyStreak,
             .potaDailyStreak:
            return "\(type):\(activity.streakDays ?? 0)"
        case .personalBest:
            return "\(type):\(activity.recordType ?? "")"
        case .challengeTierUnlock,
             .challengeCompletion:
            return "\(type):challenge"
        }
    }

    private func loadExistingOwnActivities() -> [ActivityItem] {
        let callsign = userCallsign
        let descriptor = FetchDescriptor<ActivityItem>(
            predicate: #Predicate { $0.isOwn && $0.callsign == callsign },
            sortBy: [SortDescriptor(\ActivityItem.timestamp, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func isDuplicate(
        _ activity: DetectedActivity,
        existingItems: [ActivityItem]
    ) -> Bool {
        let newKey = Self.dedupKeyForDetected(activity)
        return existingItems.contains { Self.dedupKeyForItem($0) == newKey }
    }

    private func populateDetails(_ details: inout ActivityDetails, from activity: DetectedActivity) {
        switch activity.type {
        case .newDXCCEntity:
            details.entityName = activity.entityName
            details.entityCode = activity.entityCode
            details.band = activity.band
            details.mode = activity.mode
        case .newBand:
            details.band = activity.band
            details.mode = activity.mode
        case .newMode:
            details.mode = activity.mode
            details.band = activity.band
        case .dxContact:
            details.workedCallsign = activity.workedCallsign
            details.distanceKm = activity.distanceKm
            details.band = activity.band
            details.mode = activity.mode
        case .potaActivation,
             .sotaActivation:
            details.parkReference = activity.parkReference
            details.parkName = activity.parkName
            details.qsoCount = activity.qsoCount
        case .dailyStreak,
             .potaDailyStreak:
            details.streakDays = activity.streakDays
        case .personalBest:
            details.recordType = activity.recordType
            details.recordValue = activity.recordValue
        case .challengeTierUnlock,
             .challengeCompletion:
            // These are handled by challenge system, not detector
            break
        }
    }
}

// MARK: - DetectedActivity

struct DetectedActivity {
    let type: ActivityType
    let timestamp: Date

    // Type-specific fields (optional based on type)
    var entityName: String?
    var entityCode: String?
    var band: String?
    var mode: String?
    var workedCallsign: String?
    var distanceKm: Double?
    var parkReference: String?
    var parkName: String?
    var qsoCount: Int?
    var streakDays: Int?
    var recordType: String?
    var recordValue: String?
}

// MARK: - HistoricalData

struct HistoricalData {
    var knownDXCCCodes: Set<Int>
    var knownBands: Set<String>
    var knownModes: Set<String>
    var qsoDates: Set<Date> // For daily streak
    var potaDates: Set<Date> // For POTA streak
    var maxDistanceKm: Double
    var maxQSOsInDay: Int
}
