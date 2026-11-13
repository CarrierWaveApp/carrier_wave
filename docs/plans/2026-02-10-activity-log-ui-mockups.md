# Activity Log UI Mockups

**Companion to:** [Activity Log Design](2026-02-10-activity-log-design.md)
**Date:** 2026-02-10

All mockups follow [Design Language](../design-language.md). Colors reference semantic system colors.
Dark mode is the primary context (matches app screenshots).

---

## 1. Dashboard Entry Point

The activity log gets a persistent card on the Dashboard, between the activity grid and the stats cards. When no activity log exists yet, it shows a setup prompt. When active, it shows today's count with a tap-to-open action.

### 1a. First Time (No Activity Log Yet)

```
┌─────────────────────────────────────────────────┐
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  Activity Grid (existing)                 │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │  │  ← systemGray6 card
│  │                                           │  │
│  │  🔭  Activity Log                         │  │  ← scope icon, .headline
│  │                                           │  │
│  │  Track daily contacts while hunting       │  │  ← .subheadline, .secondary
│  │  spots. No session start/stop needed.     │  │
│  │                                           │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │       Set Up Activity Log           │  │  │  ← .borderedProminent, .blue
│  │  └─────────────────────────────────────┘  │  │
│  │                                           │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  Streaks Card (existing)                  │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
```

### 1b. Active Activity Log

```
┌─────────────────────────────────────────────────┐
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  Activity Grid (existing)                 │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │  │  ← systemGray6 card, tappable
│  │                                           │  │
│  │  🔭  Activity Log            ›            │  │  ← scope icon, chevron.right
│  │                                           │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐     │  │
│  │  │   12    │ │    4    │ │    3    │     │  │  ← stat boxes (systemGray5)
│  │  │  QSOs   │ │  Bands  │ │  DXCC   │     │  │
│  │  │  today  │ │  today  │ │  new    │     │  │
│  │  └─────────┘ └─────────┘ └─────────┘     │  │
│  │                                           │  │
│  │  Home QTH · IC-7300 · 100W  📍 EM85      │  │  ← .caption, .secondary
│  │                                           │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
```

**Implementation notes:**
- Stat boxes follow the existing `StatBox` pattern: `.title2.bold` value, `.caption.secondary` label
- Card taps navigate to the full Activity Log view (pushes onto nav stack)
- "12 QSOs today" uses `.green` for the number if > 0
- "3 DXCC new" uses `.blue` for the number

---

## 2. Activity Log Main View

This is the primary hunting interface. Pushed onto the navigation stack from the Dashboard card or the Logger tab. The layout is spot-list-first with callsign entry as secondary.

### 2a. Main View — Spots Loaded

