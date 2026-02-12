import XCTest
@testable import CarrierWave

/// Tests for BandPlanService frequency/mode/license validation
@MainActor
final class BandPlanServiceTests: XCTestCase {
    // MARK: - Technician CW Tests

    func testTechnician_40m_CW_isAllowed() {
        // 7.030 MHz CW should be allowed for Technicians (40m: 7.025-7.125 CW)
        let result = BandPlanService.validate(
            frequencyMHz: 7.030,
            mode: "CW",
            license: .technician
        )
        XCTAssertNil(result, "7.030 CW should be allowed for Technician")
    }

    func testTechnician_15m_CW_isAllowed() {
        // 21.060 MHz CW should be allowed for Technicians (15m: 21.025-21.200 CW)
        let result = BandPlanService.validate(
            frequencyMHz: 21.060,
            mode: "CW",
            license: .technician
        )
        XCTAssertNil(result, "21.060 CW should be allowed for Technician")
    }

    func testTechnician_80m_CW_isAllowed() {
        // 3.530 MHz CW should be allowed for Technicians (80m: 3.525-3.600 CW)
        let result = BandPlanService.validate(
            frequencyMHz: 3.530,
            mode: "CW",
            license: .technician
        )
        XCTAssertNil(result, "3.530 CW should be allowed for Technician")
    }

    func testTechnician_10m_CW_inPhoneSegment_isAllowed() {
        // 28.350 MHz CW should be allowed for Technicians (10m: 28.300-28.500 CW/Phone)
        let result = BandPlanService.validate(
            frequencyMHz: 28.350,
            mode: "CW",
            license: .technician
        )
        XCTAssertNil(result, "28.350 CW should be allowed for Technician")
    }

    func testTechnician_10m_SSB_isAllowed() {
        // 28.400 MHz SSB should be allowed for Technicians
        let result = BandPlanService.validate(
            frequencyMHz: 28.400,
            mode: "SSB",
            license: .technician
        )
        XCTAssertNil(result, "28.400 SSB should be allowed for Technician")
    }

    func testTechnician_10m_CW_inCWSegment_isAllowed() {
        // 28.060 MHz CW should be allowed for Technicians (10m: 28.000-28.300 CW/Data)
        let result = BandPlanService.validate(
            frequencyMHz: 28.060,
            mode: "CW",
            license: .technician
        )
        XCTAssertNil(result, "28.060 CW should be allowed for Technician")
    }

    // MARK: - Technician Restriction Tests

    func testTechnician_20m_CW_isNotAllowed() {
        // 14.060 MHz CW should NOT be allowed for Technicians (no 20m privileges)
        let result = BandPlanService.validate(
            frequencyMHz: 14.060,
            mode: "CW",
            license: .technician
        )
        XCTAssertNotNil(result, "14.060 CW should NOT be allowed for Technician")
        XCTAssertEqual(result?.type, .noPrivileges)
    }

    func testTechnician_40m_SSB_isNotAllowed() {
        // 7.200 MHz SSB should NOT be allowed for Technicians (40m Tech is CW only)
        let result = BandPlanService.validate(
            frequencyMHz: 7.200,
            mode: "SSB",
            license: .technician
        )
        XCTAssertNotNil(result, "7.200 SSB should NOT be allowed for Technician")
    }

    // MARK: - General and Extra Tests

    func testGeneral_10m_CW_inPhoneSegment_isAllowed() {
        // 28.350 MHz CW should be allowed for General
        let result = BandPlanService.validate(
            frequencyMHz: 28.350,
            mode: "CW",
            license: .general
        )
        XCTAssertNil(result, "28.350 CW should be allowed for General")
    }

    func testGeneral_20m_CW_isAllowed() {
        // 14.060 MHz CW should be allowed for General (20m: 14.025-14.150 CW/Data)
        let result = BandPlanService.validate(
            frequencyMHz: 14.060,
            mode: "CW",
            license: .general
        )
        XCTAssertNil(result, "14.060 CW should be allowed for General")
    }
}
