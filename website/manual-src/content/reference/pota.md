---
title: "POTA Activations"
description: "Parks on the Air logging, rove mode, uploads, and activation management"
weight: 4
showToc: true
---

Carrier Wave provides full-featured POTA activation logging with auto-spotting, rove mode, cloud upload, and detailed activation analytics.

## Starting a POTA Activation

### Activation Type

Set {{< term "Session Type" >}} to **POTA** in the session start wizard. This enables park-specific features including auto-spotting, upload tracking, and activation statistics.

### Park Reference Entry

Enter one or more park references using any of these methods:

- **Manual entry**: Type a full reference (e.g., `US-1234`) or use shorthand (`1234` auto-expands to `US-1234`)
- **Search by name or number**: Start typing to search all POTA parks by name or reference
- **Nearby parks**: Enable location services to see parks sorted by proximity to your current GPS position

### Multi-Park Activations (n-fers)

Select multiple parks to activate simultaneously. Parks appear as removable chips in the session header. When you post a spot, it goes to **all** selected parks at once.

Tap the **x** on a park chip to remove it from the activation. This is useful for transitioning between parks in rove mode or correcting an accidental selection.

### Hunt-First Flow

If you don't know your operating frequency yet, skip frequency entry at session start. Set it later using the `BAND` command or manual frequency picker. This supports hunt-first activation workflows where you tune around before settling on a frequency.

### Park Detail Sheet

Tap any park chip to open the park detail sheet showing:

- POTA statistics for the park
- Top activators and hunters leaderboard
- Recent activations with dates and callsigns

## Rove Mode

Rove mode lets you activate multiple parks sequentially in a single session, with automatic tracking of which {{< term "QSO" >}}s belong to which park stop.

### Starting a Rove

Add multiple parks at session start, or add parks on-the-fly during the session. Use **Next Stop** to transition between parks.

### Rove Progress Bar

A horizontally scrolling progress bar shows each stop as a pill, with:

- Park reference and QSO count
- Current stop highlighted
- Scroll left/right to see all stops

### Per-Stop Tracking

Each stop tracks:

- QSOs logged at this location
- GPS grid (auto-updated when transitioning)
- Start/end timestamps
- Frequency and mode changes

### Automatic Spot Management

When you transition to the next park:

- A **QRT** spot is posted for the previous park
- A new **initial spot** is posted for the current park
- The auto-spot timer resets

### Duplicate Detection

Duplicate callsign detection is **per park stop**. If you work the same station at multiple stops, only the first QSO at each park is flagged as a duplicate. This prevents false warnings when moving between parks.

### UTC Midnight Splitting

Sessions spanning UTC midnight are automatically split into separate activations, ensuring each activation covers only one UTC date. This matches POTA's requirement that activations run from 0000-2359 UTC on a single day.

### Rove Map Visualization

Use the `MAP` command to see your rove route:

- Numbered markers for each stop
- Dashed line connecting stops in sequence
- QSO locations overlaid on the route

## Auto-Spotting

Carrier Wave posts spots automatically during POTA sessions.

### Initial Spot

