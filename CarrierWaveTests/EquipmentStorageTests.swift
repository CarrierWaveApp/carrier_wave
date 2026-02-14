import XCTest
@testable import CarrierWave

/// Tests for EquipmentStorage - UserDefaults-backed equipment list management
final class EquipmentStorageTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clear all equipment types before each test
        for type in [EquipmentType.antenna, .key, .mic] {
            UserDefaults.standard.removeObject(forKey: type.rawValue)
        }
    }

    override func tearDown() {
        for type in [EquipmentType.antenna, .key, .mic] {
            UserDefaults.standard.removeObject(forKey: type.rawValue)
        }
        super.tearDown()
    }

    // MARK: - Load Tests

    func testLoad_EmptyByDefault() {
        XCTAssertEqual(EquipmentStorage.load(for: .antenna), [])
        XCTAssertEqual(EquipmentStorage.load(for: .key), [])
        XCTAssertEqual(EquipmentStorage.load(for: .mic), [])
    }

    // MARK: - Add Tests

    func testAdd_SingleItem() {
        // When
        EquipmentStorage.add("EFHW 49:1", for: .antenna)

        // Then
        XCTAssertEqual(EquipmentStorage.load(for: .antenna), ["EFHW 49:1"])
    }

    func testAdd_SortsAlphabetically() {
        // When
        EquipmentStorage.add("Linked Dipole", for: .antenna)
        EquipmentStorage.add("EFHW 49:1", for: .antenna)
        EquipmentStorage.add("Vertical", for: .antenna)

        // Then
        XCTAssertEqual(
            EquipmentStorage.load(for: .antenna),
            ["EFHW 49:1", "Linked Dipole", "Vertical"]
        )
    }

    func testAdd_PreventsDuplicates() {
        // When
        EquipmentStorage.add("EFHW 49:1", for: .antenna)
        EquipmentStorage.add("EFHW 49:1", for: .antenna)

        // Then
        XCTAssertEqual(EquipmentStorage.load(for: .antenna), ["EFHW 49:1"])
    }

    // MARK: - Remove Tests

    func testRemove_ExistingItem() {
        // Given
        EquipmentStorage.add("EFHW 49:1", for: .antenna)
        EquipmentStorage.add("Vertical", for: .antenna)

        // When
        EquipmentStorage.remove("EFHW 49:1", for: .antenna)

        // Then
        XCTAssertEqual(EquipmentStorage.load(for: .antenna), ["Vertical"])
    }

    func testRemove_NonexistentItem() {
        // Given
        EquipmentStorage.add("EFHW 49:1", for: .antenna)

        // When
        EquipmentStorage.remove("Vertical", for: .antenna)

        // Then
        XCTAssertEqual(EquipmentStorage.load(for: .antenna), ["EFHW 49:1"])
    }

    // MARK: - Equipment Type Isolation

    func testTypes_AreIsolated() {
        // When
        EquipmentStorage.add("EFHW 49:1", for: .antenna)
        EquipmentStorage.add("Begali Traveller", for: .key)
        EquipmentStorage.add("Heil Pro 7", for: .mic)

        // Then - each type has only its own item
        XCTAssertEqual(EquipmentStorage.load(for: .antenna), ["EFHW 49:1"])
        XCTAssertEqual(EquipmentStorage.load(for: .key), ["Begali Traveller"])
        XCTAssertEqual(EquipmentStorage.load(for: .mic), ["Heil Pro 7"])
    }

    // MARK: - EquipmentType Properties

    func testEquipmentType_DisplayNames() {
        XCTAssertEqual(EquipmentType.antenna.displayName, "Antenna")
        XCTAssertEqual(EquipmentType.key.displayName, "Key")
        XCTAssertEqual(EquipmentType.mic.displayName, "Microphone")
    }

    func testEquipmentType_Icons() {
        XCTAssertEqual(EquipmentType.antenna.icon, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(EquipmentType.key.icon, "pianokeys")
        XCTAssertEqual(EquipmentType.mic.icon, "mic")
    }
}
