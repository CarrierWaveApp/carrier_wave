---
title: "Activity Log"
description: "Daily QSO tracking for hunters without session management"
weight: 11
showToc: true
---

The Activity Log provides an always-on daily {{< term "QSO" >}} tracking workflow designed for hunters who make contacts throughout the day without the overhead of starting and stopping logging sessions.

## Overview

Unlike the session-based Logger, the Activity Log operates continuously. You set up your station once, then log {{< term "QSO" >}}s as you make them. Perfect for:

- **Hunting activators** throughout the day
- **Casual operating** without session structure
- **Daily goal tracking** (e.g., "50 QSOs today")
- **Drop-in contacts** while monitoring the bands

No need to start a session, manage metadata, or stop logging. Just make contacts and log them.

## Getting Started

### First Use Setup

The first time you access Activity Log, a setup sheet guides you through:

1. **Your name** - Operator name for the log
2. **Your callsign** - Station callsign
3. **Station profile** - Select or create your first equipment profile

### Dashboard Card

The Activity Log dashboard card displays:

- **Setup prompt** if not yet configured
- **Today's statistics** once set up (QSO count, bands worked, goal progress)

Tap the card to open the Activity Log view.

## Station Profiles

Station profiles are reusable equipment configurations that apply to all {{< term "QSO" >}}s logged while that profile is active.

### Profile Components

Each profile stores:

- **Radio** - Transceiver model
- **Antenna** - Antenna type and configuration
- **Key** - CW key or paddle (optional)
- **Mic** - Microphone model (optional)
- **Power** - Output power in watts
- **Grid square** - Station location (Maidenhead locator)

### Creating Profiles

Tap **Station Profiles** in Activity Log settings to add or edit profiles.

**Use Current Location:** Tap this button to auto-populate the grid square from {{< term "GPS" >}} coordinates. Requires location permissions.

### Selecting a Profile

Before logging {{< term "QSO" >}}s, pick a station profile. This sets the equipment configuration for the day. When you change profiles, all subsequent {{< term "QSO" >}}s use the new profile's settings.

Profiles are stored in UserDefaults and persist across app launches.

### Station Profile Management

Station profiles can be managed from both the Activity Log settings and Settings -> Activity Log -> Station Profiles. Improvements include:

- **Duplicate profile** - Copy an existing profile and modify it for a new setup
- **Default profile** - Designate one profile as the default for new days
- **Profile switching** - Quick-switch between profiles from the Activity Log header

## Quick Entry

The Activity Log's quick entry field supports intelligent parsing of contact details.

### Entry Format

Type a single line containing callsign and optional details:

```
W1AW 579 WA US-0189
```

The parser extracts:
- **Callsign:** W1AW
- **{{< term "RST" >}}:** 579 (sent and received)
- **State:** WA
- **Park:** US-0189

### Multiple Parks (n-fers)

When an activator is operating from a location inside two or more parks at once (a
"two-fer", "three-fer", or generally an *n-fer*), list every park reference,
separated by spaces:

```
KB8BNW US-1234 US-0579
```

Both parks are recorded on the single {{< term "QSO" >}}, and each one counts and
de-duplicates independently:

- Logging the n-fer crosses out **every** matching park's spot in the list.
- Working just one park of an n-fer leaves the others still showing as needed, so
  you can chase the remaining park later on the same band and mode.

Each park is also credited separately toward your hunter awards.

### Callsign & Park Enrichment

