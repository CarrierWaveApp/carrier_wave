# CarrierWaveCore

Pure logic library for Carrier Wave that can be tested without iOS Simulator.

## Usage

### Running Tests (No Simulator Required)

```bash
make test-unit-core
```

Or directly:

```bash
cd CarrierWaveCore && swift test
```

### Adding to Xcode Project

1. In Xcode, select File → Add Package Dependencies
2. Click "Add Local..." and select the `CarrierWaveCore` directory
3. Add `CarrierWaveCore` to your target's "Frameworks, Libraries, and Embedded Content"

### After Integration

Once the package is added to the Xcode project, update these files to use it:

**Files to update with `import CarrierWaveCore`:**

- `DeduplicationService.swift` - Use `ModeEquivalence` and `DeduplicationMatcher`
- `TwoferDuplicateRepairService.swift` - Use `TwoferMatcher` and `ParkReference`
- `POTAClient.swift` - Replace `splitParkReferences`/`isMultiPark` with `ParkReference.*`
- `QuickEntryParser.swift` in app - Remove and use package version
- `ADIFParser.swift` in app - Remove and use package version
- `BandUtilities.swift` in app - Remove and use package version
- `FrequencyFormatter.swift` in app - Remove and use package version
- `MaidenheadConverter.swift` in app - Update to use `Coordinate` or bridge to `CLLocationCoordinate2D`
- `MorseCode.swift` in app - Remove and use package version

**Example: Updating DeduplicationService**

```swift
import CarrierWaveCore

// Replace inline mode equivalence with:
if ModeEquivalence.areEquivalent(qso1.mode, qso2.mode) { ... }

// Replace inline mode selection with:
winner.mode = ModeEquivalence.moreSpecific(winner.mode, loser.mode)
```

**Example: Updating POTAClient**

```swift
import CarrierWaveCore

// Replace:
// nonisolated static func splitParkReferences(_ parkRef: String) -> [String]
// nonisolated static func isMultiPark(_ parkRef: String) -> Bool

// With:
ParkReference.split(parkRef)
ParkReference.isMultiPark(parkRef)
```

## What's Included

| Module | Purpose |
|--------|---------|
| `ADIFParser` | ADIF file format parsing |
| `BandUtilities` | Band derivation from frequency |
| `FrequencyFormatter` | Frequency formatting and parsing |
| `MaidenheadConverter` | Grid square to coordinate conversion |
| `MorseCode` | Morse code tables and timing utilities |
| `QuickEntryParser` | Quick entry string parsing |
| `ModeEquivalence` | Mode family classification and equivalence |
| `ParkReference` | Park reference parsing and validation |
| `QSOSnapshot` | Lightweight QSO representation for matching |
| `DeduplicationMatcher` | Duplicate detection logic |
| `TwoferMatcher` | Two-fer duplicate detection |

## Test Coverage

106 tests covering:
- ADIF parsing (6 tests)
- Band utilities (4 tests)  
- Maidenhead conversion (6 tests)
- Quick entry parsing (30 tests)
- Mode equivalence (14 tests)
- Park reference handling (16 tests)
- Deduplication matching (18 tests)
- Two-fer matching (12 tests)
