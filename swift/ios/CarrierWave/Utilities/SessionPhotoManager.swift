import CarrierWaveData
import Foundation
import UIKit

// MARK: - SessionPhotoManager

/// Manages session photo file storage in Documents/SessionPhotos/<sessionUUID>/
enum SessionPhotoManager {
    // MARK: - Errors

    enum PhotoError: LocalizedError {
        case compressionFailed

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .compressionFailed: "Failed to compress photo"
            }
        }
    }

    /// Get the photos directory for a session, creating it if needed
    static func photosDirectory(for sessionID: UUID) throws -> URL {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        let photosDir = documentsDir
            .appendingPathComponent("SessionPhotos", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: photosDir, withIntermediateDirectories: true
        )
        return photosDir
    }

    /// Save a photo for a session, returning the filename
    static func savePhoto(_ image: UIImage, sessionID: UUID) throws -> String {
        let directory = try photosDirectory(for: sessionID)
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = directory.appendingPathComponent(filename)

        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw PhotoError.compressionFailed
        }
        try data.write(to: fileURL)
        return filename
    }

    /// Get the full URL for a photo filename
    static func photoURL(filename: String, sessionID: UUID) -> URL {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        return documentsDir
            .appendingPathComponent("SessionPhotos", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
            .appendingPathComponent(filename)
    }

    /// Delete a single photo
    static func deletePhoto(filename: String, sessionID: UUID) throws {
        let url = photoURL(filename: filename, sessionID: sessionID)
        try FileManager.default.removeItem(at: url)
    }

    /// Delete all photos for a session
    static func deleteAllPhotos(for sessionID: UUID) throws {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        let sessionDir = documentsDir
            .appendingPathComponent("SessionPhotos", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)

        if FileManager.default.fileExists(atPath: sessionDir.path) {
            try FileManager.default.removeItem(at: sessionDir)
        }
    }
}
