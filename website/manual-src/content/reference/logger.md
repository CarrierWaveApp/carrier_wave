---
title: "Logger"
description: "QSO entry, session management, commands, and logging features"
weight: 1
showToc: true
---

The Logger is Carrier Wave's primary interface for recording contacts. It provides rapid {{< term "QSO" >}} entry, session management, real-time callsign lookup, and a comprehensive command system for controlling your operating session.

## Starting a Session

### Session Start Wizard

The wizard is organized as a top-to-bottom journey so the required fields are always the loudest thing on screen:

1. **Identity** - Your callsign hero with a plain-text gear line beneath it (e.g. "Van POTA · FT-891 · ATAS"). Tapping the gear line opens a menu to switch, edit, or manage loadouts.
2. **Essentials** - **Programs** and **Radio** (mode, frequency, and power together, with frequency and power side by side), each under a prominent header.
3. **More Options** - A single collapsed row hides the optional tail: station, people, contest add-on, WebSDR, pack checklist, notes, and save-as-defaults.

**Start** is a pinned bottom button rather than a toolbar action, with the disabled reason (if any) shown directly above it. The casual and contest wizards follow the same pattern.

**Basic Parameters:**
- **Mode** - {{< term "CW" >}}, {{< term "SSB" >}}, {{< term "FT8" >}}, FM, AM, FT4, {{< term "RTTY" >}}, PSK31, DATA
- **Frequency** - Operating frequency in MHz (optional - supports hunt-first flow and auto-pick, below)
- **Activation Type** - Casual, {{< term "POTA" >}}, {{< term "SOTA" >}}

**Equipment:**
- **Radio/Rig** - Select from user-managed radio list
- **Antenna** - Current antenna in use
- **CW Key** - For Morse code operations
- **Microphone** - For voice modes
- **Power** - Transmit power in watts (US max: 1,500W)

**Additional Fields:**
- **Attendees** - Who's operating (for multi-operator sessions)
- **Photos** - Session photos (captured or imported from library)
- **Notes** - Session-level notes

**Activation Details:**

When operating {{< term "POTA" >}} or {{< term "SOTA" >}}:
- **Park Reference** - Supports multi-park n-fer operations with removable chips
- Search parks by name/reference or find nearby parks using GPS
- Number shorthand: typing "1234" expands to "US-1234"

**Nearby suggestions:**

Selecting POTA, SOTA, or WWFF in the wizard immediately shows the 3 nearest references within 10 mi (16 km) of your current location, sorted by distance. GPS-first with a grid-square fallback if location is unavailable. Tap a suggestion to add it. The magnifying-glass button still opens the full search/picker sheet for searching by name or browsing beyond 10 mi. If nothing is within 10 mi, the suggestion list is hidden and you'll need to search manually.

**Park auto-fill:**

When POTA is selected and the park field is empty, the wizard prepopulates it with the best nearby candidate — the park you've activated most often within 16 km (from your session history), falling back to the closest. The suggestion updates itself when the GPS fix lands, but never overwrites a park you typed, a saved default, or a park pre-filled from the map or a template.

**Inline reference fields during a session:**

The Logger expanded fields row swaps in the right field for the active session type:

- POTA sessions show **Park** (auto-enriched from spot lookup of the worked station)
- SOTA sessions show **Summit** (their summit reference for S2S contacts)
- Dual POTA + SOTA sessions show both — Summit primary, Park beneath

Typing a SOTA reference (e.g. `W6/CT-225`) directly into a quick-entry token is not yet wired up; use the inline Summit field for S2S logging.

**Contest Templates:**

If you're operating a contest, Carrier Wave can pre-configure your session from the WA7BNM contest calendar. The calendar is polled every 6 hours for upcoming events. Select a contest from the list, and the wizard populates the appropriate mode, band, exchange fields, and logging template. See [Contest Support](/reference/contests/) for details.

**Portable Callsign:**

Configure callsign prefix/suffix for portable operations:
- Prefix: `I/W6JSV` (international)
- Suffix: `/P` (portable), `/M` (mobile), `/MM` (maritime mobile), `/AM` (aeronautical mobile), or custom

**Session QSO Comment:**

