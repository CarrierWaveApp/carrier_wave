---
title: "Widgets & Live Activity"
description: "Home screen widgets, lock screen widgets, Dynamic Island, and watchOS companion"
weight: 14
showToc: true
---

Carrier Wave provides iOS home screen widgets, lock screen widgets, a Live Activity feature, and a watchOS companion app to surface key information without opening the app. All widgets use an App Group for shared data access, enabling real-time updates.

---

## Live Activity

Live Activity displays an active logging session on the lock screen and in the Dynamic Island. It appears automatically when you start a logging session and updates in real time as you log {{< term "QSO" >}}s.

### What It Shows

- Current {{< term "QSO" >}} count for the session
- Operating frequency and {{< term "mode" >}}
- Park reference (for {{< term "POTA" >}} activations)
- Last {{< term "callsign" >}} logged
- Session duration timer

### Real-Time Updates

The Live Activity updates immediately when:

- A {{< term "QSO" >}} is logged
- Frequency or {{< term "mode" >}} changes
- Session is paused or resumed
- A milestone is reached (e.g., 10th QSO for POTA activation)

If the app is terminated and relaunched during an active session, the Live Activity reconnects automatically.

### Dynamic Island

On devices with Dynamic Island, the Live Activity provides:

- **Compact view:** Minimal session info ({{< term "QSO" >}} count and park reference)
- **Expanded view:** Full session details including frequency, {{< term "mode" >}}, last {{< term "callsign" >}}, and session duration
- **Minimal view:** QSO count only (when other Live Activities compete for space)

### Ending the Activity

The Live Activity clears automatically when:

- You end the logging session
- The session is deleted

---

## Needs Widget

The Needs widget shows spots that match your configured [Smart Spot Needs](/reference/smart-needs/) categories.

### What It Shows

- **Matching spots** for your need categories (new DXCC, WAS, POTA parks, etc.)
- **Need category badge** on each spot (e.g., "DXCC", "WAS", "POTA")
- **Callsign, frequency, and mode** for each matching spot
- **Age indicator** showing spot freshness

### Sizes

Available in **medium** and **large** widget sizes:

- **Medium** - Shows top 3-4 matching spots
- **Large** - Shows top 8-10 matching spots with additional detail

### Configuration

Long-press the widget to select which need categories to display. Only spots matching the selected categories appear.

### Tapping the Widget

Tapping opens the Smart Spot Needs view in the main app.

---

## Solar Conditions Widget

The Solar Conditions widget displays current space weather and propagation conditions. It is available in small, medium, and lock screen sizes.

### Home Screen Variants

**Small Widget:**
- Circular arc gauges for K-index, A-index, and {{< term "SFI" >}}
- Arc fill and color indicate propagation quality
- 2x2 color-coded band conditions grid (80m-40m, 30m-20m, 17m-15m, 12m-10m)

**Medium Widget:**
- All metrics from small widget
- Per-metric descriptions:
  - **K-index:** Quiet, Unsettled, Active, Storm
  - **A-index:** Quiet, Unsettled, Active, Storm
  - **{{< term "SFI" >}}:** Poor, Low, Good, Very Good, Excellent

### Lock Screen Variants

**Circular:**
- K-index value in a circular gauge

**Rectangular:**
- K-index, A-index, and band conditions summary

**Inline:**
- K-index value and single band condition

### Configuration

Long-press the widget to configure band selection. The widget fetches data directly from HamQSL and refreshes periodically.

---

## Stats & Streaks Widget

The Stats & Streaks widget displays your operating statistics and streaks. It is available in small and lock screen sizes.

### Configurable Metrics

Long-press the widget to select:

**Streak Types:**
- On-Air streak (consecutive days with {{< term "QSO" >}}s)
- Activation streak (consecutive days activating parks)
- Hunter streak (consecutive days hunting {{< term "POTA" >}})
- {{< term "CW" >}} streak
- {{< term "Phone" >}} streak
- Digital streak

**Count Metrics:**
- {{< term "QSO" >}}s per week/month/year
- Activations per week/month/year
- Hunts per week/month/year
- New {{< term "DXCC" >}} entities this year

### Data Source

The widget reads from App Group UserDefaults, which the main app updates after each {{< term "QSO" >}} and at session end.

---

## Radio Spots Widget

The Radio Spots widget shows live {{< term "POTA" >}}, {{< term "SOTA" >}}, and {{< term "RBN" >}} (Reverse Beacon Network) spots. It is available in medium and large sizes.

### What It Shows

- Live spots from {{< term "POTA" >}}, {{< term "SOTA" >}}, and {{< term "RBN" >}}
- **Activity type icon** (POTA tree, SOTA mountain, RBN beacon) on each row
- Aligned table layout with progressive detail by widget size:
  - **Small:** Activity icon, {{< term "band" >}}, and {{< term "mode" >}}
  - **Medium:** Adds park/summit reference
  - **Large:** Two-line layout with {{< term "callsign" >}}, frequency, and detail text
