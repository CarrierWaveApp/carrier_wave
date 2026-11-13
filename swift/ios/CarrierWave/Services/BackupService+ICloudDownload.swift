import Foundation
import OSLog

// MARK: - BackupService iCloud Download

extension BackupService {
    /// Materialise an iCloud Drive backup on local storage.
    ///
    /// On a new device, iCloud Drive replicates the directory listing
    /// before any file content lands on disk. `validateBackup` and
    /// `copyICloudBackupToLocal` see only placeholders and fail with
    /// `backupFileNotFound`. This method triggers downloads via
    /// `startDownloadingUbiquitousItem` and polls
    /// `ubiquitousItemDownloadingStatusKey` until the bundle (or
    /// legacy `.sqlite` file) is fully materialised.
    ///
    /// - Parameters:
    ///   - entry: The backup to download.
    ///   - timeout: Maximum wall-clock seconds to wait.
    ///   - progress: Optional callback fired roughly twice a second
    ///     with `(filesReady, totalFiles)` so callers can show UI.
    func ensureICloudDownloaded(
        entry: BackupEntry,
        timeout: TimeInterval = 180,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws {
        guard entry.location == .icloud else {
            return
        }
        let url = urlForEntry(entry)
        let fm = FileManager.default

        // Kick off the top-level download. For bundle directories,
        // this materialises the directory so we can enumerate it.
        try? fm.startDownloadingUbiquitousItem(at: url)

        // Wait for the bundle/file entry to appear locally.
        let appearDeadline = Date().addingTimeInterval(30)
        while !fm.fileExists(atPath: url.path),
              Date() < appearDeadline
        {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        if !fm.fileExists(atPath: url.path) {
            logger.error(
                "iCloud backup top-level never appeared: \(entry.filename)"
            )
            throw BackupError.backupFileNotFound
        }

        // Collect every file we need locally.
        let targets = bundleFiles(at: url)
        for fileURL in targets {
            try? fm.startDownloadingUbiquitousItem(at: fileURL)
        }
        logger.info(
            "iCloud download requested for \(targets.count) files in \(entry.filename)"
        )

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let ready = downloadedCount(in: targets)
            progress?(ready, targets.count)
            if ready == targets.count {
                logger.info(
                    "iCloud download complete: \(entry.filename)"
                )
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        logger.error(
            "iCloud download timed out after \(Int(timeout))s: \(entry.filename)"
        )
        throw BackupError.icloudDownloadTimedOut
    }

    // MARK: Private

    /// Files inside a backup that must be present before restore.
    /// For `.cwbackup` bundles, returns `database.sqlite` plus every
    /// file under `SessionPhotos/`. For legacy flat files, returns
    /// the file itself.
    private func bundleFiles(at url: URL) -> [URL] {
        guard url.pathExtension == "cwbackup" else {
            return [url]
        }
        var files: [URL] = [
            url.appendingPathComponent("database.sqlite"),
        ]
        let fm = FileManager.default
        let photosDir = url.appendingPathComponent("SessionPhotos")
        if let photos = try? fm.contentsOfDirectory(
            at: photosDir, includingPropertiesForKeys: nil
        ) {
            files.append(contentsOf: photos)
        }
        return files
    }

    private func downloadedCount(in targets: [URL]) -> Int {
        var ready = 0
        for fileURL in targets {
            let values = try? fileURL.resourceValues(
                forKeys: [.ubiquitousItemDownloadingStatusKey]
            )
            if values?.ubiquitousItemDownloadingStatus == .current {
                ready += 1
            }
        }
        return ready
    }
}
