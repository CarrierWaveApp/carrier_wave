# Quick Entry Parser Design

**Date:** 2026-02-01  
**Status:** Draft

## Overview

Allow users to enter a complete QSO in a single string in the callsign input field. The parser detects token types by pattern and populates form fields automatically.

**Example:** `AJ7CM 579 WA P2P US-0189` fills:
- Callsign: `AJ7CM`
- RST Received: `579`
- State: `WA`
- Their Park: `US-0189` (P2P inferred)

## Design Decisions

| Decision | Choice |
|----------|--------|
| Token ordering | Hybrid: callsign first, remaining tokens in any order |
| P2P detection | Infer from park reference pattern (no explicit P2P flag needed) |
| RST handling | Single RST = received only; two consecutive RSTs = sent/received |
| Location scope | US states + Canadian provinces + common DX regions |
| Additional fields | Grid square detection, free-text notes at end |
| User feedback | Inline preview with color-coded tokens |
| Trigger | On space after valid callsign + additional tokens detected |
| Tour | Single page added to logger mini-tour |

## Token Detection Patterns

### Callsign (must be first)
- Standard amateur callsign pattern: 1-2 letter prefix + digit + 1-3 letter suffix
- With optional modifiers: `I/W6JSV/P`, `VE3/K1ABC`, `W1AW/MM`
- Regex: `^[A-Z]{1,2}[0-9][A-Z]{1,4}(/[A-Z0-9]+)*$` (simplified)

### RST (2-3 digits)
- Phone: `[1-5][1-9]` (e.g., `59`, `57`, `44`)
- CW/Digital: `[1-5][1-9][1-9]` (e.g., `599`, `579`, `339`)
- If two RST-like values appear consecutively, treat as sent/received
- Single RST applies to **received only** (sent uses session default)

### State/Region Codes
US States (50):
```
AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD 
MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC 
SD TN TX UT VT VA WA WV WI WY DC
```

Canadian Provinces (13):
```
AB BC MB NB NL NS NT NU ON PE QC SK YT
```

Common DX Regions (examples):
```
DL (Germany), EA (Spain), F (France), G (England), I (Italy), 
JA (Japan), VK (Australia), ZL (New Zealand), etc.
```

Note: Single-letter codes like `G`, `F`, `I` only match if not part of a callsign pattern.

### Park Reference
- Pattern: `[A-Z]{1,2}-[0-9]{4,5}` 
- Examples: `US-0189`, `K-1234`, `VE-0001`, `G-0001`
- Automatically implies P2P contact

### Grid Square
- 4-character: `[A-R]{2}[0-9]{2}` (e.g., `CN87`, `FN31`)
- 6-character: `[A-R]{2}[0-9]{2}[a-x]{2}` (e.g., `CN87wk`, `FN31pr`)

### Notes (free text)
- Any tokens that don't match above patterns
- Collected and joined as notes field
- Position: typically at end, but parser handles anywhere

## Parser Algorithm

```
function parseQuickEntry(input: String) -> QuickEntryResult?
    tokens = input.split(by: whitespace)
    
    if tokens.count < 2:
        return nil  // Not quick entry, just a callsign
    
    // First token must be callsign
    if not isCallsign(tokens[0]):
        return nil
    
    result = QuickEntryResult(callsign: tokens[0])
    remainingTokens = tokens[1...]
    unrecognized = []
    
    for token in remainingTokens:
        if isRST(token):
            if result.rstReceived == nil:
                result.rstReceived = token
            elif result.rstSent == nil:
                // Shift: first RST was actually sent
                result.rstSent = result.rstReceived
                result.rstReceived = token
        elif isParkReference(token):
            result.theirPark = token
        elif isGridSquare(token):
            result.theirGrid = token
        elif isStateOrRegion(token):
            result.state = token
        else:
            unrecognized.append(token)
    
    // Unrecognized tokens become notes
    if unrecognized.count > 0:
        result.notes = unrecognized.joined(by: " ")
    
    return result
```

## UI Integration

### Quick Entry Mode Detection

Quick entry mode activates when:
1. Input contains a space
2. First token is a valid callsign
3. At least one additional token is detected

### Inline Preview Display

When quick entry mode is active, show parsed tokens with color coding below the input field:

```
┌─────────────────────────────────────────────┐
│ AJ7CM 579 WA US-0189 good signal            │
└─────────────────────────────────────────────┘
  [AJ7CM]  [579]  [WA]  [US-0189]  "good signal"
  callsign  RST   state   park       notes
```

Color scheme (suggestions):
- Callsign: Green (primary, validated)
- RST: Blue
- State/Region: Orange
- Park: Green (POTA color)
- Grid: Purple
- Notes: Gray italic

### Form Population

On submit (Return key):
1. Parse the full input
2. Populate corresponding form fields
3. Clear the input field
4. Trigger callsign lookup for the parsed callsign
5. Log QSO with populated fields (same as normal flow)

### Interaction with Existing Features

- **Callsign lookup**: Triggers after parsing, uses parsed callsign
- **POTA duplicate check**: Works normally with parsed callsign
- **Commands**: Quick entry does NOT activate if first token is a command (FREQ, MODE, etc.)
- **Default RST**: If no RST parsed, uses session default (599/59)

## Data Model

```swift
struct QuickEntryResult {
    let callsign: String
    var rstSent: String?      // nil = use default
    var rstReceived: String?  // nil = use default
    var state: String?
    var theirPark: String?
    var theirGrid: String?
    var notes: String?
}
```

## File Changes

| File | Change |
|------|--------|
| `CarrierWave/Services/QuickEntryParser.swift` | New file: parser logic |
| `CarrierWave/Views/Logger/LoggerView.swift` | Integrate parser, add preview UI |
| `CarrierWave/Views/Logger/QuickEntryPreview.swift` | New file: token preview component |
| `CarrierWave/Views/Tour/MiniTourContent.swift` | Add quick entry page to logger tour |

## Tour Content

Add to `MiniTourContent.logger`:

```swift
TourPage(
    icon: "text.line.first.and.arrowtriangle.forward",
    title: "Quick Entry",
    body: """
    Type everything in one line: callsign, RST, state, park reference, and notes. \
    Example: "AJ7CM 579 WA US-0189" fills the form automatically.
    """
)
```

## Edge Cases

| Input | Parsed As |
|-------|-----------|
| `W1AW` | Normal callsign entry (no quick entry) |
| `W1AW 59` | Callsign + RST received |
| `W1AW 57 59` | Callsign + RST sent (57) + RST received (59) |
| `W1AW CA` | Callsign + state (California) |
| `W1AW CN87 CA` | Callsign + grid + state |
| `W1AW US-0189` | Callsign + park (P2P inferred) |
| `W1AW 599 nice QSO` | Callsign + RST + notes |
| `FREQ 14.060` | Command (not quick entry) |
| `W1AW FREQ 14.060` | Callsign + notes "FREQ 14.060" (FREQ not recognized as command mid-string) |

## Future Enhancements (Not in v1)

- Operator name with quotes: `"John"`
- Explicit field prefixes: `RST:579`, `ST:WA`
- SOTA reference detection: `W7W/KG-001`
- Contest exchange parsing: serial numbers, zones