When you start a session, an initial spot is posted immediately (if you've set a frequency). For multi-park activations, the spot includes all park references.

### Periodic Spots

The auto-spot timer posts a spot every **10 minutes** (configurable in Settings -> POTA). This keeps your activation visible in the spot feed.

The timer:

- Pauses when the session is paused
- Resumes when the session resumes
- Resets on QSY or park transitions

### QSY Spots

When you change frequency or mode, Carrier Wave prompts you to post a **QSY spot**. This notifies hunters of your new frequency.

### QRT Spots

When you end a session, a **QRT spot** is posted automatically (if the session was previously spotted). This can be disabled in Settings -> POTA.

### Manual Spots with SPOT Command

Use `SPOT` to post a manual spot with an optional comment:

- `SPOT` -- post a basic spot
- `SPOT QRT` -- post a QRT spot immediately
- `SPOT QSY 14.062` -- post a QSY spot with new frequency

## Spot Comments

POTA supports comments on spots, which Carrier Wave fetches and displays during active sessions.

### Background Polling

While a session is active, Carrier Wave polls for new spot comments in the background. This happens automatically without user intervention.

### Spot Comments Button

A button in the session header shows the count of new comments. Tap to open the comments sheet.

### Comments Sheet

The comments sheet shows:

- Hunter feedback and messages
- Consecutive RBN (Reverse Beacon Network) spots collapsed into expandable groups
- Average CW speed (WPM) calculated from RBN spots
- Timestamp and callsign for each comment

### Auto-Attach to QSOs

Comments are automatically attached as notes to matching {{< term "QSO" >}}s (matched by callsign and timestamp proximity). This preserves hunter feedback with the logged contact.

## Sessions View

The Sessions view shows all POTA activations alongside other session types in a unified list.

### Session Row Content

Each session row displays:

- Park reference(s) and activation date
- QSO count and timeline visualization
- Upload status badges (pending, submitted, accepted)
- Equipment badges (antenna, key, mic)
- Photo count badge
- Conditions summary (solar index, weather)
- Recording player (compact inline waveform)

### Session Detail

Tap a session to see:

- Full equipment list
- Attached photos
- Notes and observations
- Recorded spots (expandable, aggregated by band with deduplication)
- Complete QSO list with expand-to-see-all-fields
- Edit button (modifies park reference, date, notes)
- Statistics section (when Professional Statistician Mode is enabled)

### Swipe to Delete

Swipe left on a session to reveal the delete button. A confirmation dialog prevents accidental deletion.

### Professional Statistician Mode

When enabled in Settings -> POTA, session detail includes:

- Band distribution chart
- Mode distribution chart
- Distance CDF (cumulative distribution function)
- Timing CDF (inter-QSO intervals)
- RST statistics (sent/received averages)
- Entity count (DXCC, states, provinces)

## Upload Workflow

POTA uploads are now **fully manual via ADIF export**. The Upload buttons on the session list and activation rows open the ADIF export sheet — save the file, then upload it yourself on [pota.app/user/logs](https://pota.app/user/logs) (landscape / pinch-to-zoom on mobile, then choose the file). A first-time instruction card walks through the steps; dismiss with **Got It** (permanent) or **Show Next Time**, and the **?** toolbar button brings it back.

### QSO Grouping

QSOs are grouped by:

- Park reference
- UTC date
- Operator (multi-op sessions)

Each group becomes a separate ADIF file. **N-fer activations fan out by park**: a 5-fer produces 5 ADIFs (one per park), a 3-fer produces 3, and so on. Every file lists the same QSOs but writes only its own park into `MY_POTA_REF` so each upload is unambiguous to POTA. The "Split by Park" toggle in the export sheet auto-enables whenever any QSO carries a multi-park reference, even when every QSO shares the same comma-separated string.

### Upload Status

Each activation shows one of three states:

- **Pending** -- QSOs have not been uploaded
- **Submitted** -- QSOs uploaded, waiting for POTA processing (blue clock icon)
- **Accepted** -- POTA has accepted the activation

### Upload Prompt

When you end a session, a sheet prompts you to upload immediately or defer. The sheet includes:

- Scrollable content showing all activations
- Expandable detents (half-height, full-screen)
- Upload, reject, or export buttons

### Conditional Upload

Carrier Wave can be configured to conditionally hold uploads until specific criteria are met:

- **Minimum QSO count** - Hold uploads for activations with fewer than 10 QSOs (the POTA minimum)
- **Review required** - Require manual review before uploading (useful for verifying park references and QSO data)
- **Network condition** - Defer uploads until Wi-Fi is available (avoid large uploads on cellular)

Configure conditional upload behavior in Settings -> POTA -> Upload Settings.

### Bulk Actions

In the Activations view, use multi-select mode to:

- Upload multiple activations at once
- Mark activations as rejected (won't upload)
- Export multiple activations to ADIF

When you export several activations at once, the export sheet offers a **Combined / Split by Park** mode:

- **Combined** (the default) writes every selected activation into a single ADIF file.
- **Split by Park** writes one ADIF per park, with that park as the only park in the file. N-fer QSOs fan out into each of their parks, and the same park activated across different days or sessions is merged into a single file — then all the files are shared at once. Use this when you want to upload each park separately to POTA.

## Upload Status & Jobs

POTA upload jobs are tracked and displayed in the Activations view.

### Job Monitoring

Carrier Wave provides real-time monitoring of POTA upload jobs:

- **Job progress** updates automatically as jobs move through the POTA processing pipeline
- **Push notifications** alert you when a job completes or fails (if enabled)
- **Background polling** checks job status periodically without requiring the app to be in the foreground
- **Status timeline** shows the progression from submitted to queued to processing to completed

### Job Matching

Jobs are matched to activations by:

- Park reference
- UTC date
- Callsign

This ensures upload status is accurate even for multi-day or multi-park sessions.

### Job Status Display

Each activation shows:

- Job ID and submission timestamp
- Processing status (queued, processing, completed, failed)
- Error messages (if any)

A **warning icon** appears on activations with failed jobs. Tap to see the full POTA error message inline (e.g., "Duplicate activation detected" or "Invalid park reference").

### Reconciliation

During sync, Carrier Wave reconciles upload status from the POTA job log:

- Submitted QSOs are matched to completed jobs and marked as accepted
- Orphaned submitted QSOs (where POTA silently dropped the upload) are reset to pending

### Force Reupload (Debug Mode)

In Settings -> Advanced -> Debug Mode, a **Force Reupload** button resets all QSOs in the activation to pending and triggers a fresh upload. Use this if upload status is out of sync.

### Maintenance Window Handling

POTA servers are offline from **2330-0400 UTC** for maintenance. If you end a session during this window, Carrier Wave warns you and suggests uploading later.

## PSK Reporter: Who Heard Me?

After a session using digital modes (FT8, FT4, WSPR), the "Who Heard Me?" section queries PSK Reporter data for your callsign during the session time window:

- **Map overlay** showing receiving stations that decoded your signal
- **Station count** and geographic distribution
- **Signal reports** (SNR) from each receiving station
- **Band breakdown** showing which bands had the best propagation

This provides post-session propagation analysis beyond what RBN spots capture, particularly useful for digital mode activations.

## POTA Activation Detail

Tap an activation in the Activations view to see full details.

### Header

- Park reference(s) and activation date
- Upload status badge
- Edit button (changes park, date, notes)

### Upload Controls

- Upload Now button (pending activations)
- Mark as Rejected button
- Export to ADIF button
- Force Reupload button (debug mode)

### POTA Jobs

List of upload jobs for this activation, showing:

- Job ID and timestamp
- Status and error messages
- Tap for detailed job log

### Session Timeline

A horizontal bar with band-colored ticks representing each QSO. Collapsed gaps indicate periods of inactivity (more than 10 minutes between QSOs). Tap the timeline to enter replay mode, which animates QSOs on the map chronologically.

### QSO List

Scrollable list of all QSOs in the activation. Tap a row to expand and see all fields. Swipe left to delete individual QSOs (with confirmation).

### QSO Distance Histogram

A histogram showing the distribution of contact distances during the activation:

- **X-axis** represents distance ranges (in miles or km based on your units preference)
- **Y-axis** shows the count of QSOs in each range
- **Color coding** by band to show which bands reached which distances

This visualization helps you understand propagation patterns and the geographic reach of your activation.

### Signal Mosaic (State Grid)

A grid visualization showing which US states and Canadian provinces you contacted during the activation:

- **Colored cells** indicate states/provinces worked
- **Color intensity** maps to the number of QSOs per state
- **Empty cells** highlight gaps in coverage

The mosaic provides a quick visual summary of your geographic spread across North America.

### Club Members Summary

If you belong to any clubs (via Polo notes lists), the activation detail shows a summary of club members you worked during the activation:

- **Club name** and count of members contacted
- **Member callsigns** in an expandable list
- **Percentage** of club roster worked

### Statistics Section (Professional Statistician Mode)

When enabled, shows:

- Band distribution pie chart
- QSO rate over time
- Distance CDF
- Timing CDF (inter-QSO intervals)
- RST statistics (sent/received)
- Entity counts (DXCC, states, provinces)
- Two-column summary grid (QSOs/hr, max distance, median RST, etc.)

### Equipment Badges

Displays antenna, key, mic, and other equipment used during the activation.

### Recording Integration

If you recorded audio during the session, a compact inline player shows the waveform and playback controls.

### Conditions

- Solar gauge (SFI, A-index, K-index)
- Weather badge (temperature, conditions icon)
- Tap for full solar and weather details

### Recorded Spots

An expandable section displays all {{< term "RBN" >}} and {{< term "POTA" >}} spots captured during the session, aggregated using the same logic as the live Logger spot system.

**Tap the section header** to expand or collapse the spot list.

#### Aggregation

Recorded spots are merged and organized identically to the Logger's live spot view:

- **Human spots first** -- POTA spots (posted by hunters) appear before RBN spots
- **Deduplication** -- When the same callsign appears on the same band in both POTA and RBN data, the spots are combined with POTA as the preferred source
- **Band grouping** -- Spots organized by band for easy scanning
- **RBN region collapsing** -- Consecutive RBN spots from the same region are collapsed into expandable groups

#### Visual Indicators

Each spot row displays the same visual indicators used in the live Logger:

- **Age color coding** -- Green (<2 min), Blue (2-10 min), Orange (10-30 min), Gray (>30 min), based on the spot's age at time of capture
- **SELF** -- The spotted station matches your callsign
- **DUPE** -- Already worked on the same band and date
- **TODAY** -- Worked on a different band the same day
- **PREV** -- Worked in a previous session

#### Propagation Review

Because spots are persisted with timestamps and signal data, the recorded spots section serves as a historical record of propagation during your activation. Use it to:

- Review which {{< term "RBN" >}} receivers heard your signal and at what {{< term "SNR" >}}
- See which bands were active and when
- Correlate spot activity with your QSO rate and band changes

### Activation Map

Map showing:

- QSO locations with arcs from your position
- RST-based color coding (green = 59, yellow = 57, red = 55)
- For rove sessions: numbered stop markers and dashed route line

### Share & Export

- Generate brag sheet (shareable image card)
- Export to ADIF
- Export video (animated session replay)
- Save to Photos
- ShareLink for system share sheet

## Activation Share (Brag Sheets)

Brag sheets are shareable image cards summarizing your activation.

### Standard Content

- Map with QSO locations and arcs
- Park reference(s) and date
- QSO count and QSOs/hr rate
- Equipment summary (toggleable in Settings)
- Conditions (solar, weather)

### Professional Statistician Mode Content

When enabled, brag sheets include:

- Box plots (RST, distance, timing)
- Peak QSO rate
- Distribution histograms
- Entity counts

### Sharing

Use **ShareLink** to share via Messages, Mail, AirDrop, etc. Or tap **Save to Photos** to save the image to your library.

See [Brag Sheets & Share Cards](/reference/brag-sheets/) for full customization options.

## Video Export

Export an animated video of your activation showing QSOs plotted on a map over time. See [Video Export](/reference/video-export/) for full details on modes, map styles, and rendering options.

## POTA Settings

Configure POTA-specific behavior in Settings -> POTA.

### Auto-Spotting Interval

Set the interval (in minutes) between automatic spots. Default is **10 minutes**.

### QRT Spotting

Toggle automatic QRT spot posting when ending sessions. Default is **on**.

### Professional Statistician Mode

Enable detailed statistics in session detail and brag sheets. Default is **off**.

### Equipment on Brag Sheet

Include equipment summary on brag sheets. Default is **on**.

### Spot Age, Proximity, Sort

Configure default filters for the Spots view:

- Maximum spot age (e.g., 30 minutes)
- Maximum distance (e.g., 100 miles)
- Sort order (time, distance, frequency)

## Minimum QSO Requirement

POTA requires **10 QSOs** for a valid activation. Carrier Wave tracks your progress toward this goal in the session header and warns you if you attempt to end a session with fewer than 10 QSOs.

## See Also

- [Logger](/reference/logger/) -- {{< term "QSO" >}} logging commands and workflow
- [Activity Programs](/reference/activations/) -- SOTA, WWFF, and other programs
- [Spot Monitoring](/reference/spots/) -- POTA spot feed and filtering
- [Map View](/reference/map/) -- QSO visualization and rove routes
- [WebSDR](/reference/websdr/) -- Remote receiver integration for hunt-first activations
- [Export & Sharing](/reference/export/) -- ADIF export and brag sheet generation
- [Brag Sheets & Share Cards](/reference/brag-sheets/) -- Detailed brag sheet customization
- [Video Export](/reference/video-export/) -- Animated session replay videos
- [Service Sync Flow](/reference/sync-flow/) - Sync and upload mechanics