```
┌─────────────────────────────────────────────────┐
│  ◀ Activity Log                          ⚙      │  ← nav bar, gear = settings
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  Today: 12 QSOs  ·  4 bands  ·  3 new    │  │  ← daily counter bar
│  │  Home QTH · IC-7300 100W        [Switch]  │  │  ← profile + switch button
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  POTA  RBN  SOTA   All ▾  CW ▾           │  │  ← filter chips (capsule badges)
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │                                           │  │
│  │   14.062    W4DOG                  2m ●   │  │  ← green dot = fresh
│  │   20m CW    🌲 K-1234 - Pisgah NF        │  │  ← tree.fill icon
│  │             Spotted by N4EX               │  │
│  │                                           │  │
│  ├───────────────────────────────────────────┤  │
│  │                                           │  │
│  │    7.030    N5RZ                   5m ●   │  │  ← blue dot = recent
│  │   40m CW    RBN · 22 dB                  │  │
│  │             ✓ 20m                         │  │  ← worked-before badge
│  │                                           │  │
│  ├───────────────────────────────────────────┤  │
│  │                                           │  │
│  │   14.061    KG5YOW                 1m ●   │  │  ← green dot = very fresh
│  │   20m CW    🌲 K-5678 - Lake Mead NRA    │  │
│  │             ★ NEW DXCC                    │  │  ← NEW DXCC highlight
│  │                                           │  │
│  ├───────────────────────────────────────────┤  │
│  │                                           │  │
│  │   21.062    VE3XYZ                 8m ●   │  │  ← blue dot
│  │   15m CW    🌲 VE-1234 - Algonquin PP    │  │
│  │             ✓ 20m 40m                     │  │  ← worked on 2 bands already
│  │                                           │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  Quick Log                                │  │  ← collapsed section header
│  │  [  Callsign...           ] [Log]         │  │  ← manual entry (secondary)
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  Recent QSOs                        See All │  │
│  │                                           │  │
│  │  14:32  W4DOG    20m CW  K-1234    599    │  │
│  │  14:28  N5RZ     40m CW            599    │  │
│  │  14:15  KE8OGR   20m CW  K-9012   599    │  │
│  │  14:02  JA7ABC   20m CW            579    │  │
│  │  13:45  VK2XYZ   15m CW            559    │  │
│  │                                           │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Implementation notes:**

Daily counter bar:
- Background: `Color(.secondarySystemGroupedBackground)`
- "12" in `.green` if > 0
- Profile line: `.caption`, `.secondary`
- `[Switch]` button: `.bordered`, `.caption`

Filter chips:
- Horizontal `ScrollView` with capsule-shaped buttons
- Selected state: `.blue.opacity(0.2)` background, `.blue` text
- Unselected: `Color(.tertiarySystemFill)` background, `.secondary` text

Spot rows (reuse `POTASpotRow` patterns):
- Frequency: `.subheadline.monospaced()`, right-aligned in 80pt column
- Band + Mode: `.caption2`, `.secondary`
- Callsign: `.subheadline.weight(.semibold).monospaced()`
- Park info: `.caption`, `.secondary`, with `tree.fill` icon in `.green`
- Time ago: `.caption`, color from `ageColor` (green/blue/orange/secondary)
- Age dot: `Circle().fill(ageColor).frame(width: 8, height: 8)`

Worked-before badge:
- `✓ 20m` = checkmark + band list
- `.caption2.weight(.medium)`, `.orange` text
- Uses capsule background: `Color.orange.opacity(0.15)`

NEW DXCC badge:
- `★ NEW DXCC` solid badge
- `.caption2.weight(.bold)`, white text on `.blue` background
- `RoundedRectangle(cornerRadius: 3)`

Quick Log section:
- `DisclosureGroup` style, collapsed by default
- Callsign field: `.title3.monospaced()`, same as current logger
- `[Log]` button: `.borderedProminent`, `.green`

Recent QSOs:
- Same row pattern as `LogsListView` QSO rows
- Limited to 5 most recent, "See All" navigates to filtered log view
- Timestamp: `.caption.monospaced()`, UTC
- Callsign: `.subheadline.weight(.semibold).monospaced()`
- Band/Mode: capsule badges

---

### 2b. Spot Tapped — Log QSO Sheet

When a spot is tapped, a bottom sheet slides up pre-filled with the spot data:

```
┌─────────────────────────────────────────────────┐
│                  ─── drag indicator ───          │
│                                                 │
│  Log QSO from Spot                              │  ← .headline
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  W4DOG                                    │  │  ← .title3.monospaced(), bold
│  │  14.062 MHz · 20m CW                      │  │  ← .subheadline.monospaced()
│  │  🌲 K-1234 - Pisgah National Forest       │  │  ← .caption, .secondary
│  └───────────────────────────────────────────┘  │
│                                                 │
│  RST Sent         RST Rcvd                      │
│  ┌──────────┐     ┌──────────┐                  │
│  │   599    │     │   599    │                  │  ← pre-filled, editable
│  └──────────┘     └──────────┘                  │
│                                                 │
│  ▸ More Fields                                  │  ← disclosure, collapsed
│    (Their Grid, State, Notes)                   │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │               Log QSO                     │  │  ← .borderedProminent, .green
│  └───────────────────────────────────────────┘  │  ← .headline, full width
│                                                 │
│  Logging as AJ7CM · Home QTH · 100W             │  ← .caption, .secondary
│                                                 │
└─────────────────────────────────────────────────┘
```

**Implementation notes:**
- `.presentationDetents([.medium])` — half-screen sheet
- `.presentationDragIndicator(.visible)`
- Pre-filled fields: callsign, frequency, mode, their park reference
- RST defaults: 599 for CW/digital, 59 for phone (existing logic)
- "More Fields" is a `DisclosureGroup` matching the current logger pattern
- "Log QSO" button: `.borderedProminent`, `.green` tint, `.headline` font
- Bottom line shows current station profile context
- On success: sheet dismisses, toast appears ("QSO logged: W4DOG 20m CW"), spot row in list gets a subtle checkmark overlay

---

### 2c. Spot Row — Worked-Before States

Each spot row can show one of several states for the worked-before indicator:

```
Not worked:
│   14.062    W4DOG                  2m ●   │
│   20m CW    🌲 K-1234 - Pisgah NF        │