Set an optional comment that is automatically prepended to every QSO's notes when logged during this session. Useful for consistent contest exchanges or activation notes across all contacts.

**Wizard Options:**

- **Save as Defaults** - Remember these settings for next time
- **Save as Template** - Save this configuration as a named template for quick reuse
- **Skip wizard next time** - Jump straight to logging with saved defaults

### Session Templates

Save session configurations as named templates for quick reuse. Templates store mode, frequency, activation type, equipment, and other wizard settings.

- **Save** a template from the session start wizard
- **Load** a template to pre-fill the wizard with saved settings
- **Delete** templates you no longer need

Templates are separate from "Save as Defaults" — you can have multiple named templates for different operating scenarios (e.g., "POTA CW", "Contest SSB", "FT8 Portable").

### Same as Last Session

A **Same as Last Session** card appears above the session type grid when a previous finished session exists. Tapping it starts a new session immediately — no wizard — using the most recent finished session's mode, frequency, programs, equipment, power, callsign extras, and operator roster. Park reference is not carried over, since operators typically move between parks between sessions. The card is hidden if no finished session exists or if the first-launch tour hasn't completed.

### Gear Line

The identity block at the top of the wizard shows a plain-text **gear line** beneath your callsign hero — for example "Van POTA · FT-891 · ATAS" — summarizing your currently-applied loadout, radio, antenna, key, and mic. Tapping it opens a menu to switch loadouts, edit the current one for a quick one-off change (for example, swapping an antenna without creating a new loadout), or manage your loadouts. This replaces the earlier full-screen loadout cards.

### Hunt-First Flow

Frequency is **not required** at session start. If you're hunting before activating, start the session without a frequency and set it later using the `BAND` command or by typing a frequency in the callsign field.

### Auto-Picked Starting Frequency

When you leave the frequency field empty, the wizard suggests a free starting frequency for you. It selects your most-activated band — constrained to the bands the chosen radio can actually work — then finds an open frequency on that band, nestled among live POTA, SOTA, and RBN spots with enough clearance to avoid interference. If the band is quiet, it falls back to the mode's calling frequency. A one-line note under the field explains why the band was picked and how clear the frequency is; a **Change** button clears it for manual entry or the band suggestions list. The pick re-runs when you change the radio or mode, but never overrides a frequency you typed or a band you tapped.

### Active Sessions

Only one session can be active at a time. Starting a new session automatically pauses the previous one.

**Session Actions:**
- **Continue** - Resume a paused session (makes it active)
- **Finish** - End a paused session permanently

### Session Pause & Resume

Pause an active session to take a break without ending it. The session timer stops while paused and resumes when you continue. Auto-spotting also pauses and resumes with the session state. Paused sessions appear in the session list with a pause indicator.

## Callsign Entry

### Callsign Field

The primary entry field with auto-lookup:

1. **Polo Notes First** - Checks your saved callsign notes for nickname/emoji
2. **QRZ Lookup** - Queries QRZ.com for name, QTH, {{< term "Grid Square" >}}, license class

### Callsign Info Card

When a callsign is recognized, the info card displays:
- **Name** - Operator name
- **QTH** - Location
- **Grid Square** - Maidenhead locator
- **License Class** - For privilege validation
- **Callsign Notes Emoji** - Visual identifier from your saved notes

### Contact Count Badges

Badges indicate how many previous {{< term "QSO" >}}s you've had with this station:
- **Bronze** - 10+ contacts
- **Silver** - 25+ contacts
- **Gold** - 50+ contacts

### Auto-Focus

After logging a {{< term "QSO" >}}, the callsign field automatically regains focus for rapid sequential entries.

### Tap-to-Edit

Tap any logged callsign in the session log to bring it back into the entry fields for correction.

## Quick Entry

Type complete {{< term "QSO" >}}s in a single line for rapid logging:

```
AJ7CM 579 WA US-0189
```

### Parsing Rules

