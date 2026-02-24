import Foundation
import SwiftData

// MARK: - SyncService Activity Detection Methods

extension SyncService {
    /// Detect and report notable activities from newly created QSOs
    func processActivities(newQSOs: [QSO]) async {
        // Get user's callsign
        let aliasService = CallsignAliasService.shared
        guard let userCallsign = aliasService.getCurrentCallsign(), !userCallsign.isEmpty else {
            return
        }

        // Initialize detector if needed
        if activityDetector == nil {
            activityDetector = ActivityDetector(
                modelContext: modelContext, userCallsign: userCallsign
            )
        }
        if activityReporter == nil {
            activityReporter = ActivityReporter()
        }

        guard let detector = activityDetector, let reporter = activityReporter else {
            return
        }

        // Detect activities
        let detected = detector.detectActivities(for: newQSOs)

        guard !detected.isEmpty else {
            return
        }

        // Create local activity items
        detector.createActivityItems(from: detected)

        // Report to server and store server IDs on local items
        await reporter.reportActivities(
            detected, sourceURL: activitySourceURL, modelContext: modelContext
        )

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .didDetectActivities,
            object: nil,
            userInfo: ["count": detected.count]
        )
    }
}