Worked today on same band (dupe warning):
│   14.062    W4DOG                  2m ●   │
│   20m CW    🌲 K-1234 - Pisgah NF        │
│             ⚠ DUPE 20m CW                │  ← orange background banner
                                               .orange.opacity(0.15) bg

Worked today on different band(s):
│   14.062    W4DOG                  2m ●   │
│   20m CW    🌲 K-1234 - Pisgah NF        │
│             ✓ 40m                         │  ← orange capsule badges

Worked before (not today) on different band(s):
│   14.062    W4DOG                  2m ●   │
│   20m CW    🌲 K-1234 - Pisgah NF        │
│             ✓ 20m 40m (prev)              │  ← muted, secondary color

New DXCC entity:
│   14.062    RA3XYZ                 2m ●   │
│   20m CW    RBN · 18 dB                  │
│             ★ NEW DXCC                    │  ← solid blue badge

New DXCC + worked on other band today:
│   14.062    RA3XYZ                 2m ●   │
│   20m CW    RBN · 18 dB                  │
│             ★ NEW DXCC  ✓ 40m             │  ← blue badge + orange badge
```

**Badge specs:**

Dupe warning:
```swift
HStack(spacing: 4) {
    Image(systemName: "exclamationmark.triangle.fill")
        .font(.caption2)
    Text("DUPE 20m CW")
        .font(.caption2.weight(.semibold))
}
.foregroundStyle(.orange)
.padding(.horizontal, 6)
.padding(.vertical, 2)
.background(Color.orange.opacity(0.15))
.clipShape(Capsule())
```

Worked-before bands (today):
```swift
HStack(spacing: 2) {
    Image(systemName: "checkmark")
        .font(.caption2)
    Text("40m")
        .font(.caption2.weight(.medium))
}
.foregroundStyle(.orange)
.padding(.horizontal, 6)
.padding(.vertical, 2)
.background(Color.orange.opacity(0.15))
.clipShape(Capsule())
```

Worked-before bands (historical):
```swift
HStack(spacing: 2) {
    Image(systemName: "checkmark")
        .font(.caption2)
    Text("20m 40m")
        .font(.caption2.weight(.medium))
    Text("(prev)")
        .font(.caption2)
}
.foregroundStyle(.secondary)
```

NEW DXCC:
```swift
Text("★ NEW DXCC")
    .font(.caption2.weight(.bold))
    .foregroundStyle(.white)
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Color.blue)
    .clipShape(RoundedRectangle(cornerRadius: 3))