As soon as the parser recognizes a callsign, the quick entry looks up the operator
(name, location, and how many times you've worked them before) and shows it in a
card beneath the field. Each park reference you type is resolved to its park name
and listed below the token pills — including every park of an n-fer.

### Token Preview

As you type, the field displays color-coded token pills showing what the parser detected:

- **Blue** - Callsign
- **Green** - {{< term "RST" >}}
- **Purple** - State/Province
- **Orange** - Park reference
- **Yellow** - Frequency

This visual feedback confirms the parser understood your input correctly.

### RST Handling

**Single {{< term "RST" >}}:** Applies to both sent and received reports.

```
K1ABC 599
```
Results in: Sent 599, Received 599.

**Two RST values:** The first becomes sent, the second received.

```
K1ABC 579 599
```
Results in: Sent 579, Received 599.

### Frequency Entry

Include frequency in MHz to auto-populate band:

```
W1AW 14.060
```

The parser shows:
- **Frequency:** 14.060 MHz
- **Band:** 20m (pill badge)

### Number Row Keyboard

The quick entry field displays a custom keyboard accessory row with number keys (0-9) for rapid {{< term "RST" >}} and frequency entry.

### Band & Mode Indicator

Below the quick entry field, a status line shows:

> Next QSO will be logged as: **20m CW**

This confirms the band and mode that will apply to the {{< term "QSO" >}} when saved. Change band/mode using the picker controls above the entry field.

## Spot List

The Activity Log includes a hunter-focused spot list showing active stations to work.

### Refreshing

The spot list polls automatically every 2 minutes. To refresh on demand, **pull the list down** — this triggers one immediate poll instead of waiting out the timer. A **last refreshed** pill next to the list header shows how long ago spots were last fetched ("2 min ago"), ticking live between refreshes.

New spots appear as soon as each poll's fetches complete (about a second); callsign enrichment details (distance, bearing, operator info) fill in shortly after.

### Spot Sources

Spots come from:

- **{{< term "POTA" >}}** - Parks on the Air activators
- **{{< term "RBN" >}}** - Reverse Beacon Network

### Worked-Before Badges

Each spot displays badges indicating your contact history:

- **DUPE** - Already worked this callsign on this band today
- **TODAY** - Worked this callsign on a different band today
- **PREV** - Worked this callsign on a previous day

This helps you prioritize new contacts and avoid accidental duplicates.

### Spot Deduplication

The spot list combines {{< term "POTA" >}} and {{< term "RBN" >}} spots intelligently:

- Spots with the **same callsign + band** are merged into a single entry
- **{{< term "POTA" >}} source preferred** when available (shows park reference)
- {{< term "RBN" >}} data supplements {{< term "POTA" >}} spots with signal strength

### Tapping a Spot

Tap any spot to open a half-sheet {{< term "QSO" >}} entry form pre-filled with:

- **Callsign** from the spot
- **Frequency** from the spot
- **Mode** from the spot
- **Park reference** (if {{< term "POTA" >}} spot)

Make the contact, then save the {{< term "QSO" >}}.

### Respotting an Activator

Long-press a {{< term "POTA" >}} spot and choose **Spot** to post a fresh spot to POTA, keeping an activator you can still hear from aging out of the public feed.

A **Spot on POTA?** confirmation always appears first, previewing exactly what will be published: the activator's callsign, park reference, frequency, mode, and your callsign as the spotter. If you respotted recently, the same dialog warns about the 5-minute anti-spam cooldown.

Respotting does **not** require a POTA sign-in — it posts like pota.app's own spot form. (Self-spotting your own activation still uses your POTA account.)

## Spot Filtering

Customize which spots appear using the filter controls.

### Source Filter

- **{{< term "POTA" >}}** - Show only Parks on the Air activators
- **{{< term "RBN" >}}** - Show only Reverse Beacon Network spots
- **All** - Show both sources (with deduplication)

### Band Filter

Select one or more amateur bands:

- 160m, 80m, 60m, 40m, 30m, 20m, 17m, 15m, 12m, 10m, 6m, 2m

### Mode Filter

- **CW** - Morse code
- **SSB** - Voice (single sideband)
- **FT8** - Digital weak-signal
- **FT4** - Fast digital
- **All** - Any mode

### Age Filter

Show spots heard within the last N minutes. Configurable range: **5-30 minutes** (default: 12 minutes or less).

Older spots are often no longer active.

### Proximity Filter

**Heard Nearby** mode filters spots to stations within a configurable radius of your location.

- **Radius range:** 100-2000 miles
- **Default:** Disabled (show all spots)

When enabled, only spots within the radius appear. Useful for regional hunting or skip analysis.

### Sort Order

- **Recent** - Newest spots first (default)
- **Frequency** - Ascending frequency order

### New Since You Looked

When the spot list is sorted by **Recent**, a **+N new since you looked** divider appears above the first spot you already saw on a previous visit. The boundary is captured when you open the list and stays fixed for the current viewing session, so incoming spots from the 2-minute poll cycle don't cause the divider to shift while you're scanning. The divider is hidden on your first visit, when every spot in the list is new, or when you switch to a non-temporal sort.

### Hide Already Worked

Toggle **Hide Already Worked** to filter out spots with DUPE, TODAY, or PREV badges.

### Spot Age Color Coding

Spot rows use color to indicate freshness:

- **Green** - Less than 2 minutes old
- **Blue** - 2-10 minutes old
- **Orange** - 10-30 minutes old
- **Gray** - More than 30 minutes old

### SELF Badge

If your own callsign appears in the spot list (e.g., from {{< term "RBN" >}} receivers hearing your CQ), it displays a **SELF** badge.

### Default Filter Settings

On first use, spot filtering defaults to:

- **Source:** {{< term "POTA" >}}
- **Band:** 20m
- **Mode:** CW
- **Age:** 12 minutes or less
- **Proximity:** Heard Nearby (enabled)
- **Sort:** Recent
- **Hide Already Worked:** Enabled

Adjust these to match your hunting preferences.

## Band Timeline

The Activity Log displays a horizontal band timeline visualization showing your activity throughout the day.

### Timeline Display

Each band (20m, 40m, etc.) gets a row. Colored segments indicate periods when you logged {{< term "QSO" >}}s on that band.

**Segment length** corresponds to the time span of contacts. Gaps indicate times when you weren't active on that band.

### Color Coding

Each band uses a distinct color for quick visual reference.

### Band Timeline Visualization

The band timeline is also available in a standalone view with enhanced features:

- **Zoomable** - Pinch to zoom into specific time ranges
- **Tap segments** to see QSO details for that time block
- **Band legend** with toggle controls to show/hide specific bands

### Use Cases

- **Review your operating patterns** (e.g., "I operated 20m from 1400-1800Z")
- **Identify band conditions** (short bursts vs sustained activity)
- **Plan future operations** based on successful time blocks

## Daily Summary

Tap **View Full Day** to see a complete summary of the current day's activity.

### Summary Components

The daily summary includes:

- **Band timeline** - Visual activity breakdown
- **QSO list** - All contacts made today, sorted by time
- **Statistics** - Total QSOs, bands worked, countries worked

### QSO List

Each {{< term "QSO" >}} row shows:

- **Callsign**
- **Band + Mode** (e.g., "20m CW")
- **Time** (UTC)
- **Park reference** (if applicable)
- **State/Province** (if logged)

### Date Navigation

Use the date picker to browse previous days' activity. The timeline and {{< term "QSO" >}} list update to reflect the selected date.

Historical data persists as long as the {{< term "QSO" >}}s remain in your local database.

## Daily Goal

Set a daily {{< term "QSO" >}} goal to track your progress.

### Configuring the Goal

In Activity Log settings, set **Daily QSO Goal** to your target number (e.g., 50).

### Progress Tracking

The Activity Log header displays:

> **37 / 50 QSOs today**

A progress bar fills as you approach the goal.

### Goal Reached Notification

When you log the {{< term "QSO" >}} that meets your goal, the app displays a congratulatory alert notification.

The notification appears once per day. Logging additional {{< term "QSO" >}}s beyond the goal does not trigger more alerts.

## Location Change Detection

The Activity Log monitors your {{< term "GPS" >}} location and detects when your grid square changes.

### Change Prompt

When the app detects a grid square change, a prompt sheet appears:

> **Location changed**
> FN42 -> FN31 (47 miles)

Options:

- **Switch Profile** - Select a different station profile (e.g., mobile vs home)
- **Update Current Profile** - Update the existing profile's grid square
- **Ignore** - Continue using the current grid square

This ensures your {{< term "QSO" >}}s log with the correct location.

### Use Cases

- **Mobile operation** - Automatically updates grid as you move
- **Portable setups** - Switch profiles when arriving at a new site
- **Rove events** - Track grid changes during multi-location operations

## Daily Share Card

Share your day's activity on social media or with friends.

### Creating a Share Card

From the daily summary, tap the **Share** button.

### Card Content

The generated share card includes:

- **Carrier Wave branding**
- **Your callsign**
- **Date**
- **Total QSOs**
- **Bands worked**
- **Countries worked** (if applicable)
- **Band timeline visualization**

### Sharing

The card appears as an image in the iOS share sheet. Share via:

- Messages
- Email
- Twitter/X
- Mastodon
- Save to Photos

## Upload Services

Activity Log {{< term "QSO" >}}s sync to upload services differently than session-based logs.

### Supported Services

- **QRZ.com** - Uploads to your QRZ logbook
- **Ham2K LoFi** - Uploads to LoFi database

### POTA Upload Exclusion

**Activity Log {{< term "QSO" >}}s never upload to {{< term "POTA" >}}.**

Reason: {{< term "POTA" >}} uploads require an operator park reference (you must be activating a park). Activity Log is designed for hunters who are not at a park, so no park reference exists.

If you're activating a park, use the session-based Logger instead.

### Upload Timing

{{< term "QSO" >}}s queue for upload immediately upon saving. Sync happens in the background. Check Settings > Services to verify upload status.

## Activity Detection

Activity Log {{< term "QSO" >}}s trigger the same activity detection as session-based logs.

Detected activities include:

- **New {{< term "DXCC" >}} entity**
- **New band** (first contact on this band)
- **{{< term "DX" >}} contacts** (distance-based thresholds)
- **Streaks** (consecutive days with QSOs)

View detected activities in the Friends tab.

## Inline Editing

Modify logged {{< term "QSO" >}}s directly from the daily summary.

### Editing a QSO

Tap any {{< term "QSO" >}} row to open the edit sheet. Modify any field, then tap **Save** to update.

Changes sync to upload services automatically.

### Deleting a QSO

Swipe left on a {{< term "QSO" >}} row to reveal the **Delete** button.

A confirmation dialog appears to prevent accidental deletion. Confirm to remove the {{< term "QSO" >}} from the log and queue deletion sync to services.

## Settings

Access Activity Log settings from the Activity Log view or Settings > Activity Log.

### Station Profiles

Manage all station profiles:

- **Add Profile** - Create a new equipment configuration
- **Edit Profile** - Modify existing profiles
- **Delete Profile** - Remove unused profiles

Deleted profiles do not affect existing {{< term "QSO" >}}s logged with that profile.

### Upload Services

View which services are enabled for Activity Log uploads:

- QRZ.com status
- Ham2K LoFi status

Configure service credentials in Settings > Services.

### Daily Goal

Set your target {{< term "QSO" >}} count for each day.

Range: 1-999 {{< term "QSO" >}}s.

### Spot Age Threshold

Configure the maximum age (in minutes) for spots to appear in the spot list.

Range: 5-30 minutes. Default: 12 minutes.

### Spot Proximity Radius

When **Heard Nearby** is enabled, set the radius in miles.

Range: 100-2000 miles. Default: 500 miles.

### Spot Sort Order

Choose default sort order for the spot list:

- Recent (newest first)
- Frequency (ascending)

## See Also

- [Spot Monitoring](/reference/spots/) - Understanding {{< term "RBN" >}} and {{< term "POTA" >}} spots
- [Logger](/reference/logger/) - Session-based logging for activations
- [Home](/reference/dashboard/) - View overall statistics
- [Community & Activity](/reference/community/) - Friends, clubs, and activity feed
