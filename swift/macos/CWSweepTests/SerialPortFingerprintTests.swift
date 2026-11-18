import XCTest
@testable import CWSweep

@MainActor
final class SerialPortFingerprintTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        suiteName = "SerialPortFingerprintTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Fingerprint

    func testRealSerialNumberIsUsed() {
        let port = makePort("/dev/cu.usbserial-BG011TK5", vendor: 1_027, product: 24_577, serial: "BG011TK5")
        XCTAssertEqual(port.deviceFingerprint, "1027-24577-BG011TK5")
    }

    func testAllZeroSerialFallsBackToLocation() {
        let power = makePort("/dev/cu.usbserial-124420", vendor: 6_790, product: 29_987, location: 0x124420)
        let keyer = makePort("/dev/cu.usbserial-124440", vendor: 6_790, product: 29_987, location: 0x124440)
        XCTAssertEqual(power.deviceFingerprint, "6790-29987-loc124420")
        XCTAssertNotEqual(power.deviceFingerprint, keyer.deviceFingerprint)
    }

    func testNonUSBPortUsesPath() {
        let port = SerialPortMonitor.SerialPortInfo(
            id: "/dev/cu.debug-console", path: "/dev/cu.debug-console", name: "debug-console",
            vendorId: nil, productId: nil, serialNumber: nil
        )
        XCTAssertEqual(port.deviceFingerprint, "/dev/cu.debug-console")
    }

    // MARK: - Migration

    func testBlankProfileMovesToTheRadiosPort() throws {
        let radio = makePort("/dev/cu.usbserial-BG011TK5", vendor: 1_027, product: 24_577, serial: "BG011TK5")
        try saveBlankProfile(path: radio.path)
        defaults.set("0-0-", forKey: "radio.slot.a.lastDeviceFingerprint")

        LegacyFingerprintMigration.run(ports: [radio], defaults: defaults)

        XCTAssertNil(defaults.data(forKey: "radio.savedProfile.0-0-"))
        XCTAssertNotNil(defaults.data(forKey: "radio.savedProfile.1027-24577-BG011TK5"))
        XCTAssertEqual(defaults.string(forKey: "radio.slot.a.lastDeviceFingerprint"), "1027-24577-BG011TK5")
    }

    func testBlankProfileWaitsWhileRadioIsUnplugged() throws {
        try saveBlankProfile(path: "/dev/cu.usbserial-BG011TK5")
        defaults.set("0-0-", forKey: "radio.slot.a.lastDeviceFingerprint")

        LegacyFingerprintMigration.run(ports: [], defaults: defaults)

        XCTAssertNotNil(defaults.data(forKey: "radio.savedProfile.0-0-"))
        XCTAssertEqual(defaults.string(forKey: "radio.slot.a.lastDeviceFingerprint"), "0-0-")
    }

    func testBlankWinKeyerAndNicknameAreDropped() {
        defaults.set("0-0-", forKey: "winkeyer.lastDeviceFingerprint")
        defaults.set(["0-0-": "Old", "/dev/cu.a": "Keep"], forKey: "serial.portNicknames")

        LegacyFingerprintMigration.run(ports: [], defaults: defaults)

        XCTAssertNil(defaults.string(forKey: "winkeyer.lastDeviceFingerprint"))
        XCTAssertEqual(defaults.dictionary(forKey: "serial.portNicknames") as? [String: String], ["/dev/cu.a": "Keep"])
    }

    // MARK: Private

    private var suiteName = ""
    private var defaults: UserDefaults!

    private func makePort(
        _ path: String, vendor: Int, product: Int, serial: String = "000000000", location: Int? = nil
    ) -> SerialPortMonitor.SerialPortInfo {
        SerialPortMonitor.SerialPortInfo(
            id: path, path: path, name: path,
            vendorId: vendor, productId: product, serialNumber: serial, locationId: location
        )
    }

    private func saveBlankProfile(path: String) throws {
        let profile = RadioProfile(
            name: "K3", modelId: nil, protocolType: .elecraft,
            serialPortPath: path, baudRate: 38_400, civAddress: nil
        )
        try defaults.set(JSONEncoder().encode(profile), forKey: "radio.savedProfile.0-0-")
    }
}