- Signal strength info (for {{< term "RBN" >}} spots)

### Configuration

Long-press the widget to configure:

**Source Filter:**
- All sources
- {{< term "POTA" >}} only
- {{< term "SOTA" >}} only
- {{< term "RBN" >}} only

**Band Filter:**
- Multi-select from 160m to 2m

**{{< term "Mode" >}} Filter:**
- {{< term "CW" >}}
- {{< term "SSB" >}}
- {{< term "FT8" >}}
- {{< term "FT4" >}}
- Digital (other digital modes)

### Active Filters

Active filters appear as badges in the widget header. When more spots are available than can fit, a "+N more" indicator appears at the bottom.

### Refresh Interval

The widget refreshes every 5 minutes to fetch new spots.

### Tapping the Widget

Tapping the Radio Spots widget opens the Activity Log in the main app.

---

## Active Session Widget

The Active Session widget displays the current logging session. It is available in small, medium, and lock screen sizes.

### What It Shows

- Current {{< term "QSO" >}} count
- Park reference (for {{< term "POTA" >}} activations)
- Elapsed time since session start

### Tapping the Widget

Tapping the Active Session widget navigates directly to the Logger in the main app.

---

## Hunt Widget

The Hunt widget is a single-glance dashboard for hunters: it combines current propagation conditions with a live count of how many activators are on the air right now. It is available in the small home screen size.

### What It Shows

- **Propagation rating** in the top-right (Excellent / Good / Fair / Poor / Very Poor), color-coded
- **K-index, A-index, and {{< term "SFI" >}}** circular gauges with arc fill that scales with conditions
- **Band conditions** (80/40, 30/20, 17/15, 12/10) with a green/yellow/red dot per pair derived from current daytime conditions
- **Binoculars badge** in the bottom-right with the live count of active POTA + SOTA + RBN spots from the last 30 minutes

### Refresh Interval

The widget refreshes every 15 minutes — spot freshness matters more than solar variation here.

### Tapping the Widget

Tapping the Hunt widget jumps directly to the Hunter Log ({{< term "Activity Log" >}}) so you can start logging the next chase. If you haven't set up a Hunter Log yet, the setup sheet appears instead. Works regardless of whether you have an active session running.

---

## watchOS Companion App

Carrier Wave includes a companion app for Apple Watch that provides glanceable information and quick-start capabilities.

### Solar Conditions

The watch app displays current solar conditions:

- **K-index** with color-coded indicator
- **SFI** value
- **Band conditions** summary (compact grid)

Data refreshes when you raise your wrist or when the app receives a background update.

### Live Spots

A scrollable list of current POTA and RBN spots:

- **Callsign and frequency** for each spot
- **Park reference** for POTA spots
- **Age indicator**
- **Complication** shows spot count on the watch face

### Stats & Streaks

View your current operating statistics:

- **Active streak** count and type
- **QSO count** for today/week/month
- **Last QSO** time and callsign

### Quick Start

Start a logging session directly from your Apple Watch:

1. Tap **Quick Start** on the watch
2. Select from recent session presets (mode, frequency, activation type)
3. Session starts on your iPhone with the selected parameters
4. The watch displays the Live Activity with QSO count updates

**Note:** QSO entry still happens on the iPhone. The watch provides session monitoring and quick-start convenience.

### Complications

Carrier Wave provides watch face complications:

- **Circular** - Current streak count
- **Rectangular** - K-index and SFI summary
- **Inline** - Streak count with label
- **Corner** - QSO count for today

---

## Widget Configuration

All widgets support configuration via long-press. Configuration options vary by widget type and include:

- Metric or streak selection (Stats & Streaks)
- Band selection (Solar Conditions)
- Source, band, and {{< term "mode" >}} filters (Radio Spots)
- Need categories (Needs Widget)

### App Group

Carrier Wave uses an App Group (`group.com.jsvana.FullDuplex`) to share data between the main app and widgets. This enables:

- Real-time updates without opening the app
- Background solar polling for fresh propagation data
- Immediate reflection of logged {{< term "QSO" >}}s in stats widgets

---

## Deep Links

Tapping widgets navigates to specific areas of the app:

- **Radio Spots:** Opens Activity Log
- **Needs Widget:** Opens Smart Spot Needs view
- **Active Session:** Opens Logger
- **Hunt:** Opens the Hunter Log (Activity Log)
- **Activation Suggestion:** Opens Sessions
- **Solar Conditions, Stats & Streaks:** Opens Dashboard

---

## See Also

- [Home](/reference/dashboard/) - Overview of app metrics
- [Smart Spot Needs](/reference/smart-needs/) - Need-based spot matching
- [Activity Log](/reference/activity-log/) - Daily QSO tracking and spot monitoring
- [Logger](/reference/logger/) - QSO entry and session management