- **RST** - {{< term "RST" >}} reports (single value -> both sent/received; two consecutive -> sent/received)
- **Grid Square** - 4- or 6-character Maidenhead locators
- **State/Province** - US states, Canadian provinces
- **Park References** - {{< term "POTA" >}} refs (US-0189, K-1234, VE-0100)
- **UTC Time Override** - `HH:MM`, `HH:MMZ`, `HHMMZ`, or bare `HHMM` (e.g. `14:30`, `1430Z`, `0930`) sets the {{< term "QSO" >}} timestamp to that UTC time on today's date. Bare 4-digit values that are also valid amateur frequencies (e.g. `1804` on 160m) keep their frequency interpretation; append `Z` to force the time interpretation. Bare 3-digit times require `Z` to avoid colliding with RST values.
- **Notes** - Unrecognized tokens become notes (multi-word notes combine into single badge)

### Token Preview

As you type, color-coded badges show how each component will be parsed. This gives immediate feedback before logging.

**Example:**
```
K6ABC 599 DM13 CA
```
Shows: `K6ABC` (callsign) `599` (RST) `DM13` (grid) `CA` (state)

### Set Session Fields from Quick Entry

A quick-entry line with **no callsign** updates your session settings instead of logging a QSO. For example:

```
14.046 CW CN87
```

sets the active session's frequency, mode, and operator grid in one go — applying to every QSO you log from then on. The live command hint and the confirmation toast both note that the values apply going forward. Tokens a session can't take (parks, states, RSTs, times) are called out as ignored rather than silently dropped. On the Hunter Log (Quick Log), frequency and mode become defaults for future entries; grid is reported as not settable there.

## QSO Fields

### RST Sent / RST Received

Signal reports exchanged during the contact.

**Defaults:**
- Voice modes ({{< term "SSB" >}}, FM, AM): `59`
- {{< term "CW" >}} and digital modes: `599`
- Fields start empty with placeholder hints showing the default

**Auto-advance:** Typing into RST Sent moves focus to RST Received as soon as the value reaches the expected length for the current mode — 3 characters for {{< term "CW" >}} / digital, 2 for phone. Only fires on the upward edge, so editing or shrinking the value doesn't re-trigger the jump.

### State/Province

US state or Canadian province. Auto-filled from QRZ when available.

**Manual Override:** You can override the auto-filled value if the operator gives you a different location (common during portable operations).

### Grid Square

Maidenhead {{< term "Grid Square" >}} locator (4 or 6 characters).

### Park Reference

For {{< term "POTA" >}} contacts:
- Supports multiple park references (activator operating from multiple parks)
- Chip-based UI with removable badges
- Search picker with nearby parks from GPS
- Number shorthand: `1234` -> `US-1234`

### Operator

Individual operator's callsign if different from the station callsign (e.g., guest operators at club stations).

**Placeholder Hint:** Shows QRZ name as placeholder when field is empty.

### Notes

Free-form text for memorable details about the contact.

### Field Visibility

**Always-Visible Fields:** Configure in Settings -> Logger which fields appear without expanding.

**More Chevron:** Tap to expand additional fields when needed.

## Commands

Type commands in the callsign field to control your session:

### Frequency & Band

| Command | Description |
|---------|-------------|
| `14.060` | Set frequency (supports kHz, MHz, with optional unit suffix) |
| `14.030.50` | Sub-kHz precision (dot-separated format) |
| `BAND` | Open band picker with live spots and clear-frequency recommendations |

### Mode

| Command | Description |
|---------|-------------|
| `MODE CW` | Switch to specified mode |
| `CW` | Bare mode name also works (CW, SSB, FT8, FM, etc.) |

### Spotting

| Command | Description |
|---------|-------------|
| `SPOT` | Post {{< term "POTA" >}} self-spot |
| `SPOT QRT` | Post spot with "QRT" comment |
| `SPOT QSY 14.062` | Post spot with custom comment |
| `SPOT <message> REPEAT <minutes>` | Set custom auto-spot message and interval |
| `SPOT STOP` | Cancel repeating spot timer |

**Alias:** `QRT` for `SPOT QRT`.

### SMS Spotting

When you're off-grid with no data connection, Carrier Wave can spot your POTA or SOTA activation via text message (SMS). This sends a spot to the POTA/SOTA network through an SMS gateway, ensuring hunters can find you even without cellular data or WiFi.