```

---

## 3. Station Profile Picker Sheet

Follows the same pattern as `RadioPickerSheet` — UserDefaults-backed list with inline add/delete. Profiles are stored as JSON-encoded array via `StationProfileStorage` (mirrors `RadioStorage`).

### 3a. Profile List

```
┌─────────────────────────────────────────────────┐
│  Station Profile                        Done    │  ← nav bar
├─────────────────────────────────────────────────┤
│                                                 │
│  ● Home QTH                              ✓     │  ← selected (checkmark)
│    IC-7300 · 100W · Hex beam                    │  ← .caption, .secondary
│    📍 EM85                                      │  ← .caption, .secondary
│                                                 │
│  ○ Mobile                                       │
│    IC-705 · 10W · Hamstick                      │
│    📍 (use current location)                    │  ← italicized
│                                                 │
│  ○ QRP Portable                                 │
│    KX3 · 5W · EFHW                              │
│    📍 (use current location)                    │
│                                                 │
├─────────────────────────────────────────────────┤
│                                                 │
│  ＋ Add Station Profile                         │  ← plus.circle icon
│                                                 │
└─────────────────────────────────────────────────┘
```

**Implementation notes:**
- `List` with sections, same structure as `RadioPickerSheet`
- Selected profile has `checkmark` in `.accentColor`
- Swipe to delete (`.swipeActions`)
- Tap to select and dismiss
- Each row shows: name (`.subheadline.weight(.medium)`), details (`.caption`, `.secondary`), grid (`.caption`, `.secondary`)

### 3b. Add/Edit Profile Sheet

```
┌─────────────────────────────────────────────────┐
│  Cancel     New Profile              Save       │
├─────────────────────────────────────────────────┤
│                                                 │
│  Name                                           │
│  ┌───────────────────────────────────────────┐  │
│  │  Home QTH                                 │  │  ← .textInputAutocapitalization(.words)
│  └───────────────────────────────────────────┘  │
│                                                 │
│  Radio                                          │
│  ┌───────────────────────────────────────────┐  │
│  │  IC-7300                            ›     │  │  ← taps to RadioPickerSheet
│  └───────────────────────────────────────────┘  │
│                                                 │
│  Power (Watts)                                  │
│  ┌───────────────────────────────────────────┐  │
│  │  100                                      │  │  ← .numberPad
│  └───────────────────────────────────────────┘  │
│                                                 │
│  Antenna                                        │
│  ┌───────────────────────────────────────────┐  │
│  │  Hex beam                                 │  │  ← free text
│  └───────────────────────────────────────────┘  │
│                                                 │
│  Grid Square                                    │
│  ┌───────────────────────────────────────────┐  │
│  │  EM85                                     │  │  ← .monospaced()
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ☐ Use current location instead of fixed grid   │  ← toggle
│                                                 │
│  ☐ Set as default profile                       │  ← toggle
│                                                 │
└─────────────────────────────────────────────────┘
```

**Implementation notes:**
- `Form` / `NavigationStack` with toolbar Cancel/Save
- Radio field taps into existing `RadioPickerSheet` (reuse, not duplicate)
- Grid: `.font(.subheadline.monospaced())`, `.textInputAutocapitalization(.characters)`
- "Use current location" toggle: when on, grid field is disabled and says "(auto)"
- Power validation: same as `SessionStartSheet` (1-1500W range)
- Save button disabled if name is empty

---

## 4. Location Change Prompt

Shown as a sheet when the app resumes and the user's grid square has changed since last use.

```
┌─────────────────────────────────────────────────┐
│                  ─── drag indicator ───          │
│                                                 │
│           📍                                    │  ← large location icon
│                                                 │
│       Location Changed                          │  ← .title3.weight(.semibold)
│                                                 │
│  Your grid square appears to have changed.      │  ← .subheadline, .secondary
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │                                           │  │
│  │    EM85  →  EM84                          │  │  ← .title3.monospaced()
│  │    (≈ 15 km moved)                        │  │  ← .caption, .secondary
│  │                                           │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │           Update to EM84                  │  │  ← .borderedProminent, .blue
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │            Keep EM85                      │  │  ← .bordered
│  └───────────────────────────────────────────┘  │
│                                                 │
│  Switch station profile?                        │  ← .caption, .secondary
│  ┌──────────┐ ┌──────────┐ ┌──────────┐        │
│  │ Home QTH │ │  Mobile  │ │ Portable │        │  ← capsule buttons
│  └──────────┘ └──────────┘ └──────────┘        │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Implementation notes:**
- `.presentationDetents([.medium])`
- Grid change: monospaced, with arrow
- Distance: computed from `MaidenheadConverter` (existing utility)
- Profile chips: horizontal row of capsule-shaped buttons, selected one highlighted in `.blue.opacity(0.2)`
- If only one profile exists, hide the profile switcher section

---

## 5. Filter Sheet

Accessed by tapping filter chips or a filter icon in the spots section. Half-sheet with toggleable options.

```
┌─────────────────────────────────────────────────┐
│                  ─── drag indicator ───          │
│                                                 │
│  Filter Spots                           Reset   │  ← .headline + button
│                                                 │
│  Source                                         │
│  ┌──────┐ ┌──────┐ ┌──────┐                    │
│  │ POTA │ │ RBN  │ │ SOTA │                    │  ← multi-select capsules
│  └──────┘ └──────┘ └──────┘                    │
│                                                 │
│  Band                                           │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ │
│  │ 160m │ │  80m │ │  40m │ │  30m │ │  20m │ │  ← multi-select
│  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐           │
│  │  17m │ │  15m │ │  12m │ │  10m │           │
│  └──────┘ └──────┘ └──────┘ └──────┘           │
│                                                 │
│  Mode                                           │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐           │
│  │  CW  │ │  SSB │ │  FT8 │ │ RTTY │           │
│  └──────┘ └──────┘ └──────┘ └──────┘           │
│                                                 │
│  Region                                         │
│  ┌──────┐ ┌──────┐ ┌──────┐                    │
│  │  All │ │  NA  │ │  DX  │                    │  ← single-select
│  └──────┘ └──────┘ └──────┘                    │
│                                                 │
│  ──────────────────────────────────────────     │
│  ☐  Hide already-worked callsigns               │  ← toggle
│  ☐  Show only new DXCC                          │  ← toggle
│                                                 │
└─────────────────────────────────────────────────┘
```

