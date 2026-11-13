#if os(macOS)
    import Foundation

    // MARK: - MacGroupContainerMigration

    /// One-time move of CW Sweep's data out of the iOS-style App Group container
    /// (`group.com.jsvana.FullDuplex`) into the team-prefixed one
    /// (`7UE4RDLUSX.com.jsvana.FullDuplex`).
    ///
    /// Why: macOS 15+ only trusts a `group.` container claim when a provisioning
    /// profile carries the App Groups entitlement. CW Sweep's Xcode-managed
    /// profiles don't, so every launch raised the "would like to access data
    /// from other apps" prompt and the grant never stuck. A `<TeamID>.` group is
    /// verified from the code signature instead and never prompts.
    ///
    /// What moves: everything the app keeps in the container — `cw-store.*` at
    /// the root and the children of each `Library/<folder>/` (SwiftData's
    /// `CWSweep.store` + sidecars and CloudKit assets live in
    /// `Library/Application Support`). The system's own
    /// `.com.apple.containermanagerd.metadata.plist` and `Application Scripts`
    /// stay behind.
    ///
    /// Safety: targets are checked for conflicts before anything moves, so a
    /// conflict moves nothing. A failure mid-way leaves already-moved files in
    /// the new container (they no longer exist in the old one, so a retry
    /// resumes). The marker is set only after a complete pass, and reading the
    /// old container is the one remaining action that can prompt — once.
    ///
    /// Must run before the first `ModelContainer` or cw-store open.
    public enum MacGroupContainerMigration {
        // MARK: Public

        public enum Outcome: Equatable, Sendable {
            /// Marker already set; the old container was not touched.
            case alreadyDone
            /// Old container absent (fresh install, or already emptied).
            case nothingToDo
            /// Moved these relative paths.
            case migrated([String])
            /// Could not resolve the new container; nothing was touched.
            case containerUnavailable
            /// See `description`; the marker is not set so the next launch retries.
            case failed(String)
        }

        public enum MigrationError: Error, Equatable {
            /// A file exists at both locations; refusing to overwrite either.
            case conflict(String)
            /// Some files moved and others didn't; the next launch moves the rest.
            case incomplete(String)
        }

        public static let markerKey = "macGroupContainerMigrated.v1"
        public static let lastOutcomeKey = "macGroupContainerMigration.lastOutcome"

        /// Run the move if it hasn't completed yet. Records the outcome under
        /// `lastOutcomeKey` so it can be read back with `defaults read`.
        @discardableResult
        public static func runIfNeeded(
            defaults: UserDefaults = .standard,
            fileManager: FileManager = .default
        ) -> Outcome {
            guard !defaults.bool(forKey: markerKey) else {
                return .alreadyDone
            }
            guard let destination = fileManager
                .containerURL(forSecurityApplicationGroupIdentifier: CwStoreLocation.defaultAppGroupID)
            else {
                return record(.containerUnavailable, defaults: defaults)
            }
            let legacy = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers", isDirectory: true)
                .appendingPathComponent(CwStoreLocation.legacyMacAppGroupID, isDirectory: true)
            do {
                let moved = try migrate(from: legacy, to: destination, fileManager: fileManager)
                defaults.set(true, forKey: markerKey)
                return record(moved.isEmpty ? .nothingToDo : .migrated(moved), defaults: defaults)
            } catch {
                return record(.failed(String(describing: error)), defaults: defaults)
            }
        }

        // MARK: Internal

        static let skippedRootNames: Set<String> = [".com.apple.containermanagerd.metadata.plist", "Library"]
        static let skippedLibraryFolders: Set<String> = ["Application Scripts"]

        /// Move the container's contents from `legacy` into `destination` and
        /// return the relative paths moved (empty when `legacy` doesn't exist or
        /// holds nothing of ours).
        static func migrate(
            from legacy: URL,
            to destination: URL,
            fileManager: FileManager = .default
        ) throws -> [String] {
            guard fileManager.fileExists(atPath: legacy.path) else {
                return []
            }
            let plan = try plannedMoves(in: legacy, fileManager: fileManager)
            guard !plan.isEmpty else {
                return []
            }
            for relative in plan
                where fileManager.fileExists(atPath: destination.appendingPathComponent(relative).path)
            {
                throw MigrationError.conflict(relative)
            }
            var moved: [String] = []
            for relative in plan {
                let target = destination.appendingPathComponent(relative)
                do {
                    try fileManager.createDirectory(
                        at: target.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    try fileManager.moveItem(at: legacy.appendingPathComponent(relative), to: target)
                    moved.append(relative)
                } catch {
                    guard moved.isEmpty else {
                        throw MigrationError.incomplete("\(relative): \(error)")
                    }
                    throw error
                }
            }
            return moved
        }

        // MARK: Private

        /// Root entries (minus the system plist and `Library`) plus the children
        /// of each `Library/<folder>/`, as paths relative to the container.
        private static func plannedMoves(in legacy: URL, fileManager: FileManager) throws -> [String] {
            var plan = try fileManager.contentsOfDirectory(atPath: legacy.path)
                .filter { !skippedRootNames.contains($0) }
                .sorted()
            let library = legacy.appendingPathComponent("Library", isDirectory: true)
            guard fileManager.fileExists(atPath: library.path) else {
                return plan
            }
            for folder in try fileManager.contentsOfDirectory(atPath: library.path).sorted()
                where !skippedLibraryFolders.contains(folder)
            {
                let folderURL = library.appendingPathComponent(folder, isDirectory: true)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue
                else {
                    continue
                }
                for child in try fileManager.contentsOfDirectory(atPath: folderURL.path).sorted() {
                    plan.append("Library/\(folder)/\(child)")
                }
            }
            return plan
        }

        private static func record(_ outcome: Outcome, defaults: UserDefaults) -> Outcome {
            defaults.set("\(Date.now.ISO8601Format()) \(outcome)", forKey: lastOutcomeKey)
            return outcome
        }
    }
#endif
