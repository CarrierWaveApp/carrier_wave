---
title: "Smart Spot Needs"
description: "Need categories, needs-on-air matching, notifications, and HamAlert export"
weight: 10
showToc: true
---

Smart Spot Needs automatically identifies spots that match your operating goals, helping you work new entities, states, parks, and other targets without manually scanning spot lists.

## Overview

Smart Spot Needs monitors incoming spot data (POTA, SOTA, WWFF, RBN) and alerts you when a spot matches a configured need category. This transforms passive spot watching into active goal pursuit.

## Need Categories

### DXCC Needs

Track DXCC entities you haven't worked:

- **All-time new** - Entities not in your log at all
- **Band-new** - Entities not worked on a specific band (for DXCC Challenge)
- **Mode-new** - Entities not worked on a specific mode
- **Confirmed-new** - Entities worked but not yet confirmed via LoTW or QRZ

Carrier Wave builds your DXCC needs list from your QSO database automatically. When a spot appears for a DXCC entity you need, it's flagged with a "DXCC" badge.

### WAS (Worked All States) Needs

Track US states and Canadian provinces:

- **States not worked** on any band
- **Band-specific gaps** for band-WAS awards
- **Mode-specific gaps** for mode-WAS awards
- **Confirmed-only** for states needing QSL confirmation

### POTA Park Needs

Track POTA parks you haven't worked:

- **Unworked parks** - Parks with no QSO in your log
- **State-specific** - Focus on parks in states you're targeting
- **Activation needs** - Parks you haven't activated (for activators pursuing park count goals)

### WWFF Reference Needs

Track WWFF references:

- **Unworked references** globally or by country program
- **National program completion** tracking

### Challenge Needs

When participating in [challenges](/reference/community/#challenges), spots matching challenge criteria are flagged:

- **Challenge badge** with the challenge name
- **Points value** if the spot contributes to challenge scoring
- **Priority ranking** based on challenge deadline proximity

### Custom Pattern Needs

Define your own matching rules using patterns:

- **Callsign patterns** - Match specific callsign prefixes (e.g., `VK*` for Australian stations)
- **Frequency ranges** - Match spots within a frequency range
- **Grid square patterns** - Match specific grids or grid prefixes
- **Combined conditions** - AND/OR logic for complex rules

## Configuring Needs

### Settings Location

Configure Smart Spot Needs in **Settings -> Smart Needs**.

### Enabling Categories

Toggle each need category on or off:

- **DXCC** - On/Off
- **WAS** - On/Off
- **POTA Parks** - On/Off
- **WWFF** - On/Off
- **Challenges** - On/Off (auto-enabled when you join a challenge)
- **Custom** - Add/edit/delete custom rules

### Notification Cooldown

Set the minimum time between alerts for the same need:

- **Default:** 30 minutes
- **Range:** 5 minutes to 2 hours
- **Per-need:** The cooldown applies per specific need (e.g., per DXCC entity)

This prevents alert fatigue when a station remains spotted for an extended period.

## Needs-on-Air Matching

### How Matching Works

Every time new spot data arrives (approximately every 45 seconds during active sessions), Carrier Wave:

1. Checks each spot against all enabled need categories
2. Consults your QSO database for worked-before status
3. Applies band and mode filters from your configuration
4. Generates a prioritized list of matching needs

### Priority Ranking

Matching spots are ranked by priority:

1. **Challenge needs** (time-limited, highest urgency)
2. **DXCC all-time new** (rarest opportunities)
3. **DXCC band/mode new** (for award progress)
4. **WAS needs** (state completion)
5. **POTA/WWFF park needs** (park collection)
6. **Custom patterns** (user-defined priority)

### Notification

When a need is matched, Carrier Wave delivers:

- **Toast notification** in the app with the need category badge
- **Sound alert** (configurable, can be disabled)
- **Push notification** if the app is in the background (requires notification permission)
- **Widget update** for the Needs widget

## Dashboard Card

The Smart Spot Needs card on Home shows:

- **Active needs count** - How many of your needs are currently spotted
- **Top 3 needs** with callsign, frequency, and need category
- **Tap to expand** into the full needs view

## Full Needs View

The expanded needs view shows all currently matched spots:

- **Grouped by category** (DXCC, WAS, POTA, etc.)
- **Sort options** - By priority, by age, by frequency
- **Spot details** including callsign, frequency, mode, age, and SNR
- **Tap a spot** to open the Logger pre-filled with the spot's details

### Need Detail

Tap any need to see:

- Why this spot matches (e.g., "Japan (JA) - New DXCC entity, not in your log")
- Your current progress toward the related award
- Recent activity from this entity/state/park

## Widget

The Needs widget for the iOS home screen shows matching spots at a glance. See [Widgets & Live Activity](/reference/widgets/#needs-widget) for details.

## HamAlert Export

Export your needs configuration as a HamAlert trigger list:

1. Go to **Settings -> Smart Needs**
2. Tap **Export to HamAlert**
3. Carrier Wave generates a trigger list compatible with HamAlert's import format
4. Share the file via email or save to Files

### What's Exported

- DXCC entity list (entities you need)
- Callsign prefixes for WAS needs
- POTA park references you haven't worked
- Custom patterns converted to HamAlert syntax

### Keeping HamAlert in Sync

Re-export periodically (e.g., weekly) to update your HamAlert triggers as you work new entities and parks. Carrier Wave regenerates the list based on your current QSO database each time you export.

## Performance

Smart Spot Needs is designed for low overhead:

- **Cached needs list** rebuilt only when QSOs change (not on every spot check)
- **Incremental updates** when new QSOs are logged
- **Background-safe** matching runs on a background thread

For logs with thousands of QSOs, the initial needs list computation may take a few seconds. Subsequent checks are near-instantaneous.

## See Also

- [Spot Monitoring](/reference/spots/) - Spot data sources and filtering
- [Home](/reference/dashboard/) - Needs card on Home
- [Widgets & Live Activity](/reference/widgets/) - Needs widget
- [Settings & Services](/reference/settings/) - Smart Needs configuration
- [Community & Activity](/reference/community/) - Challenge needs integration