**Implementation notes:**
- `.presentationDetents([.medium, .large])`
- Capsule chips: selected = `Color.blue.opacity(0.2)` bg + `.blue` text, unselected = `Color(.tertiarySystemFill)` + `.secondary`
- Band/Mode/Source are multi-select (tap to toggle), Region is single-select
- "Hide already-worked" and "Show only new DXCC" are `Toggle` switches
- "Reset" clears all filters to show everything
- Reuse the existing `SpotFilters` enum patterns where possible

---

## 6. Daily Summary / Band Timeline

Accessible from "See All" or by scrolling down past the recent QSOs section. Shows the full day's activity with band hopping visualization.

```
┌─────────────────────────────────────────────────┐
│  ◀ Today's Activity                             │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  Feb 10, 2026                             │  │
│  │  12 QSOs · 4 bands · 2 modes             │  │
│  │  3 new DXCC · 2 POTA hunters              │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  Band Timeline                                  │
│  ┌───────────────────────────────────────────┐  │
│  │                                           │  │
│  │  13:00         14:00         15:00        │  │  ← time axis
│  │  ┣━━━━━━━━━━━━━━━━━━┫                     │  │
│  │  │    20m CW (6)    │                     │  │  ← blue segment
│  │                      ┣━━━━━━━━━┫          │  │
│  │                      │40m CW(3)│          │  │  ← green segment
│  │                                ┣━━━━━━━┫  │  │
│  │                                │15m SSB│  │  │  ← orange segment
│  │                                        ┣━┫│  │
│  │                                        │2││  │  ← purple (FT8)
│  │                                           │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  QSOs                                           │
│  ┌───────────────────────────────────────────┐  │
│  │  15:32  W4DOG    20m CW  K-1234    599   │  │
│  │  15:28  N5RZ     40m CW            599   │  │
│  │  15:15  KE8OGR   20m CW  K-9012   599   │  │
│  │  15:02  JA7ABC   20m CW            579   │  │
│  │  14:45  VK2XYZ   15m SSB           57    │  │
│  │  14:38  RA3DEF   15m SSB           55    │  │
│  │  14:30  DL1ABC   15m SSB           59    │  │
│  │  14:15  KG5YOW   40m CW  K-5678   599   │  │
│  │  13:55  AA4XX    40m CW            599   │  │
│  │  13:42  W1AW     40m CW            599   │  │
│  │  13:30  N0BHC    20m CW  K-9999   599   │  │
│  │  13:15  K4ABC    20m CW            599   │  │
│  │                                           │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ◀  Feb 9: 8 QSOs · 3 bands                 ▸  │  ← swipe for previous days
│                                                 │
└─────────────────────────────────────────────────┘
```

**Implementation notes:**
- Band timeline reuses the `QSOTimelineLayout` engine from POTA activations, adapted for band segments instead of gap detection
- Each band gets a color from the existing band color palette
- Segment shows band + mode + QSO count
- QSO list: full day's log, most recent first
- Bottom nav: swipe or arrow buttons to navigate to previous days
- Stats header follows the card pattern: `Color(.systemGray6)`, `RoundedRectangle(cornerRadius: 12)`

---

## 7. Settings — Activity Log Section

Added to `SettingsView` as a new section, between Logger settings and Sync Sources.

