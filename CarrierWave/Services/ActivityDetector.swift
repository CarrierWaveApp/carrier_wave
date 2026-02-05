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

    /// Create ActivityItem records from detected activities
    func createActivityItems(from detected: [DetectedActivity]) {
        for activity in detected {
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
