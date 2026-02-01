# Performance Testing Improvements Plan

**Status:** Draft  
**Created:** 2026-01-31

## Current State

The project has basic performance tests in `CarrierWaveTests/PerformanceTests/QSOStatisticsPerformanceTests.swift`:

- Uses `measure {}` blocks (default 10 iterations)
- Uses manual timing with `CFAbsoluteTimeGetCurrent()` for baseline validation
- Tests QSOStatistics computation with 50k/500k synthetic QSOs
- QSOFactory generates realistic test data

### Current Limitations

1. **No XCTMetric usage** - Only using basic `measure {}` and manual timing
2. **Manual baselines** - Hardcoded TimeInterval constants instead of Xcode baselines
3. **No memory/CPU tracking** - Only wall clock time measured
4. **No UI performance tests** - Only unit-level stats computation
5. **CI baseline challenge** - Baselines are machine-specific

## Proposed Improvements

### Phase 1: Upgrade to XCTMetric

Replace manual timing with proper XCTMetric usage for richer data:

```swift
func testFullStatisticsPerformance() {
    let qsos = QSOFactory.generate(count: Self.standardTestSize)
    
    let metrics: [XCTMetric] = [
        XCTClockMetric(),
        XCTCPUMetric(),
        XCTMemoryMetric()
    ]
    
    let options = XCTMeasureOptions.default
    options.iterationCount = 5  // Reduce from 10 for faster CI
    
    measure(metrics: metrics, options: options) {
        let stats = QSOStatistics(qsos: qsos)
        _ = stats.totalQSOs
        _ = stats.activityByDate
        _ = stats.dailyStreak
    }
}
```

**Benefits:**
- CPU cycles and instructions tracked
- Memory consumption measured
- Standard deviation calculated automatically
- Results visible in Xcode test reports

### Phase 2: UI Performance Tests

Add XCUITest-based performance tests for critical views identified in `docs/PERFORMANCE.md`:

1. **Dashboard tab switching** - Measure time to display stats
2. **Logger view launch** - Measure session start to input ready
3. **Map view rendering** - Measure with various QSO counts
4. **Logs list scrolling** - Measure smooth scrolling with 10k+ QSOs

```swift
// CarrierWaveUITests/PerformanceTests/TabSwitchingPerformanceTests.swift
func testDashboardTabSwitchPerformance() {
    let app = XCUIApplication()
    app.launch()
    
    // Navigate away first
    app.tabBars.buttons["Logs"].tap()
    
    measure(metrics: [XCTOSSignpostMetric.applicationLaunch]) {
        app.tabBars.buttons["Dashboard"].tap()
        // Wait for stats to render
        _ = app.staticTexts["Total QSOs"].waitForExistence(timeout: 5)
    }
}
```

**Note:** XCTMemoryMetric returns 0 for XCUIApplication targets - use XCTClockMetric and XCTCPUMetric for UI tests.

### Phase 3: Custom Signpost Instrumentation

Add OSSignpost markers to critical code paths for fine-grained measurement:

```swift
// In QSOStatistics.swift
import os.signpost

private let perfLog = OSLog(subsystem: "com.carrierwave", category: "Performance")

var activityByDate: [Date: Int] {
    os_signpost(.begin, log: perfLog, name: "activityByDate")
    defer { os_signpost(.end, log: perfLog, name: "activityByDate") }
    
    // ... existing computation
}
```

Then measure with XCTOSSignpostMetric:

```swift
func testActivityByDateWithSignpost() {
    let metric = XCTOSSignpostMetric(
        subsystem: "com.carrierwave",
        category: "Performance",
        name: "activityByDate"
    )
    
    measure(metrics: [metric]) {
        let stats = QSOStatistics(qsos: qsos)
        _ = stats.activityByDate
    }
}
```

### Phase 4: Launch Performance Test

Add app launch time tracking (target: <400ms):

```swift
func testLaunchPerformance() {
    measure(metrics: [XCTOSSignpostMetric.applicationLaunch]) {
        XCUIApplication().launch()
    }
}
```

### Phase 5: CI Integration Strategy

Since baselines are machine-specific, use a hybrid approach:

1. **Xcode baselines** for local development (stored in xcbaselines/)
2. **Absolute time assertions** for CI (the current approach):

```swift
func testQuickStatisticsCI() {
    let qsos = QSOFactory.generate(count: Self.quickTestSize)
    
    let start = CFAbsoluteTimeGetCurrent()
    let stats = QSOStatistics(qsos: qsos)
    _ = stats.totalQSOs
    _ = stats.activityByDate
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    
    // CI runners should complete in under 3 seconds
    // This is intentionally generous to account for CI variability
    XCTAssertLessThan(elapsed, 3.0)
}
```

3. **Trend tracking** (future): Export results to JSON and track over time

## File Changes

### New Files

| File | Purpose |
|------|---------|
| `CarrierWaveUITests/PerformanceTests/TabSwitchingPerformanceTests.swift` | UI tab switching perf tests |
| `CarrierWaveUITests/PerformanceTests/ScrollingPerformanceTests.swift` | List scrolling perf tests |
| `CarrierWaveUITests/PerformanceTests/LaunchPerformanceTests.swift` | App launch time test |

### Modified Files

| File | Change |
|------|--------|
| `CarrierWaveTests/PerformanceTests/QSOStatisticsPerformanceTests.swift` | Add XCTMetric usage |
| `CarrierWave/Views/Dashboard/QSOStatistics.swift` | Add OSSignpost instrumentation (optional) |
| `Makefile` | Add `test-performance-ui` target |

## Metrics Reference

| Metric | Purpose | Notes |
|--------|---------|-------|
| `XCTClockMetric` | Wall clock time | Basic timing |
| `XCTCPUMetric` | CPU cycles, instructions, CPU time | Includes retired instructions |
| `XCTMemoryMetric` | Physical memory | Returns 0 for XCUIApplication |
| `XCTStorageMetric` | Bytes written to disk | For I/O-heavy tests |
| `XCTOSSignpostMetric` | Time in signposted regions | Best for targeted measurement |
| `XCTOSSignpostMetric.applicationLaunch` | App launch time | Target: <400ms |

## Best Practices

1. **Use predefined test data** - QSOFactory provides deterministic data
2. **Isolate measurements** - Use `startMeasuring()`/`stopMeasuring()` for setup-heavy tests
3. **Test on device** - Simulator metrics are unreliable
4. **Combine metrics** - Measure CPU, memory, and time together
5. **Run in separate scheme** - Keep performance tests out of main test suite
6. **Set realistic baselines** - Account for device variability (10% tolerance)

## Implementation Order

1. [ ] Upgrade existing tests to use XCTMetric (Phase 1)
2. [ ] Add OSSignpost instrumentation to QSOStatistics (Phase 3)
3. [ ] Create LaunchPerformanceTests (Phase 4)
4. [ ] Create TabSwitchingPerformanceTests (Phase 2)
5. [ ] Create ScrollingPerformanceTests (Phase 2)
6. [ ] Add `test-performance-ui` Makefile target (Phase 5)
7. [ ] Update docs/FILE_INDEX.md with new test files

## Resources

- [Square Engineering: measureBlock](https://developer.squareup.com/blog/measureblock-how-does-performance-testing-work-in-ios/)
- [Augmented Code: XCTMetric](https://augmentedcode.io/2019/12/22/performance-testing-using-xctmetric/)
- [ChimeHQ: XCTest Performance](https://www.chimehq.com/blog/xctest-performance)
- [Apple: Performance Tests](https://developer.apple.com/documentation/xctest/performance-tests)