```
┌─────────────────────────────────────────────────┐
│  Activity Log                                   │  ← section header
├─────────────────────────────────────────────────┤
│                                                 │
│  Station Profiles                          ›    │  ← navigates to profile list
│  3 profiles · Home QTH active                   │
│                                                 │
│  Daily Goal                                     │
│  ┌───────────────────────────────────────────┐  │
│  │  ☐ Enable daily QSO goal                  │  │  ← toggle
│  │     Goal: [10] QSOs                       │  │  ← stepper, shown if enabled
│  └───────────────────────────────────────────┘  │
│                                                 │
│  Upload Services                                │
│  ┌───────────────────────────────────────────┐  │
│  │  ☑ QRZ Logbook                            │  │  ← toggle (default on)
│  │  ☑ Ham2K LoFi                             │  │  ← toggle (default on)
│  │  ☐ POTA        Not applicable - no park   │  │  ← disabled, explanation
│  └───────────────────────────────────────────┘  │
│                                                 │
│  Location                                       │
│  ┌───────────────────────────────────────────┐  │
│  │  ☑ Detect location changes                │  │  ← toggle
│  │  ☐ Auto-update grid square                │  │  ← toggle (prompt vs auto)
│  └───────────────────────────────────────────┘  │
│                                                 │
│  Spot Defaults                                  │
│  ┌───────────────────────────────────────────┐  │
│  │  Default source filter           All  ›   │  │
│  │  Default mode filter             All  ›   │  │
│  │  Default region                   NA  ›   │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## 8. Empty State — No Spots Available

When the spot list is empty (network error, no spots matching filters):

```
┌─────────────────────────────────────────────────┐
│                                                 │
│              📡                                 │  ← large icon, .secondary
│                                                 │
│         No spots right now                      │  ← .headline, .secondary
│                                                 │
│    Spots refresh automatically every            │  ← .subheadline, .tertiary
│    30 seconds. Try adjusting filters            │
│    or check back in a few minutes.              │
│                                                 │
│         [Refresh Now]                           │  ← .bordered button
│                                                 │
│    Tip: Use Quick Log below to enter            │  ← .caption, .tertiary
│    callsigns manually                           │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## 9. Toast Notifications

Reuse existing `LoggerToastView` patterns:

### QSO Logged from Spot
```
┌───────────────────────────────────────────────┐
│  ✓  QSO Logged                                │  ← green checkmark
│     W4DOG · 20m CW · K-1234                   │  ← .caption, .secondary
└───────────────────────────────────────────────┘
```

### Daily Goal Reached
```
┌───────────────────────────────────────────────┐
│  🎯  Daily Goal!                               │  ← blue target
│     10 QSOs today — nice work!                 │
└───────────────────────────────────────────────┘
```

### New DXCC Entity
```
┌───────────────────────────────────────────────┐
│  🌍  New DXCC Entity!                          │  ← blue globe
│     Russia (RA3XYZ) — DXCC #156               │
└───────────────────────────────────────────────┘
```

---

## View Hierarchy Summary

```
DashboardView
└── ActivityLogCard (new)              ← tappable card with daily stats
    └── ActivityLogView (new)          ← pushed onto nav stack
        ├── ActivityLogHeader          ← daily counter + profile banner
        ├── SpotFilterBar              ← horizontal filter chips
        ├── ActivityLogSpotsList       ← spot rows with worked-before
        │   └── SpotLogSheet           ← half-sheet on tap
        ├── QuickLogSection            ← collapsed manual entry
        └── RecentQSOsSection          ← last 5 QSOs
            └── DailySummaryView       ← "See All" destination
                └── BandTimelineView   ← reuses QSOTimelineLayout

StationProfilePicker (sheet)
├── ProfileRow
└── AddEditProfileSheet
    └── RadioPickerSheet (reused)

LocationChangeSheet (auto-shown on resume)

SettingsView
└── ActivityLogSettingsView (new section)
```

---

## Navigation Flow

```
Dashboard
  │
  ├── [Tap Activity Log card] ──→ ActivityLogView
  │                                   │
  │                                   ├── [Tap spot] ──→ SpotLogSheet (half-sheet)
  │                                   │                     └── [Log QSO] ──→ Toast + dismiss
  │                                   │
  │                                   ├── [Tap Switch] ──→ StationProfilePicker (sheet)
  │                                   │
  │                                   ├── [Tap filter chip] ──→ FilterSheet (half-sheet)
  │                                   │
  │                                   ├── [Tap See All] ──→ DailySummaryView (push)
  │                                   │
  │                                   └── [Tap ⚙] ──→ ActivityLogSettingsView (push)
  │
  └── [App resumes + grid changed] ──→ LocationChangeSheet (auto)

Settings
  └── [Activity Log section] ──→ ActivityLogSettingsView
      └── [Station Profiles] ──→ StationProfilePicker
```
