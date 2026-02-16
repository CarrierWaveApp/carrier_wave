import UIKit
import XCTest
@testable import CarrierWave

/// Tests for SessionPhotoManager - file-based session photo storage
@MainActor
final class SessionPhotoManagerTests: XCTestCase {
    // MARK: Internal

    var testSessionID: UUID!

    override func setUp() {
        super.setUp()
        testSessionID = UUID()
    }

    override func tearDown() {
        // Clean up test photos
        try? SessionPhotoManager.deleteAllPhotos(for: testSessionID)
        testSessionID = nil
        super.tearDown()
    }

    // MARK: - Save Tests

    func testSavePhoto_CreatesFile() throws {
        // Given
        let image = createTestImage()

        // When
        let filename = try SessionPhotoManager.savePhoto(image, sessionID: testSessionID)

        // Then
        XCTAssertFalse(filename.isEmpty)
        XCTAssertTrue(filename.hasSuffix(".jpg"))
        let url = SessionPhotoManager.photoURL(filename: filename, sessionID: testSessionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - URL Tests

    func testPhotoURL_CorrectPath() {
        let url = SessionPhotoManager.photoURL(
            filename: "test.jpg", sessionID: testSessionID
        )
        XCTAssertTrue(url.path.contains("SessionPhotos"))
        XCTAssertTrue(url.path.contains(testSessionID.uuidString))
        XCTAssertTrue(url.path.hasSuffix("test.jpg"))
    }

    // MARK: - Delete Tests

    func testDeletePhoto_RemovesFile() throws {
        // Given
        let image = createTestImage()
        let filename = try SessionPhotoManager.savePhoto(image, sessionID: testSessionID)
        let url = SessionPhotoManager.photoURL(filename: filename, sessionID: testSessionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // When
        try SessionPhotoManager.deletePhoto(filename: filename, sessionID: testSessionID)

        // Then
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDeleteAllPhotos_RemovesDirectory() throws {
        // Given - save multiple photos
        let image = createTestImage()
        _ = try SessionPhotoManager.savePhoto(image, sessionID: testSessionID)
        _ = try SessionPhotoManager.savePhoto(image, sessionID: testSessionID)
        let dir = try SessionPhotoManager.photosDirectory(for: testSessionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        // When
        try SessionPhotoManager.deleteAllPhotos(for: testSessionID)

        // Then
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    // MARK: Private

    // MARK: - Helpers

    private func createTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }
}
