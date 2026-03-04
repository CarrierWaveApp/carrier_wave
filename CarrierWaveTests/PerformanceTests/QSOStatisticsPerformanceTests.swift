import CarrierWaveCore
import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

/// Performance tests for QSO statistics computation.
/// Run before releases to detect performance regressions.
///
/// Usage:
/// - `make test-performance-quick` - Quick test (50k QSOs) for CI
/// - `make test-performance` - Full test suite (500k QSOs) for pre-release
final class QSOStatisticsPerformanceTests: XCTestCase {
    // MARK: - Test Data Sizes

    /// Standard large dataset for regression testing
    static let standardTestSize = 500_000

    /// Smaller size for quicker iteration during development and CI
    static let quickTestSize = 50_000

    // MARK: - Performance Baselines

    /// Expected max time for full stats computation on 500k QSOs
    /// Update this after establishing baseline on your hardware
    static let fullStatsBaseline: TimeInterval = 10.0

    /// Expected max time for activity grid computation on 500k QSOs
    static let activityGridBaseline: TimeInterval = 2.0

    /// Expected max time for streak calculation on 500k QSOs
    static let streakBaseline: TimeInterval = 3.0

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    // MARK: - Setup

    @MainActor
    override func setUp() async throws {
        let schema = Schema(CarrierWaveSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext
    }

    override func tearDown() {
        modelContainer = nil
        modelContext = nil
    }

    // MARK: - Performance Tests (500k QSOs)

    /// Measures full QSOStatistics computation with 500k QSOs
    @MainActor
    func testFullStatisticsPerformance() {
        // Generate test data (not measured)
        let qsos = QSOFactory.generate(count: Self.standardTestSize)

        // Keep stats alive outside measure block to avoid deallocation crash
        var stats: QSOStatistics?

        // Measure stats computation
        measure {
            stats = QSOStatistics(qsos: qsos)

            // Access all computed properties to trigger lazy evaluation
            _ = stats!.totalQSOs
            _ = stats!.confirmedQSLs
            _ = stats!.uniqueEntities
            _ = stats!.uniqueGrids
            _ = stats!.uniqueBands
            _ = stats!.uniqueParks
            _ = stats!.successfulActivations
            _ = stats!.activityByDate
            _ = stats!.dailyStreak
            _ = stats!.potaActivationStreak
        }

        // Ensure stats is used after measure to prevent optimization
        _ = stats
    }

    /// Measures activity grid computation specifically (iterates all QSOs)
    @MainActor
    func testActivityByDatePerformance() {
        let qsos = QSOFactory.generate(count: Self.standardTestSize)
        var stats: QSOStatistics?

        measure {
            stats = QSOStatistics(qsos: qsos)
            _ = stats!.activityByDate
        }

        _ = stats
    }

    /// Measures streak calculation specifically (builds date sets and scans)
    @MainActor
    func testStreakCalculationPerformance() {
        let qsos = QSOFactory.generate(count: Self.standardTestSize)
        var stats: QSOStatistics?

        measure {
            stats = QSOStatistics(qsos: qsos)
            _ = stats!.dailyStreak
            _ = stats!.potaActivationStreak
        }

        _ = stats
    }

    /// Measures category grouping (used for drill-down views)
    @MainActor
    func testCategoryGroupingPerformance() {
        let qsos = QSOFactory.generate(count: Self.standardTestSize)
        var stats: QSOStatistics?

        measure {
            stats = QSOStatistics(qsos: qsos)
            _ = stats!.items(for: .bands)
            _ = stats!.items(for: .entities)
            _ = stats!.items(for: .grids)
            _ = stats!.items(for: .parks)
        }

        _ = stats
    }

    // MARK: - Quick Tests (50k QSOs - for CI)

    /// Quick sanity test with smaller dataset (for CI)
    @MainActor
    func testQuickStatisticsPerformance() {
        let qsos = QSOFactory.generate(count: Self.quickTestSize)

        let start = CFAbsoluteTimeGetCurrent()
        let stats = QSOStatistics(qsos: qsos)
        _ = stats.totalQSOs
        _ = stats.confirmedQSLs
        _ = stats.uniqueEntities
        _ = stats.activityByDate
        _ = stats.dailyStreak
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // Quick test should complete in under 2 seconds
        XCTAssertLessThan(elapsed, 2.0, "Quick stats test took \(elapsed)s, expected < 2.0s")
    }

    // MARK: - Baseline Validation Tests

    /// Validates that full stats computation doesn't exceed baseline
    @MainActor
    func testFullStatisticsWithinBaseline() {
        let qsos = QSOFactory.generate(count: Self.standardTestSize)

        let start = CFAbsoluteTimeGetCurrent()
        let stats = QSOStatistics(qsos: qsos)
        _ = stats.totalQSOs
        _ = stats.confirmedQSLs
        _ = stats.uniqueEntities
        _ = stats.activityByDate
        _ = stats.dailyStreak
        _ = stats.potaActivationStreak
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(
            elapsed,
            Self.fullStatsBaseline,
            "Full stats computation took \(elapsed)s, baseline is \(Self.fullStatsBaseline)s"
        )
    }
}
