import Foundation
import OSLog

// MARK: - PerfUploader

/// Uploads MetricKit payloads to the performance monitoring server with offline queue.
actor PerfUploader {
    // MARK: Internal

    static let shared = PerfUploader()

    /// Enqueue a payload for upload. Attempts immediate send; persists to disk on failure.
    func enqueue(endpoint: String, payload: Data, metadata: DeviceMetadata) async {
        let wrapped = wrapPayload(payload: payload, metadata: metadata)
        let success = await upload(endpoint: endpoint, body: wrapped)
        if !success {
            persistToDisk(
                PendingPayload(endpoint: endpoint, payload: payload, metadata: metadata)
            )
        }
        await flushQueue()
    }

    /// Record a lightweight lifecycle event (view appear, tab switch, orientation change).
    /// Events are batched and uploaded periodically via `flushEvents()`.
    func recordEvent(_ event: PerfEvent) {
        pendingEvents.append(event)
        if pendingEvents.count >= Self.eventBatchSize {
            Task { await flushEvents() }
        }
    }

    /// Upload any buffered lifecycle events.
    func flushEvents() async {
        guard !pendingEvents.isEmpty else {
            return
        }
        let batch = pendingEvents
        pendingEvents.removeAll()

        let metadata = DeviceMetadata.current()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let payload = try? encoder.encode(batch) else {
            return
        }
        await enqueue(endpoint: "v1/events", payload: payload, metadata: metadata)
    }

    /// Drain any queued payloads and buffered events. Called on foreground and after successful enqueue.
    func flushQueue() async {
        await flushEvents()
        let pending = loadPendingPayloads()
        for item in pending {
            let wrapped = wrapPayload(payload: item.payload, metadata: item.metadata)
            let success = await upload(endpoint: item.endpoint, body: wrapped)
            if success {
                removeFile(item.fileURL)
            }
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "PerfUploader"
    )

    /// Embedded API key for anonymous telemetry — not security-critical.
    private static let apiKey = "cw-perf-v1-anon"

    private static let maxQueuedFiles = 50
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private static let eventBatchSize = 20

    private var pendingEvents: [PerfEvent] = []

    private var baseURL: String {
        let raw = UserDefaults.standard.string(forKey: "perfMonitoringBaseURL")
            ?? ActivitiesClient.resolvedBaseURL
        return ActivitiesClient.normalizeBase(raw)
    }

    private var queueDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("perf_queue", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Upload

    private func upload(endpoint: String, body: Data) async -> Bool {
        let urlString = "\(baseURL)/\(endpoint)"
        guard let url = URL(string: urlString) else {
            Self.logger.error("Invalid URL: \(urlString)")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpBody = body
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) {
                return true
            }
            Self.logger.debug("Upload returned non-2xx for \(endpoint)")
            return false
        } catch {
            Self.logger.debug("Upload failed for \(endpoint): \(error.localizedDescription)")
            return false
        }
    }

    private func wrapPayload(payload: Data, metadata: DeviceMetadata) -> Data {
        let metadataJSON = (try? JSONEncoder().encode(metadata)) ?? Data("{}".utf8)
        // Build combined JSON: { "metadata": {...}, "payload": <raw> }
        var combined = Data()
        combined.append(Data("{\"metadata\":".utf8))
        combined.append(metadataJSON)
        combined.append(Data(",\"payload\":".utf8))
        combined.append(payload)
        combined.append(Data("}".utf8))
        return combined
    }

    // MARK: - Queue Persistence

    private func persistToDisk(_ pending: PendingPayload) {
        pruneQueue()

        let fileName = "\(UUID().uuidString).json"
        let fileURL = queueDirectory.appendingPathComponent(fileName)

        do {
            let data = try JSONEncoder().encode(pending)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to persist payload: \(error.localizedDescription)")
        }
    }

    private func loadPendingPayloads() -> [PendingPayloadWithURL] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: queueDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else {
            return []
        }

        let cutoff = Date().addingTimeInterval(-Self.maxAge)

        return files.compactMap { fileURL -> PendingPayloadWithURL? in
            guard fileURL.pathExtension == "json" else {
                return nil
            }

            // Drop files older than 7 days
            if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
               let created = attrs[.creationDate] as? Date,
               created < cutoff
            {
                try? fm.removeItem(at: fileURL)
                return nil
            }

            guard let data = try? Data(contentsOf: fileURL),
                  let pending = try? JSONDecoder().decode(PendingPayload.self, from: data)
            else {
                return nil
            }

            return PendingPayloadWithURL(
                endpoint: pending.endpoint,
                payload: pending.payload,
                metadata: pending.metadata,
                fileURL: fileURL
            )
        }
    }

    private func pruneQueue() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: queueDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else {
            return
        }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        guard jsonFiles.count >= Self.maxQueuedFiles else {
            return
        }

        // Sort oldest first and remove excess
        let sorted = jsonFiles.sorted { lhs, rhs in
            let ld = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rd = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return ld < rd
        }

        let excess = sorted.count - Self.maxQueuedFiles + 1
        for fileURL in sorted.prefix(excess) {
            try? fm.removeItem(at: fileURL)
        }
    }

    private func removeFile(_ url: URL?) {
        guard let url else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - PendingPayload

/// Nonisolated so Codable witnesses can run off the main actor (inside PerfUploader actor).
nonisolated private struct PendingPayload: Codable {
    // MARK: Lifecycle

    init(endpoint: String, payload: Data, metadata: DeviceMetadata) {
        self.endpoint = endpoint
        self.payload = payload
        self.metadata = metadata
        timestamp = Date()
    }

    // MARK: Internal

    let endpoint: String
    let payload: Data
    let metadata: DeviceMetadata
    let timestamp: Date
}

// MARK: - PendingPayloadWithURL

nonisolated private struct PendingPayloadWithURL {
    let endpoint: String
    let payload: Data
    let metadata: DeviceMetadata
    let fileURL: URL
}

// MARK: - PerfEvent

/// Lightweight lifecycle event sent to the server for view/tab/orientation tracking.
/// Nonisolated so Codable witnesses can run off the main actor (inside PerfUploader actor).
nonisolated struct PerfEvent: Codable {
    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case kind
        case label
        case timestamp
        case elapsedSeconds = "elapsed_seconds"
        case memoryMB = "memory_mb"
    }

    let kind: String
    let label: String
    let timestamp: Date
    let elapsedSeconds: Double
    let memoryMB: Int?

    /// Create an event stamped with current process uptime and resident memory.
    static func now(kind: String, label: String) -> PerfEvent {
        PerfEvent(
            kind: kind,
            label: label,
            timestamp: Date(),
            elapsedSeconds: ProcessInfo.processInfo.systemUptime,
            memoryMB: currentResidentMemoryMB()
        )
    }

    // MARK: Private

    /// Read resident memory via `task_info` (same approach as StartupProfiler).
    private static func currentResidentMemoryMB() -> Int? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { pointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), pointer, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        return Int(info.resident_size / (1_024 * 1_024))
    }
}
