import Foundation

// MARK: - ActivityProgramStore

/// Caches activity programs locally with a bundled fallback for offline-first startup.
/// Fetches fresh data from the activities server periodically.
@MainActor
final class ActivityProgramStore: ObservableObject {
    // MARK: Lifecycle

    init(client: ActivitiesClient? = nil) {
        self.client = client
        loadFromCache()
    }

    // MARK: Internal

    /// All available programs, ordered by sort position
    @Published private(set) var programs: [ActivityProgram] = []

    /// Current registry version (for cache invalidation)
    @Published private(set) var version: Int = 0

    /// Whether a fetch is in progress
    @Published private(set) var isFetching = false

    /// Programs that have a reference field (excludes casual)
    var activationPrograms: [ActivityProgram] {
        programs.filter { $0.hasReferenceField }
    }

    /// All programs including casual, suitable for the session start picker
    var allPrograms: [ActivityProgram] {
        programs
    }

    /// Look up a program by slug
    func program(for slug: String) -> ActivityProgram? {
        programs.first { $0.slug == slug }
    }

    /// Look up a program by ActivationType (bridge for migration)
    func program(for activationType: ActivationType) -> ActivityProgram? {
        program(for: activationType.rawValue)
    }

    /// Refresh programs from the server if stale (older than 24 hours)
    func refreshIfNeeded() async {
        let lastFetch = UserDefaults.standard.double(forKey: Self.lastFetchKey)
        let elapsed = Date().timeIntervalSince1970 - lastFetch
        let staleThreshold: TimeInterval = 24 * 60 * 60 // 24 hours

        guard elapsed > staleThreshold else {
            return
        }

        await refresh()
    }

    /// Force refresh programs from the server
    func refresh() async {
        guard let client, !isFetching else {
            return
        }

        isFetching = true
        defer { isFetching = false }

        do {
            let response = try await client.fetchPrograms()
            programs = response.programs
            version = response.version
            saveToCache(response)
            UserDefaults.standard.set(
                Date().timeIntervalSince1970,
                forKey: Self.lastFetchKey
            )
        } catch {
            print("[ActivityProgramStore] Fetch failed: \(error)")
            // Keep using cached/bundled data
        }
    }

    // MARK: Private

    private static let cacheKey = "activityProgramsCache"
    private static let lastFetchKey = "activityProgramsLastFetch"

    private let client: ActivitiesClient?

    private func loadFromCache() {
        // Try UserDefaults cache first
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let response = try? JSONDecoder.activitiesDecoder.decode(
               ProgramListResponse.self,
               from: data
           )
        {
            programs = response.programs
            version = response.version
            return
        }

        // Fall back to bundled defaults
        programs = Self.bundledPrograms
    }

    private func saveToCache(_ response: ProgramListResponse) {
        if let data = try? JSONEncoder.activitiesEncoder.encode(response) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    /// Built-in program definitions for offline-first startup.
    /// These match the server seed data and are used until the first successful fetch.
    private static let bundledPrograms: [ActivityProgram] = [
        ActivityProgram(
            slug: "casual",
            name: "Casual",
            shortName: "Casual",
            icon: "radio",
            website: nil,
            referenceLabel: "Reference",
            referenceFormat: nil,
            referenceExample: nil,
            multiRefAllowed: false,
            activationThreshold: nil,
            supportsRove: false,
            capabilities: [],
            adifFields: nil
        ),
        ActivityProgram(
            slug: "pota",
            name: "Parks on the Air",
            shortName: "POTA",
            icon: "tree",
            website: "https://pota.app",
            referenceLabel: "Park Reference",
            referenceFormat: "^[A-Za-z]{1,4}-\\d{1,6}$",
            referenceExample: "K-1234",
            multiRefAllowed: true,
            activationThreshold: 10,
            supportsRove: true,
            capabilities: [
                .referenceField, .adifUpload, .browseSpots,
                .selfSpot, .hunter, .locationLookup, .progressTracking,
            ],
            adifFields: ADIFFieldMapping(
                mySig: "POTA", mySigInfo: "ref",
                sigField: nil, sigInfoField: nil
            )
        ),
        ActivityProgram(
            slug: "sota",
            name: "Summits on the Air",
            shortName: "SOTA",
            icon: "mountain.2",
            website: "https://www.sota.org.uk",
            referenceLabel: "Summit Reference",
            referenceFormat: "^[A-Z0-9]{1,4}/[A-Z]{2}-\\d{3}$",
            referenceExample: "W4C/CM-001",
            multiRefAllowed: false,
            activationThreshold: 4,
            supportsRove: false,
            capabilities: [.referenceField, .adifUpload],
            adifFields: ADIFFieldMapping(
                mySig: "SOTA", mySigInfo: "ref",
                sigField: nil, sigInfoField: nil
            )
        ),
    ]
}
