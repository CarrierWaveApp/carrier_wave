import Foundation
import MetricKit
import OSLog

// MARK: - PerfMetricsSubscriber

/// Receives MetricKit payloads from the OS and forwards them to PerfUploader.
final class PerfMetricsSubscriber: NSObject, MXMetricManagerSubscriber {
    // MARK: Internal

    static let shared = PerfMetricsSubscriber()

    func register() {
        MXMetricManager.shared.add(self)
        Self.logger.info("MetricKit subscriber registered")
    }

    // MXMetricManagerSubscriber — called on arbitrary thread

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        let metadata = DeviceMetadata.current()
        for payload in payloads {
            let json = payload.jsonRepresentation()
            Task {
                await PerfUploader.shared.enqueue(
                    endpoint: "v1/metrics",
                    payload: json,
                    metadata: metadata
                )
            }
        }
        Self.logger.info("Received \(payloads.count) metric payload(s)")
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let metadata = DeviceMetadata.current()
        for payload in payloads {
            let json = payload.jsonRepresentation()
            Task {
                await PerfUploader.shared.enqueue(
                    endpoint: "v1/diagnostics",
                    payload: json,
                    metadata: metadata
                )
            }
        }
        Self.logger.info("Received \(payloads.count) diagnostic payload(s)")
    }

    // MARK: Private

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "PerfMetrics"
    )
}