### Spot Monitoring

| Command | Description |
|---------|-------------|
| `RBN` | Show your {{< term "RBN" >}} and {{< term "POTA" >}} spots |
| `RBN K6ABC` | Show spots for any callsign |
| `POTA` | Show active {{< term "POTA" >}} spots panel with band/mode filters |
| `P2P` | Find park-to-park opportunities via nearby {{< term "RBN" >}} skimmers |

### Conditions & Tools

| Command | Description |
|---------|-------------|
| `SOLAR` | Show solar conditions (K-index, SFI, propagation) |
| `WEATHER` | Show weather conditions from NOAA |
| `MAP` | Show session {{< term "QSO" >}}s on a map |
| `WEBSDR` | Open WebSDR receiver picker or connect to last receiver |

**Aliases:** `SDR`, `REC`, `RECORD`, `SWL` also open the WebSDR receiver.

### Session Management

| Command | Description |
|---------|-------------|
| `NOTE <text>` | Add timestamped note to session log |
| `RIG` | Edit equipment (radio, antenna, key, mic) during active session |
| `HIDDEN` | View and restore deleted {{< term "QSO" >}}s from current session |

**Alias:** `DELETED` also opens hidden {{< term "QSO" >}}s.

### External Resources

| Command | Description |
|---------|-------------|
| `CHECKLIST` | Deep link to CW Field Guide outing checklists (passes session radio) |
| `MANUAL` | Open CW Field Guide radio manual for current radio |

**Alias:** `CL` for `CHECKLIST`.

### Help

| Command | Description |
|---------|-------------|
| `HELP` | Show list of all available commands |

## Command Quick Reference

All commands and their aliases in one place:

| Command | Aliases | Description |
|---------|---------|-------------|
| `14.060` | | Set frequency |
| `BAND` | | Open band picker |
| `MODE CW` | `CW`, `SSB`, `FT8`, etc. | Switch mode |
| `SPOT` | | Post {{< term "POTA" >}} self-spot |
| `SPOT QRT` | `QRT` | Post QRT spot |
| `SPOT QSY 14.062` | | Post spot with comment |
| `RBN` | | Show your {{< term "RBN" >}} and {{< term "POTA" >}} spots |
| `POTA` | | Show active {{< term "POTA" >}} spots |
| `P2P` | | Find park-to-park opportunities |
| `SOLAR` | | Show solar conditions |
| `WEATHER` | | Show weather conditions |
| `MAP` | | Show session {{< term "QSO" >}}s on a map |
| `WEBSDR` | `SDR`, `REC`, `RECORD`, `SWL` | Open WebSDR receiver |
| `HUNT` | `POTA`, `SPOTS` | Show activator spots (POTA + SOTA) |
| `HUNT <call> <freq>` or `HUNT <call> <mode>` | | Log a one-off off-frequency QSO without changing the session; missing freq/mode falls back to the session (e.g. `HUNT N9HO 14060`) |
| `NOTE <text>` | | Add timestamped note |
| `RIG` | | Edit session equipment |
| `HIDDEN` | `DELETED` | View deleted {{< term "QSO" >}}s |
| `CHECKLIST` | `CL` | Open CW Field Guide checklist |
| `MANUAL` | | Open radio manual |
| `HELP` | | Show available commands |

## Band Plan Validation

### License Privilege Checking

If you've set your license class in Settings (Tech, General, Extra), Carrier Wave validates:
- **Frequency Privileges** - Warns when operating outside your license allocations
- **Mode Restrictions** - Alerts for {{< term "CW" >}}-only vs voice segments

### Warning Banner

The unified frequency warning banner shows:
- License violations (out-of-privilege operation)
- Mode violations (e.g., voice in {{< term "CW" >}}-only segment)

**Note:** Warnings don't prevent logging. You may be logging someone else's {{< term "QSO" >}}s or operating under a different license.

### Band Plan Visual Chart

The BAND command displays a visual chart of the current band plan, showing:

- **Sub-band segments** color-coded by mode allocation (CW, data, phone)
- **License class boundaries** highlighted for your configured class
- **Your current frequency** indicated by a cursor marker
- **Active spots** overlaid as density indicators showing where activity is concentrated

This chart provides an at-a-glance view of band allocation and activity, helping you find clear frequencies and stay within your privileges.

### Sub-kHz Precision

Supports frequencies like `14.03050` or dot-separated format `14.030.50` for precise logging.

## Frequency Activity

### RBN Monitoring

Monitors {{< term "RBN" >}} activity within +/-2kHz of your frequency:
- **QRM Assessment** - Alerts when other stations are operating nearby
- **Operator Nearby** - Suppressed when the nearby spot is the station you're working

### Unified Warning Banner

Combines license violations and frequency activity warnings in a single banner for clarity.

## Auto Mode Detection

When you change frequency, Carrier Wave automatically switches to the appropriate mode:
- {{< term "CW" >}} segments -> CW mode
- DATA segments -> FT8/digital mode
- Phone segments -> {{< term "SSB" >}} mode

**Toggle:** Enable/disable in Settings.

## Duplicate Detection

### Same-Band Duplicates

{{< term "QSO" >}}s with the same callsign, same band, same UTC date are blocked:
- **Log Button Disabled** - Cannot save duplicate
- **Warning Banner** - Explains why the contact is flagged

### Different-Band Contacts

Contacts with the same callsign on a different band or date are **highlighted green**:
- Indicates you've worked this station before
- Confirms this is a valid new contact (different band/date)

### POTA Rove Duplicate Detection

During {{< term "POTA" >}} rove sessions, duplicates are detected **per park stop**. You can work the same station from multiple parks in the same session.

## Session Log

### Recent QSOs

The session log shows recent contacts filtered by the current session:

- **UTC Times** - Displayed with "Z" suffix (e.g., 18:45Z)
- **Contact Info** - Nickname and callsign notes emoji
- **Total Count** - Number of contacts per row

### Swipe-to-Delete

Swipe left on any {{< term "QSO" >}} to delete:
- Requires confirmation dialog
- Use `HIDDEN` command to view and restore deleted contacts

## Keyboard Customization

### Number Row

Persistent row above keyboard with:
- Digits 0-9
- Decimal point
- Configurable symbols (customize in Settings -> Logger -> Number Row)

### Command Row

Configurable buttons for frequently-used commands. Customize in Settings -> Logger -> Command Row. Drag to reorder buttons and toggle visibility.

### Dismiss Button

Quickly dismiss the keyboard when needed.

## Equipment Tracking

### Session Equipment

Equipment propagated to all {{< term "QSO" >}}s logged during the session:
- Radio/rig
- Antenna
- {{< term "CW" >}} key
- Microphone
- Custom equipment

### Equipment Capsule

Tappable capsule in the session header shows current equipment. Use `RIG` command to edit equipment during an active session.

### ADIF Export

Equipment is exported as `MY_RIG` in ADIF files for compatibility with other logging software.

## Session Photos

Attach photos to your session for documenting your operating location, setup, or conditions.

### Adding Photos

Add photos during session start in the wizard, or at any time during the session from the session detail view:

- **Camera** - Capture a new photo
- **Photo Library** - Select existing photos

### Viewing Photos

Photos appear in the session detail view with a full-screen viewer. Swipe between photos and pinch to zoom.

### Photo Storage

Session photos are stored locally on device. They are included in iCloud Drive backup mirrors when enabled but do not sync via CKSyncEngine to other devices due to size constraints.

## Session Management

### Simple Logging Mode

Enable **Settings → Appearance → Logging** to hide the situational chips in the in-session header. When on, the header shows only the essentials: callsign, QSO count, park, frequency/band, and mode. Hidden chips include operating shift, equipment, duration, space weather, and SDR/radio status. Useful during a busy pileup when you want a clean, scannable header. The full detail is still available by turning the toggle off.

### Session Header

Shows:
- **Session Title** - Tap to customize
- **Duration** - Time elapsed since session start
- **QSO Count** - Total contacts in session

### End Session

**Active Session:**
- Red "End Session" button
- Auto-navigates to Logbook tab when ended (if session has {{< term "QSO" >}}s)

**No Active Session:**
- Green "Start Session" button

### Edit Session Callsign

Change the station callsign for an existing session from the session detail menu. This updates the callsign on all QSOs in the session — useful when you realize you logged under the wrong callsign or forgot to set a portable prefix.

### Delete Session

Hides all {{< term "QSO" >}}s and cleans up spots and photos.

**Confirmation Required:** Type "delete" to confirm (prevents accidental deletion).

### Keep Screen On

Enable in Settings -> Logger to prevent device sleep during active sessions.

## Session Timeline & Replay

### QSO Timeline

Each session displays a horizontal timeline bar showing the timing and distribution of contacts:

- **Band-colored ticks** for each QSO
- **Collapsed gaps** indicate periods of inactivity (more than 10 minutes between contacts)
- **Mode change markers** showing when you switched modes

### Session Replay

From the session detail view, tap the timeline to enter replay mode. The replay animates your session chronologically, plotting each QSO on the map as it occurred. Use the scrubber to jump to any point in the session.

## Live Activity & Dynamic Island

When a logging session is active, Carrier Wave displays a Live Activity on the lock screen and in the Dynamic Island.

### Lock Screen Display

- Current {{< term "QSO" >}} count
- Operating frequency and mode
- Park reference (for POTA activations)
- Last callsign logged

### Dynamic Island

- **Compact view** - QSO count and park reference
- **Expanded view** - Full session details including frequency, mode, and last callsign

The Live Activity updates in real time as you log contacts, change frequency, or pause/resume the session. It clears automatically when you end the session.

See [Widgets & Live Activity](/reference/widgets/) for details on all widget types.

## Session Share Cards

Generate a shareable image card summarizing your session's highlights:

- **Map** with QSO locations and geodesic arcs
- **Session statistics** (QSO count, duration, bands, modes)
- **Equipment summary**
- **Conditions** (solar and weather)

Share cards are generated from the session detail view via the share button. See [Brag Sheets & Share Cards](/reference/brag-sheets/) for customization options.

## Video Export

Export an animated video of your session showing QSOs plotted on a map over time with toast-style notifications for each contact. Video export supports real-time and highlight modes, configurable map styles, and optional audio overlay.

See [Video Export](/reference/video-export/) for full details.

## Rove Stop Batch Grid Editing

During POTA rove sessions, you can batch-edit the grid square for all QSOs at a specific stop:

1. Open the session detail view
2. Tap the rove stop you want to edit
3. Select **Edit Grid for Stop**
4. Enter the corrected grid square
5. All QSOs at that stop update to the new grid

This is useful when GPS was inaccurate or unavailable at a stop, or when you realize you logged the wrong grid after moving on.

## iPad Layout

### Two-Pane Layout

On iPad with regular width:
- **Left Pane** - Logger with {{< term "QSO" >}} entry
- **Right Pane** - Persistent spots sidebar ({{< term "POTA" >}}, {{< term "RBN" >}}/My Spots, P2P tabs)

### Compact Width

On compact width (iPhone or iPad split view), the sidebar is hidden and the Logger uses the full width.

### Sidebar Toggle

NavigationSplitView sidebar toggle visible on Logger tab for manual control.

## Toast Notifications

### Success Feedback

Toast messages appear for:
- {{< term "QSO" >}} logged successfully
- Spot posted
- Command executed
- Friend spotted alerts

### Haptic Feedback

Success haptic (gentle bump) when logging a {{< term "QSO" >}}.

## See Also

- [FT8 Operating Suite](/reference/ft8/) - FT8 waterfall, decoding, and TX control
- [Radio Control](/reference/radio-control/) - Frequency and mode sync with your radio
- [POTA Activations](/reference/pota/) - Activation tracking and park management
- [Spot Monitoring](/reference/spots/) - {{< term "RBN" >}}, {{< term "POTA" >}}, and P2P spots
- [Activity Log](/reference/activity-log/) - Daily QSO tracking for hunters
- [Map View](/reference/map/) - Visualize contacts geographically
- [WebSDR Integration](/reference/websdr/) - Remote receiver access
- [Contest Support](/reference/contests/) - Contest templates and Cabrillo export
- [Settings & Services](/reference/settings/) - Configure Logger behavior
