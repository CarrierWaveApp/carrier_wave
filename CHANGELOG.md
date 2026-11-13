# Changelog

All notable changes to Carrier Wave will be documented in this file.

Carrier Wave ships as apps with independent version numbers: the iOS/macOS
apps (plus firmware and server) are tracked below, and the Android app is
tracked on its own version line (0.1, 0.2, …) in the [Android](#android)
section at the end of this file.

## [Unreleased]

### Fixed
- **Brag sheet maps center on your QTH (iOS).** Session, activation and TOTA
  brag-sheet maps now center horizontally on the operator QTH and zoom to the
  tightest fit for every contact and its great-circle arc, plus a small margin.
  MapKit can't show more than 180° of longitude, so wider DX sessions (e.g.
  CN87 to JA and EU) render as a QTH-centered world map in the Midnight style
  instead of clipping the QTH or the far contacts.

## [1.106.0] - 2026-11-01

### Added
- **Report satellite status to AMSAT (iOS).** A "Report" button on the
  selected bird's community block and on each transmitter's community page
  files your own observation with AMSAT's status page: transmitter, Heard /
  Telemetry Only / Not Heard (Crew Active for the ISS crew row), the time you
  heard it, your callsign and grid. Submitted straight to status.amsat.org on
  the tap, never in the background; AMSAT's own validation message shows when
  a report is refused. Every community view now carries AMSAT's CC BY 4.0
  attribution link.
- **IC-9700 full-duplex Doppler in CW Sweep (macOS).** Settings → Trackers →
  Doppler CAT gains an uplink target "Sub band of the downlink radio": during a
  pass Sweep switches the IC-9700 into satellite mode (and puts it back
  afterwards or on disconnect), tunes Main to the Doppler-corrected downlink
  and Sub to the pre-corrected uplink, sets USB/LSB on linear birds, and keeps
  the uplink moving while you transmit. On linear transponders the Main dial is
  read back and folded into a passband offset so the uplink follows — reversed
  on inverting transponders. The pass details show the offset and NOR/REV.
  SatNOGS passband edges and the inverting flag now flow through the shared
  catalog; CI-V polling also reads PTT so the TX pill reflects the rig.
- **Add a QSO to an ended session (iOS).** Session detail gains an "Add QSO"
  row (and menu item) on completed sessions: type one line in the logger's
  quick-entry grammar — callsign, RST, park, grid, state, frequency, mode,
  Zulu time, notes, even several callsigns — and it is logged into that
  session through the same shared Rust path as the live logger, with the same
  callsign lookup enrichment and upload marking, without reopening the
  session. A Zulu time lands on the session's own UTC day; otherwise the QSO
  takes the session's end time. Contest sessions are excluded.

### Changed
- **Server 0.4.105 — AMSAT status via AMSAT's new API.** The aggregator now
  reads `status.amsat.org/api/v1` (`catalog.php` for the satellite list and
  one incremental `reports.php?since=…` call per cycle instead of scraping
  the status page and querying ~95 satellites one by one), identifies itself
  with a descriptive User-Agent as AMSAT's guidelines ask, keeps AMSAT's
  15-minute report period so a re-filed report replaces the earlier verdict,
  and falls back to the legacy `www.amsat.org/status` host until AMSAT's
  data migration on 2026-11-04. `AMSAT_STATUS_API_BASE` overrides the base.

## [1.105.0] - 2026-10-23

### Added
- **Satellite list that points at the bird (iOS).** The Satellites tab's
  search button is now a full satellite list: every bird with its next pass
  in the next 24 hours, its primary transmitter, and a compass arrow that
  turns with the phone to point at the satellite — or at where it will rise.
  Tapping a satellite selects it and opens the antenna pointing view, so the
  compass tape and elevation scale guide you onto it; "Show on Map" in the
  row's context menu just selects it.
- **Pass plot on the pointing screen (iOS).** Below the horizon the antenna
  pointing view now draws the next pass as an arc on a compact polar sky
  plot (horizon rim, 30°/60° rings, cardinals), rotated so the direction
  the boom points is up, with the rise point marked. In that state the
  screen also drops the target reticle and the elevation scale and reads
  azimuth only — there is nothing to tilt toward yet.

### Fixed
- **POTA sign-in and links on the rebuilt pota.app (iOS).** Parks on the Air
  relaunched pota.app on 2026-10-15 without the old `#/` hash routes. Automatic
  and manual POTA sign-in now open `pota.app/user/login`, which starts the
  Cognito redirect by itself, and only fall back to pressing a Sign In button
  when the site shows one. The "open POTA logs page" and callsign-change
  links point at `pota.app/user/logs` and `pota.app/user/stats`. The upload
  job list also decodes the new paginated `/user/jobs` response (and pages
  through it) alongside the legacy array. The public spot, park, stats and
  park-catalog endpoints are unchanged and keep working as before.
- **Park names missing from POTA spots (all platforms).** The relaunched POTA
  API leaves `parkName` null on every activator spot and carries the park name
  in `name`. The shared Rust spot core (iOS, macOS, Android), the activities
  server's spot aggregator, the watch app, the widgets and the Pebble bridge
  now fall back to `name`, so spot lists and the server's aggregated spots show
  park names again.
- **Merged POTA sessions exported only one activation's QSOs (iOS).** A
  session's "Export ADIF" (row menu and session detail) handed the exporter a
  single (park, callsign, UTC day) activation — the first one — and the
  exporter re-scoped the QSOs to that activation, so after merging a session
  whose QSOs fell on another UTC day, at another park, or came from a casual
  session with no park, the file silently dropped them. The same path
  exported only the first stop of a rove. Session exports now go through a
  new session-scoped exporter in the shared Rust core (`AdifApi.exportSession`)
  that selects every visible QSO by session id, writes each QSO's own park and
  falls back to the session's park for QSOs without one, and adds the
  session's SOTA summit as `MY_SOTA_REF`. The sheet's QSO count now reports
  what the file holds. Android gets the exporter through the regenerated
  Kotlin bindings (no session export UI there yet).
- **Satellites tab no longer hangs on "Loading orbital data…".** The tab now
  opens straight from cached orbital data and refreshes in the background
  (CW Sweep's satellite tracker too).
  Before, once the 6-hour cache expired, every open waited on SatNOGS's
  ~4 MB transmitter list, which downloads at ~240 KB/s and routinely hit the
  20-second request timeout on phones. A failed download never reset the
  cache clock, so every later open waited out the timeout again. The shared
  satellite engine (iOS, macOS, Android) now gives SatNOGS downloads a
  120-second budget, shares one in-flight refresh between the tab and the
  pass-alert scheduler, and serves the stale cache for 15 minutes after a
  failed download instead of retrying on every open. A manual Refresh still
  goes to the network immediately.

## [1.104.0] - 2026-10-13

### Added
- **Community Activity grid for satellites.** AMSAT's status grid, rebuilt
  inside the Satellites tab (ellipsis menu → Community Activity): every
  AMSAT-tracked transmitter as a row of hour-aligned cells coloured by the
  AMSAT legend (active / telemetry only / not heard / conflicting), with 1 h
  to 1-day cell widths. Each row is enriched from Carrier Wave's other
  sources — the catalog's SatNOGS mode and downlink, your next pass of that
  bird with its peak elevation, and how many QSOs you logged through it this
  week — with favorites floated to the top and filters for favorites, silent
  birds, and birds outside your catalog. Each row fits the whole week in a
  stacked-bar sparkline; pinch to zoom every row together and drag
  sideways to pan, with a reset chip; tap a row for a scrollable,
  pinch-zoomable Swift Charts week view with your own passes shaded behind the
  bars, an hour-of-day histogram, and a Show on Map button. The same signal
  also appears where you already look: a community dot (AMSAT's last-24 h
  colour, hollow when AMSAT doesn't track the bird) on every upcoming-pass
  row and the info card, a matching ring on each map marker, the
  reporters' grid squares plotted on the map for the selected bird, and a
  "Heard by 4 on the previous orbit (DL, ON, EI)" line on the info card —
  what the community saw one orbit ago is the best predictor for your
  pass. The info card also carries a community block with a week
  sparkline per AMSAT capability that opens the hour-by-hour page, and
  thirteen more AMSAT names (TO-108, TEVEL2-3, FO-126, HC1PX, and the
  SatNOGS-temporary-id birds) are now mapped to NORAD ids so their
  community data reaches the app. The activities server now keeps
  every raw AMSAT report (`amsat_report`, deduplicated, 8-day retention) so
  the week's history is complete even for busy FM birds where AMSAT's own API
  caps a query at 100 rows, and serves it at
  `GET /v1/satellites/amsat-status/activity`, with the raw per-bird reports
  at `GET /v1/satellites/amsat-status/reports`; the 7-day summary rows are
  now computed from that stored window too.

## [1.103.0] - 2026-10-11

### Added
- **JTTY in CW Sweep.** WSJT-X 3.2's new keyboard-to-keyboard contest mode
  (4-GFSK, 1.9 s frames, ~125 Hz, no time slots) gets a native terminal in
  CW Sweep: live decoded text, F1–F8 contest macros with WSJT-X's `%M %H %E
  %Q` syntax and serial/Field Day/RTTY Roundup exchange profiles, free-text
  send with gapless queueing, PTT through the connected radio, and one-click
  logging of the worked call. Decoding and encoding run in the separate
  GPL `jtty-sidecar` helper (downloaded on first use and verified against a
  pinned checksum) so the mode's codec never links into the app. JTTY is
  also a first-class digital mode everywhere: the shared Rust mode tables,
  ADIF catalog, WSJT-X logging, quick entry, band plan and CAT mode maps,
  and every CW Sweep mode picker, chip and parser. (CAR-351)
- **Another Morse Trainer streak.** Connect your AMT account (Settings →
  Services → Another Morse Trainer on iOS; Settings → Accounts in CW Sweep)
  with an emailed sign-in link — no password, read-only — and your Morse
  practice streak appears alongside your QSO streaks: a "Morse Practice
  Streak" dashboard metric and a row in the Streaks detail on iOS, a "Morse
  Streak" card on the CW Sweep Dashboard. Practice days are drawn in purple on
  the activity grid (solid for practice-only days, a corner dot on days with
  QSOs too). Stats are cached for offline viewing and refresh when the
  dashboard opens; removing Carrier Wave from your AMT devices signs it out.
  The sign-in, token rotation and stats fetch live in the shared Rust core
  (`cw-net` `AmtClient` / `cw-ffi` `AmtApi`), so iOS, macOS and Android share
  one implementation.
- **Activity grid in CW Sweep.** The Dashboard gains the same GitHub-style
  activity grid as Field: a year (or more) of UTC days, green for activation
  QSOs, blue for hunter QSOs with a diagonal split on days with both, purple
  for Another Morse Trainer practice, month labels, a legend, and hover
  tooltips with the day's counts.
- **WSJT-X logging in Carrier Wave: Field.** Settings → Services → WSJT-X
  brings CW Sweep's WSJT-X listener (CAR-282) to the phone: point WSJT-X →
  Settings → Reporting → UDP Server at the phone's Wi-Fi address (shown on the
  screen with a copy button) and port 2237, and every QSO WSJT-X logs lands in
  the Field log once — repeat broadcasts and the ADIF twin are skipped — and
  attaches to the active session when one is running. QSOs are written through
  the cw-store seam and marked for QRZ / LoFi / Club Log (and POTA inside a
  POTA activation) exactly like the manual logger, so they upload on the next
  sync. The listener binds every interface by default, restarts on each return
  to the foreground, and keeps a live feed of decodes, logged QSOs and skipped
  duplicates in Settings. Gated by the new "WSJT-X Logging" experiment (beta,
  on by default). iOS pauses the socket while the app is in the background.

### Fixed
- **iOS — Hunter Log command buttons did nothing.** RBN, SOLAR, WX, MAP and
  MANUAL (tapped on the keyboard row or typed) only showed "This command is
  only available during an activation". They now open the same RBN, solar,
  weather and session-map panels the activation logger has, fed from the
  hunter log (your callsign and grid, today's hunter QSOs on the map), and
  MANUAL opens the active station profile's radio manual. Activation-only
  buttons (SPOT, HUNT, P2P, S2S) are no longer shown on the Hunter Log's
  keyboard row instead of sitting there inert.
- **iOS — Sessions page said "No contacts yet today" for an active Hunter
  Log.** The card's count was never refreshed until the Hunter Log view was
  opened, and the Sessions tab kept two separate hunter-log managers so QSOs
  logged through one never updated the other. One manager is now shared and
  its today-stats refresh on the Sessions page and after every logged QSO.

## [1.102.0] - 2026-10-05

### Added
- **CW Sat Bridge (firmware-sat/): satellite doppler executor for ESP32-P4.**
  New headless bridge firmware that accepts a precomputed pass schedule over
  BLE (new `Sat*` messages in `proto/cwbp.proto`, capability bit
  `CAP_SAT_DOPPLER`) and flies it against a Quansheng UV-K1/K5 running the
  sugarfree90 CAT firmware: VFO A tracks the doppler-corrected downlink,
  VFO B the corrected uplink, with uplink CTCSS/mode setup, an `IF;` TX
  guard (never retunes mid-transmission), and phone-optional execution on
  the bridge's own clock. Detection gains an `IF;` probe (the CAT fork
  ignores `ID;`). NimBLE runs host-only with the controller on a companion
  ESP32-C6 over HCI UART.
- **Shared doppler schedule core (`firmware-sat/sat-core`)** — packed step
  wire format + executor cursor, consumed by both the firmware and
  `cw-domain`'s new `satellite::doppler_schedule` builder (1 s doppler
  sampling, per-link quantization: 2.5 kHz FM / 100 Hz linear-RX, ≤60 s
  keepalives), exposed to the apps as
  `SatelliteApi.build_doppler_schedule`.
- **iOS: Send to Bridge.** Long-press a pass in Upcoming Passes (when a CW
  Sat Bridge is connected) to build, upload, and arm the schedule; the
  control sheet shows upload progress, the executor's live state and
  frequencies, a downlink/uplink VFO flip, and abort.
- **Automatic detection of CSN S.A.T. and WA4MCM PSR-100 rotators.** Both
  apps sweep the local network for CSN Technologies S.A.T. / SAT Controller
  units (Hamlib rotctld on TCP 4533, web UI fingerprint) and WA4MCM PSR-100
  Mk2 rotors (web UI on :8080 plus EasyComm II / GS-232B / S.A.T.-XML UDP
  probes that also reveal which protocol the rotor is set to). CW Sweep gains
  Settings → Trackers (scan, add by address, connect, park/stop, minimum
  elevation, Doppler CAT slots) and steers the chosen rotator during passes,
  pre-positioning to the AOS azimuth five minutes early. On iOS the satellite
  pointing screen and tab menu gain a Rotator & Trackers sheet that drives
  the same rotator from the selected satellite. Detection is hands-free: both
  apps sweep in the background (at launch / when the satellites tab opens, on
  network changes, and every few minutes), silently re-link the rotator you
  already use, and otherwise ask "CSN S.A.T. detected — Connect?" with Not Now
  and Ignore options. Adding a unit by address probes it and works out the
  type from how it answers, and its network is remembered and swept from
  then on, so a rotor on an IoT VLAN (say 192.168.20.x while the phone is on
  192.168.1.x) is found hands-free after the first time. A whole network can
  also be added as 192.168.20.0/24. The PSR-100 Mk2 is driven through its
  built-in web server (the same `AZ…EL…` / `STOP` commands its own page
  sends, position from its JSON status), which crosses VLANs and needs no
  UDP port setup; the EasyComm / GS-232B / S.A.T.-XML UDP paths remain for
  same-subnet use, and a PSR-100 connected over one of them is switched to
  HTTP control automatically whenever its web server answers. Rotator link
  errors now show the underlying reason instead of a bare "no reply". Both
  apps also gained manual rotator controls: a jog pad with a 1°/5°/15° step,
  go-to azimuth/elevation, Park and Stop (in the CW Sweep rotator card and
  the iOS Rotator & Trackers sheet); jog buttons repeat while held, CW Sweep
  also jogs with the arrow keys (⇧ 15°, ⌥ 1°, Esc stops), and a manual move
  turns Follow off. The iOS sheet shows the desired target (the satellite's
  live az/el, or the rise azimuth before AOS) with its source even before a
  rotator is linked, next to the pointing your taps have commanded. A
  "Point & Track" button on the iOS sky view and under CW Sweep's sky plot
  slews a linked rotator onto the selected satellite and turns Follow on in
  one tap.
- **Two-radio FM satellite duplex with Doppler tuning.** The satellite pointing
  screen gained a Duplex Radios sheet: bind one CW Bridge to the uplink
  handheld and one to the downlink handheld (each bridge gets its own BLE
  link, alongside the logger's primary radio), pick Auto (both radios follow
  the pass prediction) or Manual downlink (tune the downlink by ear and the
  uplink follows your correction), set the uplink CTCSS per satellite (SO-50,
  ISS, AO-91, AO-92 and PO-101 preset to their tones), and start tuning. The
  bridge firmware now recognizes Quansheng UV-K1 / UV-K5 V3 radios running the
  F4HWN CAT build over their USB-C port (CDC-ACM serial, Kenwood-style `FA`/`MD`
  commands, 10 Hz steps), including radios that do not answer `ID;`.
- **Notice when your callsign has no QRZ logbook key.** If the callsign you
  log under differs from the callsign your connected QRZ Logbook API key
  belongs to (for example after a callsign change), QRZ Logbook Sync now shows
  a warning naming both callsigns with a one-tap "Add API Key" action, and the
  QRZ row under Logbook Services shows an orange warning instead of the green
  check. Adding a key for the current callsign makes it the primary account.
  Previously QSOs logged under the new callsign silently never reached QRZ.

### Fixed
- **Carrier Wave Sync: first pull no longer takes half a minute.** A pull
  replaying the journal applied every QSO as its own SQLite autocommit (two
  full disk flushes per row under the store's fsync setting) and fetched each
  journal blob from object storage one round trip at a time. A pull is now
  applied in one transaction and downloads eight blobs at a time; a failed
  batch simply replays next pass since the cursor only advances on success.
  All platforms.
- **No more crashes when switching away from the app mid-sync.** iOS was
  killing Carrier Wave (`0xdead10cc`) when it was suspended while the local
  log database was being read or written, because that database lived in the
  shared App Group folder. It now lives in the app's own storage and is moved
  there automatically on first launch. (CAR-350)
- **Callsign change no longer reverts on relaunch.** After Settings → About Me →
  Change Callsign, the QRZ Logbook sync that runs on every launch re-applied the
  callsign the QRZ API key still belonged to, flipping the profile back to the
  old call until the key was updated. A callsign detected from a connected
  service is now ignored when it is one the operator has explicitly moved away
  from; a typed change back to a previous callsign still works. (CAR-349)
- **Callsign change now reaches the server for signed-in accounts.** The
  change-callsign and claim-previous requests were sent with the legacy device
  token even when a Carrier Wave account session existed, so the account kept
  acting as the old callsign (friends and shared contacts saw the old call) and
  the previous-account merge was always rejected. Account requests now use the
  account session, callsign drift is checked at launch for account sessions
  too, and OAuth-only installs are no longer skipped. (CAR-349)
- **Server: a callsign change can no longer leave an account split.** A change
  request for an account-owned callsign that cannot prove account ownership is
  refused instead of renaming only the legacy tables. Accounts already split by
  the old behaviour are repaired on their next change request: the account is
  re-pointed and anything logged under the stale old-callsign row is folded
  into the renamed user. (CAR-349)

## [CW Sweep 0.14.0] - 2026-10-05

### Added
- **Rotator panel in CW Sweep.** A new Rotator item under System in the
  sidebar is the station rotator console: link state and reported AZ/EL with
  connect / park / stop, hand controls (hold-to-repeat jog pad with a 1° / 5° /
  15° step shared with the Satellites card, go-to AZ/EL, Park, Stop), and the
  LAN scan / add-by-address sections. The same sections back Settings →
  Trackers, which keeps the Doppler CAT options.
- **Satellite mode in CW Sweep.** A new Satellites sidebar item gives the Mac a
  pass console: upcoming passes for the next six hours (active pass
  highlighted with an LOS countdown), a polar sky plot with the predicted
  track dashed, the flown track solid, AOS/LOS labels and a pulsing satellite
  marker, live az/el readouts and an elevation-vs-time profile, pass details
  with NORAD ID, mode line (CTCSS for the common FM birds), Doppler-corrected
  RX and pre-corrected TX rows computed from the SGP4 range rate, an RX/TX
  PTT pill, and range / range-rate / LOS / max-el / altitude / S-meter stats.
  A full-width synthetic waterfall (downlink ±25 kHz, signal width by mode,
  strength by range, dashed rig-tuned marker, frequency scale) can show the
  passband corrected (signal stays put, like Gpredict/SatPC32) or uncorrected
  (signal drifts). The console uses the app's own dark look — black canvas,
  gray cards, system blue/green/red/yellow accents, monospaced readouts. Doppler
  CAT tunes the downlink radio each second (and an
  optional second radio for the uplink); the status bar shows rig/CAT,
  rotator and TLE age. Orbits come from the shared Rust engine (SatNOGS TLEs
  and transponders) with the observer at Settings → General → Grid.
- **CW Sweep: IC-9700 waterfall over LAN**: connecting to an Icom radio over
  LAN/WiFi (RS-BA1) now enables scope waveform output and renders the radio's
  spectrum in the waterfall panel, with center and span read from the radio.
  IC-9700 frames are tagged Main or Sub so the panel follows whichever band
  the scope is showing. Sweep reads the radio's scope on/off and output
  settings when it connects and puts them back when it disconnects, so it
  doesn't leave the scope in a changed state for the next client. Adds the
  IC-9700 (USB and LAN) to the radio catalog and fixes the CW Bridge rig
  detector's swapped IC-7300 / IC-705 addresses.
- **CW Sweep: quieter CI-V command log**: over USB, unsolicited CI-V
  Transceive frames (the radio announcing its own frequency and mode, several
  per second while a satellite tracker drives an IC-9700) no longer fill the
  command log, so replies to Sweep stay visible.

### Changed
- **CW Sweep syncs through Carrier Wave Sync instead of iCloud.** The Mac
  now uses the same end-to-end encrypted sync server as Carrier Wave: Field
  and Android: sign in with your callsign (Settings → Accounts, emailed
  sign-in link), enter your sync passphrase (Settings → Sync), and QSOs and
  sessions flow both ways. Passes run after you log, every few minutes,
  on wake and on demand (status bar, ⌘K "Sync Now", Vim `:sync`). Under the
  hood the Rust store is now the Mac's canonical store (writes go there
  first through the shared seams; pulled rows are replicated into the
  SwiftData store the UI reads), and the server-sync client, OAuth client
  and write seams moved into the shared package so iOS and macOS run one
  implementation. The orphan reconciler no longer prunes store-only rows
  under Rust authority — a latent iOS bug where CloudKit-inbound QSOs could
  be dropped. Plan: `docs/plans/2026-10-05-sweep-carrier-wave-sync.md`.

### Fixed
- **CW Sweep no longer asks "would like to access data from other apps" on
  every launch.** macOS 15+ only trusts an iOS-style `group.` App Group
  container when a provisioning profile vouches for it, and Sweep's
  Xcode-managed profiles never did, so the prompt returned each launch and
  Allow never stuck. The Mac app now uses the team-prefixed group
  `7UE4RDLUSX.com.jsvana.FullDuplex`, which macOS verifies from the code
  signature. On first launch the app moves its data (`cw-store.db`, the
  SwiftData store and CloudKit assets) into the new container before
  anything opens it; that one move can prompt a final time.
- **CW Sweep's waterfall uses far less CPU**: the waterfall panel drew every
  bin of every line as its own rectangle (about 95,000 per redraw, redrawn
  for each new scope line). It now draws the lines as one image. With an
  IC-9700 streaming over LAN, CW Sweep dropped from about 90% to about 20% of
  a core.
- **CW Sweep no longer pins a CPU core while a band scope or band map is
  on screen**: each spot canvas stored its click/hover hit areas in view
  state on every draw, which scheduled another draw — an endless redraw loop
  (about 100% of a core with the default layout and no radio connected; now
  about 4%). Affects the contest band scope, the band map and the regulated
  band map.
- **CW Sweep connects to Icom radios over LAN in about a second**: the
  "are you there" packet is now resent every second during the handshake.
  The IC-9700 often ignores the first one, which made the first attempt time
  out and the retry connect about 7 seconds later. A failed attempt no longer
  leaves a dead session behind (it was torn down again on the next
  disconnect), and the Yaesu-only `SS05;` span query is no longer sent to
  CI-V radios.
- **CW Sweep menu and layout fixes**: Radio › Connect Radio… (⌥⌘R) now opens
  the Radio section instead of doing nothing; the layout menu's New Layout… /
  Edit Layout… / Duplicate Current… open the layout editor again (the sheet
  was attached inside the toolbar menu, where macOS never shows it);
  disconnecting twice in a row (a double click while the radio is closing)
  no longer tears the same connection down twice; and the Icom LAN
  "Connected to …" log line shows the RS-BA1 port (50001) instead of 4992.
- **CW Sweep clears the IC-9700 scope output it leaves behind**: the radio
  keeps scope waveform output per connection (LAN and USB separately), so an
  "on" left by another client (wfview) was never turned off. Sweep now always
  turns its own connection's output off on disconnect, and the command log
  shows every scope command sent on connect and on disconnect.
- **CW Sweep no longer crashes on launch on macOS 15**: the SCU-LAN10 audio
  player connected its player node with a 16-bit integer format, which
  AVAudioEngine rejects with an exception while the radio manager starts up.
  It now uses the standard Float32 format and converts the radio's 16-bit
  samples as they arrive.
- **CW Sweep doesn't touch iCloud while sync is off**: the iCloud account
  check now runs only when sync is enabled (and when you turn it on), so
  builds without the iCloud entitlement start normally.

### Removed
- **CW Sweep: iCloud sync.** The CKSyncEngine journal, the iCloud toggle and
  CloudKit push handling are gone from the Mac app; the iCloud entitlements
  stay for Key-Value Storage. Existing logs are untouched.
## [1.101.0] - 2026-09-27

### Added
- **CW Sweep: WSJT-X logging.** Settings → WSJT-X turns on a UDP listener
  (default 127.0.0.1:2237; point WSJT-X → Settings → Reporting → UDP Server at
  it). QSOs WSJT-X logs appear in the Carrier Wave log once: its repeat
  broadcasts and the ADIF copy of each QSO are recognised and skipped, the QSO
  attaches to the active session, and a live feed of decodes plus a status-bar
  badge show what WSJT-X is doing. The ingest service lives in CarrierWaveData
  so Field can adopt it later. (CAR-282)
- **CW Sweep: S.A.T. satellite log listener.** Settings → S.A.T. enables a UDP
  or TCP ADIF listener (default UDP 2333) for the CSN Technologies S.A.T.
  tracker; point its QSO LOG IP at the Mac address shown there and every
  satellite QSO it logs lands in the Carrier Wave log tagged "S.A.T." with
  `SAT_NAME` / `PROP_MODE` preserved, deduplicated against retransmits and
  attached to the active session. File ADIF imports now keep the satellite
  fields too. (CAR-343)
- **WSJT-X over UniFFI (Rust core).** `cw-ffi` exposes a `WsjtxApi` listener
  (`start(host, port, delegate)` / `stop` / `isRunning`) with a
  `WsjtxListenerDelegate` callback delivering decoded WSJT-X messages
  (Heartbeat, Status, Decode, QSOLogged, LoggedADIF, Close, Other) as UniFFI
  records, plus `wsjtxMapQsoLogged` / `wsjtxMapLoggedAdif` helpers that turn a
  logged QSO into a store `FfiQso` ready to upsert. Groundwork for FT8/FT4
  auto-logging in Field and Sweep; app wiring is CAR-282. Also repairs three
  hand-written `FfiQso` initialisers in the CarrierWaveCore package that had
  not compiled since the satellite fields landed. (CAR-281)
- **Structured JSON logs and request correlation ids (server).**
  `LOG_FORMAT=json|pretty|compact` (default `json`) selects the log format;
  every request runs in a `request` span carrying `request_id`, `method`,
  `path` and `route`, emits one `request completed` line with `status` and
  `latency_ms`, and echoes `X-Request-Id` (honoured if supplied, UUID
  otherwise). Health and metrics polls log at DEBUG. The stale default
  `RUST_LOG` filter named the wrong crate and is fixed. See
  `server/docs/logging.md` for `journalctl | jq` recipes and the Loki /
  Grafana Cloud shipping plan. (CAR-156)
- **CW Sweep: your own spot stands out in the spots list.** The operator's
  spot gets an accent gutter bar, a person icon and a "You" badge, is pinned
  to the top under the default time sort, and gets an accent ring/bar on the
  band map chip. (CAR-204)
- **WSJT-X logged QSOs map into the store (Rust core).** New
  `cw_store::wsjtx_import` turns the decoder's `QsoLogged` (type 5) and
  `LoggedADIF` (type 12) messages into `Qso` rows: WSJT-X mode/band/frequency
  normalisation, `import_source = "wsjtx"` provenance, and a stable UUIDv5
  identity derived from the app's dedup key so both messages for one QSO
  collapse into a single row. Includes the first Rust ADIF-record → QSO
  mapping (a port of iOS `ImportService.createQSO`). Not yet exposed over
  FFI. (CAR-280)
- **CW Sweep: vim command mode has full command-palette parity.** New `:freq`
  (MHz or kHz), `:mode`, pane navigation (`:logger` `:spots` `:cluster`
  `:dashboard` `:log` `:radio` `:sync [now]`), `:inspector`, `:role <name>`,
  and status-line info commands `:find <call>`, `:last [N]`, `:count`, all
  routed through the same code paths as Cmd+K / Cmd+Shift+P. Also wires the
  radio palette's `SPOT [comment]` and the Activation menu's Spot Now to the
  self-spot service; both previously never reached it. (CAR-211)
- **WSJT-X Status and Decode messages decoded (Rust core).** `cw-net`'s
  WSJT-X UDP decoder now fully decodes Status (dial frequency, mode, DX
  call/grid, report, TX state, RX/TX DF, DE call/grid, watchdog, sub-mode,
  fast mode, special operation mode, frequency tolerance, T/R period,
  configuration name, TX message) and Decode (new, time, SNR, delta
  time/frequency, mode, message, low confidence, off air) instead of
  surfacing them as opaque `Other` messages. Fields WSJT-X appended in later
  releases decode best-effort so older WSJT-X/JTDX/MSHV datagrams still
  parse. Not yet exposed over FFI. (CAR-283)

### Changed
- **App versions have a single source of truth.** iOS and CW Sweep marketing
  versions and build numbers now live only in `swift/Versions.xcconfig`; both
  Xcode projects derive `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` from
  it, the Xcode Cloud build-number bump targets that file, and a new
  `scripts/check-versions.sh` (pre-commit, release script, CI) fails if the
  xcconfig, the newest What's New entry, or the newest released changelog
  heading disagree. (CAR-158)
- **Sessions list no longer re-sorts and re-groups on every screen update
  (iOS).** Month sections are cached and rebuilt off the main thread only
  when the underlying sessions change, and every activation-metadata lookup
  is now bounded instead of fetching the whole table. (CAR-154)
- **Configurable Postgres pool size (server).** `DATABASE_MAX_CONNECTIONS`
  (default 16, was a hard-coded 5) sizes the sqlx pool shared by HTTP
  handlers, aggregators and background loops; exposed in the Ansible env
  templates. (CAR-159)
- **Scheduled club roster sync (server).** Clubs with a callsign-notes URL
  (BKG's `members.txt`, for example) are now reconciled against that file
  every 6 hours instead of only when an admin pressed "import". New
  callsigns are added, members who left the list are removed, admins are
  never touched, and an empty or failing fetch leaves the roster alone. The
  BKG roster had been stuck at ~30 members while the published list grew
  past 550. The admin import endpoint runs the same routine and now reports
  removals; the admin club list shows when each roster last synced.

- **CW Bridge PCB: panel headers, status LEDs and finished WROOM routing
  (hardware).** The board is fully routed again after the August swap from
  the XIAO to a bare ESP32-S3-WROOM-1U left every module trace dangling.
  New: a 1×04 I²C header for a 128×64 OLED (replaces the 2×04 SPI screen
  header and frees GPIO4/7/9 plus two expander pins), a 1×04 panel LED
  header (power, Bluetooth searching/paired, USB connected/identified;
  series resistors on-board, driven from the PCAL6416A alongside the
  on-board LEDs), and RESET/BOOT moved from on-board tactiles to 1×02
  headers. `LED_ST1/LED_ST2` are now `LED_BT/LED_USB`. BOM/CPL regenerated;
  DRC is back at its 4-hole baseline. The stale pre-swap gerbers were removed.
  J1 is now a horizontal, JLC-placed USB-A (SHOU HAN AF 90 WJDG) instead of
  the hand-soldered vertical Molex, and every header carries a pin-1 mark and
  a purpose label on the silk. The antenna is a U.FL-to-SMA bulkhead pigtail from the
  WROOM-1U to the enclosure; no antenna parts live on the PCB.
- **CW Bridge firmware ported from the Heltec dev board to the rev 2 PCB
  (firmware).** New `board.rs` pin map: encoder phases on GPIO1/2, shared
  I²C on GPIO5/6, ES8388 codec over I²S (MCLK 43 / BCLK 39 / LRCK 40 /
  DOUT 42 / DIN 3) replacing the bare-DAC output and ADC capture, buttons +
  encoder switch + BT/USB status LEDs on the PCAL6416A expander, console UART
  on GPIO41. Removed the Heltec-only VBAT sampler, Vext/OLED-reset handling
  and TRS jack detection (no such circuits on the board).
- **External SDR waterfall for CW Sweep (macOS).** Any SDR can now feed the
  waterfall. It can watch a radio's IF output, such as the Elecraft K3/K3S
  8.215 MHz IF OUT, or an antenna directly. The rig's CAT frequency, mode,
  RIT and TX state drive the mapping from SDR frequency to RF, so the
  waterfall stays centered on the VFO and tap-to-tune works. Sources are
  SoapySDR (SDRplay, RTL-SDR, Airspy HF+; loaded at runtime from Homebrew),
  rtl_tcp/rsp_tcp servers, and built-in test tones. Settings → SDR has a K3
  preset and per-mode IF calibration on a known carrier. The capture, the
  FFT and the frequency mapping run in Rust (new `cw-sdr` crate, exposed
  through `cw-ffi`).

### Fixed
- **Activation brag sheet works offline (iOS).** It no longer shows "No grid
  data available" when there is no connection. Map imagery that cannot be
  fetched falls back to a vector map (contacts, RST-coloured paths, a "Map
  imagery unavailable offline" caption) at the same card size; contacts
  without a grid are placed by their park, summit or DXCC entity and the rest
  are counted as "N contacts without location"; opening the sheet retries
  callsign lookups and re-renders, and Share / Save to Photos export exactly
  what is on screen. (CAR-135)
- **CW Sweep: QSO logger rows render at one uniform height.** Long callsigns,
  RST strings laid out in narrow or hidden columns, wide band badges and
  optional park icons no longer make individual rows taller; every cell is
  single-line with tail truncation and the table enforces a 28 pt row.
  (CAR-193)
- **Re-spots always advertise your own frequency (iOS).** Tapping a spot to
  hunt another activator from inside your activation set the session
  frequency to theirs, and the 10-minute auto re-spot, `SPOT REPEAT`, QSY
  and QRT spots all read that value, so your call was re-spotted on the other
  operator's frequency. The session now tracks a separate self-spot
  frequency that only your own QSYs move; hunting never touches it, and the
  QRT spot at end of session uses it too. Android was not affected. (CAR-296)
- **PoLo metadata rows no longer sit as "pending upload" forever (iOS).**
  Ham2K PoLo's WEATHER/SOLAR/NOTE/TODO/START/BREAK markers are QSO-shaped
  rows, not contacts. Three sync paths kept arming them for upload and the
  per-sync clear only knew three of the six modes. All six are now in
  `QSOMode.metadataModes` (and the Rust `METADATA_MODES`), the merge, orphan
  and dead-state repairs skip them, and a one-time launch repair clears the
  stale flags on existing installs. (CAR-278)
- **CW Sweep: tuning a spot is never a silent no-op.** The legacy KiwiSDR
  "Tune In" button no longer exists; with no radio connected, Tune & Log now
  recentres the external SDR waterfall, records where the tune went in the
  radio command log, and the spot context menu explains the destination. The
  context menu's Lookup, previously an empty action, now opens QRZ. (CAR-121)
- **Sync snapshots are now two-phase (server).** `POST /v1/sync/snapshot`
  only presigns the upload and records a pending attempt; a new
  `POST /v1/sync/snapshot/commit` verifies the blob exists before moving the
  live pointer or garbage-collecting journal entries. Snapshot sequences
  outside `(currentSnapshotSeq, highWater]` are rejected and the pointer
  never moves backward, so a crashed or abandoned upload (or a hostile
  `sync:write` token) can no longer leave an account with a dangling
  snapshot and a deleted journal. (CAR-334, CAR-338, CAR-341)
- **Macro run-event roll-ups could be undercounted (server).** The daily
  retention sweep deleted raw events past a mid-day cutoff, so the 90-day-old
  bucket was aggregated, half-deleted, re-aggregated from the survivors and
  frozen at the lower number. The horizon is now day-aligned and the roll-up
  upsert never lowers a stored count. (CAR-325)
- **`/v1/health` reports database health (server).** The endpoint runs
  `SELECT 1` with a 2 s timeout and returns 503 with `database: "error"`
  when Postgres is unreachable; the monitoring probe now hits `/v1/health`
  instead of `/`. (CAR-157)
- **Web logbook no longer stops at the oldest 500 entries (logbook-web).**
  The viewer read only the first page from `/v1/sync/bootstrap` and reported
  success, so accounts with more than 500 journal entries were missing their
  most recent QSOs from the count, the ADIF export and the duplicate scan. It
  now pages `/v1/sync/changes` to the server's high-water mark, fails loudly
  if paging stalls, and when an entry's encrypted blob is missing it skips
  that entry and shows an "Incomplete logbook" warning instead of failing the
  whole load. (CAR-321)
- **Web logbook ADIF export wrote wrong field lengths for non-ASCII text
  (logbook-web).** The `<FIELD:length>` prefix counted UTF-16 code units, so
  `José` was tagged `:4` instead of `:5` and strict importers truncated the
  value. Lengths now match the Rust and Swift exporters; logbook-web gained a
  vitest suite pinning the behaviour. (CAR-320)
- **OAuth example client returned a truncated log for large accounts
  (examples/oauth-log-client).** `loadQsos` folded only the bootstrap page
  and never consulted `highWater`; it now pages `/v1/sync/changes?since=` to
  completion and refuses to return partial data if paging stalls. (CAR-318)
- **Web logbook duplicate deletes no longer wedge sync on a failed upload
  (logbook-web).** A single failed blob PUT used to abort the remaining
  uploads and leave committed journal entries with no blob, so every device's
  next sync hit a 404 forever. Each upload now retries with exponential
  backoff, every entry is attempted, and blobs that still haven't landed are
  parked locally (sealed ciphertext only, fingerprinted to the data key) and
  re-pushed on demand. (CAR-322)
- **Web logbook warns before closing mid-delete and can resume an unfinished
  one (logbook-web).** The tab asks before unloading while uploads are in
  flight, a partial failure shows how many entries are still waiting with a
  Retry button, and reopening the duplicate finder offers to resume or
  discard leftovers. CORS-shaped failures name the R2 PUT prerequisite.
  (CAR-319)
- **Starting an activation no longer waits on slow spot sources for a
  frequency (iOS).** The session wizard used to hold the frequency field in
  a "Finding an open frequency…" spinner until POTA, SOTA *and* RBN had all
  answered — up to 30 s on a bad connection — with no way to type a value
  in the meantime. The calling frequency for the operator's usual band now
  lands the instant the sheet opens; the live spot fetch gets 3 s to
  upgrade it to a clear gap, then the wizard picks from whichever sources
  have answered (the note says so) while the fetch finishes in the
  background for the band scope. The spinner row also has a "Set manually"
  button, concurrent spot loads share one fetch, and opening the scope no
  longer collapses when a later auto-pick lands.
- **Brag sheet club counts now follow the club roster (iOS).** The session
  brag sheet's club section was a snapshot taken at session end and never
  revisited, so sessions logged while the BKG roster was stuck at ~30
  members kept showing the old counts after the server caught up. The club
  sync now records a roster revision and posts a notification when the
  cache changes; the session club-member snapshots are recomputed against
  the current roster whenever that revision moves, instead of once ever.
- **Club roster removals and role changes never reached devices (server).**
  The `/v1/clubs/sync` and `/v1/clubs/membership` ETag only tracked club
  edits and member join times, so deleting a member or changing a role left
  clients on `304 Not Modified` with the old roster until something else
  changed. Every roster mutation now bumps the club's `updated_at`.
- **Self-spot toasts now echo the comment that actually went out (iOS).**
  Typing `QRT` in the command bar posted a QRT spot to POTA but reported
  "Spotted at US-1234: QSY to 14.068" in the app — the toast hardcoded
  "QSY" for every commented spot. It now shows the real comment alongside
  the frequency ("QRT · 14.068"). (CAR-347)
- **Session wizard frequency scope readout now matches the reticle (iOS).**
  After the scope opened on an auto-picked frequency, the readout and the
  row under the reticle could disagree (reticle on 14.051, readout 14.068).
  The scope worked out the centered row by dividing the scroll offset by the
  row height, but the lazy list gives rows it hasn't rendered yet an estimated
  height, so after any jump the offset stopped mapping to a row — straight
  after opening on 14.068 it pointed at 14.094. Each on-screen row now checks
  whether its rendered frame sits under the reticle, so the readout always
  names the row you can see. (CAR-346)

## [1.100.1] - 2026-09-20

### Changed
- **Satellite pointing mode keeps the tuning readout while steering (iOS).**
  The Doppler-corrected downlink/uplink, mode, and Doppler shift no longer
  disappear when you drift off target — they stay below the correction
  chevrons at a fixed size and position, so the frequency doesn't move
  when lock is gained or lost (parity with the same Android change).

### Fixed
- Network failure messages from the shared Rust core now include the
  underlying cause chain (DNS / TLS / connection refused / timed out)
  instead of reqwest's opaque "error sending request for url (…)", so
  user-reported fetch failures (e.g. the Satellites SatNOGS load) are
  diagnosable from the on-screen error alone. Applies to every cw-net
  client on both platforms.
- **Satellites: real names instead of "OBJECT C" placeholders.** The shared
  catalog now also fetches SatNOGS's satellite registry (cached 6 h like the
  other feeds, soft-fail) and prefers its canonical names — with OSCAR
  designator aliases promoted — over the TLE line-zero names, which carry
  launch placeholders for ~285 birds (TO-108/CAS-6 showed as "OBJECT C").
- **Satellites: FO-29 (and other mislabeled birds) restored.** SatNOGS marks
  every FO-29 transmitter `service: Unknown`, which the amateur-only catalog
  filter dropped entirely. AMSAT-tracked birds with zero amateur-service
  transmitters now get their transmitter list admitted anyway — AMSAT
  tracking is itself the amateur signal. (Both reported by KM7BUM.)
- **Server: AMSAT status rows for 28 more satellites now carry NORAD ids**
  (AO-123, NO-44, IO-86, UO-11, SO-127, TEVEL2-7/8, SONATE-2, the RS*S
  fleet, and more), so the apps can join their heard-recently reports,
  names, and workability signal — previously those rows were name-only and
  silently ignored by the catalog.

## [1.100.0] - 2026-09-20

### Added
- **Satellite logging (SAT_NAME / PROP_MODE)**: QSOs now carry first-class
  satellite fields end-to-end — new `sat_name`/`prop_mode` columns in the
  shared Rust store (schema v16), on the E2E sync wire, in the Rust and Swift
  ADIF writers/parsers, and in the QRZ/POTA/eQSL/ClubLog upload records —
  so satellite contacts get LoTW satellite credit (PROP_MODE=SAT is required
  for a match). Satellite fields show in QSO details and are editable in the
  QSO edit sheet; ADIF imports pick them up too. FREQ/BAND follow the ADIF
  convention (your transmit side = the uplink); FREQ_RX/BAND_RX is a
  deliberate follow-up.
- **Satellite post-LOS quick log**: a "Log pass QSOs" button on the pointing
  screen (whenever the bird is below the horizon — i.e. right after LOS) and
  a "Log" button on the satellite info card open a one-screen pass log:
  satellite, transmitter, mode, and time are prefilled and you only type
  callsign + grid per contact (rows auto-append; per-row time override).
  Contacts are written through the shared Rust logger under a lightweight,
  already-completed "AO-91 pass" session — your live POTA activation is
  never paused — with SAT_NAME/PROP_MODE forced on every QSO and the usual
  QRZ/LoFi/ClubLog upload routing.
- **Shared Rust satellite engine (SatelliteApi)**: the whole satellite
  prediction core now lives in the shared Rust workspace — SGP4 propagation
  (the `sgp4` crate plus a SatelliteKit-parity conversion layer,
  fixture-tested to ~0.006° az/el agreement with the shipped iOS engine),
  catalog build with AMSAT workability rules, pass prediction, mutual-pass
  planning, alert planning with the exact iOS notification copy, SatNOGS +
  AMSAT fetching with a 6-hour SQLCipher cache (schema v17) and offline
  stale fallback, and a coastline export for host-drawn charts. This is the
  engine the Android satellite feature builds on, and the one iOS will swap
  to in a follow-up.

- **Work-type filter for the satellite map and pass lists.** Multi-select
  FM / Linear / Digital / Telemetry filter (both platforms, persisted,
  shared between surfaces) — telemetry is its own bucket (downlink-only
  transmitters you can receive but never work through), so beacon-only
  cubesats can be hidden without losing real digital birds, and linear
  birds toggle on/off as one group (CW rides the transponder). On the map
  it lives in the ⋯ menu (iOS) / a toolbar filter dropdown (Android) so no
  map real estate goes to chips; the upcoming-passes list keeps chips. At
  least one bucket always stays enabled, and the explicitly selected bird
  never disappears from the map.
- **Uplink/downlink band filters.** Alongside the work-type buckets, the
  same filter can narrow by band letters (H/V/U/L/S/C/X) independently
  for uplink and downlink — "show me birds I can hit with 2 m up and hear
  on 70 cm down." A bird qualifies when a single transmitter satisfies
  mode + uplink band + downlink band together; an active uplink filter
  means "has an uplink in these bands," so receive-only telemetry drops
  out of an uplink-narrowed view. On the pass list the "↑/↓" chips expand
  an inline letter row that toggles in place — multi-select without the
  list ever closing; the map keeps everything in its filter menu.
- **Mutual passes show your sky's direction — and obey your horizon.**
  Mutual windows now carry the pass geometry from your station (rise /
  peak / set azimuths), shown on each row ("your sky SW → peaks S → NW"),
  and the horizon mask applies to your side of every mutual window. The
  planner's leftover funnel icon is gone — its 10° workable floor is now
  always on (raised by the shared elevation threshold when higher), with
  the footer spelling out exactly what's filtering.
- **Horizon mask: minimum elevation by direction.** Beta-tester ask
  (N9HO: "depending on the direction I may be deaf until above 30°") —
  the clear-sky filter grew from on/off sectors into a real horizon
  mask: each of the 8 compass directions carries its own minimum
  elevation (tap to cycle 0° → 10° → 20° → 30° → 45° → blocked), and a
  pass counts only if its peak clears the minimum for the direction it
  peaks in. Applied to the map, the next-pass strip, the all-sky list,
  and now the per-satellite pass schedule too (which also gained the
  shared elevation threshold). The flat threshold picked up the steps
  operators actually use — 15° and 25° join the list. Mutual windows
  keep the flat threshold (they carry no azimuth geometry).
- **Heard-recently, favorites-only, and clear-sky filters — and one
  filter everywhere.** Three more dimensions on the shared satellite
  filter: "Heard this week" keeps only birds the AMSAT community
  confirmed alive in the last 7 days (untracked birds keep the benefit
  of the doubt), "Favorites" narrows every surface to starred birds, and
  a clear-sky horizon mask (8 compass sectors) drops passes peaking in
  directions your horizon is blocked. The Mutual Pass Planner now runs
  on the same shared filter as the map and pass lists (its separate mode
  chips and per-station chip ordering are gone) — modes, bands,
  heard-recently, favorites, and the elevation threshold all apply to
  mutual windows too; only the sky sectors stay out there, since a
  two-station window has no single-horizon geometry. Both platforms.
- **Next-pass elevation filter.** The satellite filter gains a minimum
  peak-elevation threshold (Any / 10° / 20° / 30° / 45°): pass lists drop
  passes peaking below it, and the map hides birds with no upcoming pass
  reaching it in the sweep window (never applied while the sweep is still
  loading, so the map can't blank on missing data). Both platforms, in
  the filter sheet/dropdown and as an "El ≥" chip on the pass list.
- **Next pass on the satellite info card.** Selecting a bird now shows
  its next pass inline — "Next pass in 25m · peaks 34°" (or "Up now ·
  sets in 12m" mid-pass), with the peak color-graded like the pass lists
  and the marginal tag when it's a 10–20° pass. Both platforms.
- **Per-mode "heard today" dots on transmitter rows.** Every transmitter
  row on the satellite info card, pass list, and sky-dome footer (both
  platforms) now carries the AMSAT community signal for that specific
  capability: green when the mode was heard in the last 24 hours, dim
  gray when AMSAT tracks it but nobody reported it today, nothing when
  the capability is untracked. On hybrid birds this finally shows *which*
  side is alive — FM repeater heard, transponder quiet, or vice versa.

### Changed
- **Linear birds are back on the satellite lists.** The AMSAT
  community-silence rule hid any tracked satellite with no "heard" report
  in 7 days — which systematically erased linear transponder birds, since
  AMSAT reporting skews heavily toward the FM crowd. Linear/CW
  capabilities now get a 30-day silence window (in both the
  satellite-level gate and the per-capability transmitter filter, on both
  platforms via the shared engine); FM and digital keep the 7-day rule,
  and famous dead linear birds stay on the curated derelict list.
- **iOS satellites now run on the shared Rust engine.** The Swift
  SGP4/pass-prediction stack (SatelliteKit dependency, SatNOGS/AMSAT
  clients, pass predictor, mutual planner, workability gates, display-name
  and polarization tables, alert planner) is deleted; the tracker model,
  pass lists, mutual planner, and headless pass-alert scheduler all call
  the same `SatelliteApi` Android uses. One engine, one set of orbits and
  alert identifiers on both platforms.
- **Satellite in-pass recording (record now, structure later)**: a REC PASS
  button on the pointing screen records the whole pass from the microphone
  (voice-grade AAC, ~4 MB per pass), and while recording the screen shows one
  giant MARK button — tap it each time you work someone. After LOS the
  quick-log sheet plays the recording back inline with a chip per mark
  (tapping rewinds 5 seconds before your tap so the callsign is right
  there), and your marks pre-seed one contact row each at the marked time.
  This is the community's own technique — record the pass, log after LOS —
  productized with zero AI. Recordings live outside backups and clean up
  after 7 days.
- **Satellite pass alerts + favorites**: star satellites from the info card,
  the search list, or a pass sheet — favorites sort first everywhere, and
  favoriting your first bird enables pass alerts (with the notification
  permission prompt). Local notifications fire before each favorited pass
  ("SO-50 pass in 15 min · Peaks 62° · W → E · 6 min"), default ≥20° peak
  (the handheld-antenna recommendation; 10–20° passes are now labeled
  "marginal" throughout and can be opted into alerts). Configure lead time
  (10/15/30 min) and the marginal opt-in from the new bell button on the
  satellites tab. Schedules refresh on app foreground and via a 6-hour
  background-refresh task, and survive offline on cached TLEs. Tapping an
  alert opens the satellites tab with the bird selected and starts a
  pass-countdown Live Activity (Dynamic Island + lock screen, self-driving
  timer that flips to in-progress at AOS and dims after LOS). A compact
  "next workable passes" strip (favorites first) now leads the satellites
  tab above the time scrubber.
- **Satellites tab (alpha, hidden experiment)**: new hidden tab showing live
  amateur-satellite positions on a map — SatNOGS DB TLEs filtered to the
  ~480 satellites with amateur-service transmitters, propagated on-device
  with SGP4 (new SatelliteKit dependency) and animated smoothly once per
  second. The map opens centered on your grid square. Tap a satellite for
  name/NORAD/altitude, its transmitters (mode, uplink/downlink frequencies),
  its coverage footprint circle, and its ground track; search by name or
  NORAD ID. A time slider scrubs the whole sky ±12 hours to preview
  upcoming passes, snapping back to live. Tilt the phone up and the map
  becomes a motion-driven sky dome: pan the phone around to see every
  ham satellite at its true position in your sky (horizon, elevation
  rings, and compass points drawn in). Sweep the crosshair near a
  satellite to see its info card (frequencies, modes) and its dashed
  pass arc across the sky; the selected satellite gets its own arc, an
  arrow guiding you to it, a lock-on haptic within 5°, and a
  polarization-roll readout for handheld antennas. Your location comes
  from GPS with grid-square fallback. Data cached for 6 hours
  with offline fallback. Enable in Settings → Experiments → Satellites,
  then find it under More. Well-documented birds (SO-50, RS-44, ISS, IO-117,
  QO-100, the Fox/FUNcube cubesats, AO-7, …) show a curated downlink
  polarization badge (linear/circular) on their info and hover cards —
  SatNOGS carries no polarization data and Faraday rotation makes the
  ground-arrival angle uncomputable, so this is static metadata; on a
  circular downlink the on-target hint says antenna twist won't matter
  instead of showing the twist-to-peak roll readout. The world map is now
  an azimuthal-equidistant "great circle" chart centered on your QTH —
  range rings, coastline outlines, bearing-true satellite positions,
  footprints, and ground tracks — replacing the MKMapView globe (MapKit
  silently refuses camera rotation at continental zoom). Pinch to zoom
  from the full Earth disk down to regional scale (extra 1,000/2,500 km
  range rings appear zoomed in; compass letters pin to the screen edge). It rotates with
  the device compass (heading-up) by default; a lock button snaps it back
  to north-up and keeps it there (persisted). A **Passes** button on the
  selected satellite's card lists its next passes over your QTH (48-hour
  SGP4 search): each pass shows the rise–set window with a live countdown
  (or "in progress"), duration, color-graded peak elevation, slant range at
  closest approach, and the compass azimuth path (rise → peak → set), with
  the satellite's polarization badge and transmitter frequencies in the
  header; geostationary birds that never set are called out instead of
  showing an empty list. A **Point** button enters antenna-mount mode:
  strap the phone to the antenna boom (back camera along the boresight)
  and the full screen becomes far-visible guidance in the sky dome's
  theme, borrowing Garmin G1000 instrument conventions — a heading-tape
  section of the compass with a fixed lubber line and an orange fly-to
  bug for azimuth, a glideslope-style vertical deviation scale (dots at
  ±10°/±20°, orange diamond) for elevation, and giant left/right and
  up/down corrections in degrees. A thick frame around the screen edge
  carries the semantic status color (red = far off, orange = within 20°,
  green = locked within 5° with a haptic, blue = below horizon). Once
  locked the screen shows the Doppler-corrected downlink/uplink
  frequencies to tune (from the propagated range rate), the mode chip,
  and the polarization hold (live roll for linear antennas, the curated
  hint for circular birds). Below the horizon it counts down to the next
  pass and the instruments steer toward the rise point so the antenna
  can be pre-aimed. The screen stays awake while pointing. An AR toggle
  in the header adds live camera passthrough behind the instruments with
  the satellite marker projected onto the actual sky (orange ring, green
  when locked) and a fixed boresight crosshair — the choice persists
  between sessions. A calendar button in the toolbar opens an all-sky
  **Upcoming Passes** schedule: every pass over your QTH in the next 6
  hours across all satellites with an active transmitter, sorted by rise
  time, each with a live countdown (or minutes left when in progress),
  duration, peak elevation, rise→set compass path, and the primary
  downlink frequency and mode; tap a pass to select that satellite on
  the map. Horizon-scrapers are hidden by default — a filter toggle
  shows only workable passes (peak ≥ 10°) and remembers your choice.
  A **mutual-pass planner** (two-person button in the toolbar) finds
  windows where a satellite is above the horizon at your QTH and a
  second station at the same time — the windows you can actually work
  each other. Your grid is prefilled; the other station takes a grid, a
  callsign (automatically resolved to the most recent grid in your
  log), or a friend picked from your friends list. Results list every
  mutual window in the next 24 hours with how long you're both in the
  footprint and the limiting peak elevation. Tapping a window opens a
  profile visualization: the Earth in true-proportion cross-section
  with both stations on the surface, the satellite's path colored by
  who can see it (green = both, orange = one), an animated satellite
  sweeping the pass with sight lines to each station, and its live
  coverage arc on the surface. Mode chips (FM/SSB/CW/Digi) filter the
  search to satellites whose active transmitters actually support the
  selected modes — the persisted filter re-runs the search live, each
  result shows the matching transmitter's mode and downlink, and when
  you pick a friend or callsign the chips re-order by how often you've
  worked that station in each mode. The other-station field
  autocompletes as you type: matching friends first in their own color,
  then callsigns from your log, as tappable chips. Callsigns without a grid in your
  log fall back to the shared callsign-lookup chain (Polo notes → QRZ →
  HamDB) automatically. In the profile view you're identified by your
  callsign rather than your grid, station labels un-overlap when the
  stations render close together, and high orbits (AO-10-style Molniya
  apogees) use a log-compressed altitude scale so the Earth stays
  readable instead of shrinking to a bump — LEO passes remain
  essentially true-proportion. Below the profile, a times table shows
  the window's key instants (both rise, best, both set) in Zulu and in
  each station's own local time — the other station's time zone is
  reverse-geocoded from their grid, with a longitude-based estimate
  offline. Satellites now carry an AMSAT community-status chip ("heard
  2h" green / "not heard" dim) on the info card and in the upcoming and
  mutual pass lists — the activities server aggregates
  amsat.org/status centrally (new `/v1/satellites/amsat-status`
  endpoint + polite 30-minute aggregator) so phones never hit AMSAT's
  volunteer-run service directly, and the app degrades silently until
  the server is deployed. The app now shows only workable satellites:
  famous derelicts that SatNOGS still lists as active (AO-10, AO-40,
  AO-85, AO-92, AO-95) are excluded everywhere, and any AMSAT-tracked
  bird with no community "Heard" report in the last 7 days is hidden
  too (the server aggregate now spans a 7-day report window so a quiet
  day doesn't hide a working linear bird). The workable-pass filter
  (peak ≥ 10°, one persisted toggle) now applies uniformly to every
  pass list — upcoming, per-satellite, and the mutual planner (where
  the limiting minimum peak is what's tested). Satellites are now
  shown by their OSCAR designator first ("SO-50") with the longer
  mission name ("SaudiSat 1C") de-emphasized beside it — on the map and
  sky-dome labels, the info card, search (which matches both names),
  pass lists, the mutual planner, and the pointing screen. The great-circle map's
  home point can now be moved by dragging: the map follows your finger
  live, but by continuously re-centering the azimuthal projection (true
  re-projection, not a screen translation), so when you let go the
  bearings and distances read true from wherever you've centered. A
  home button appears while off-QTH to snap the projection back — zoom
  is left where you set it. The tilt-up sky view gained the same AR
  camera mode as the pointing screen: toggle the video button and the
  satellite overlay draws over the live camera image, so satellites,
  pass arcs, and the hover crosshair sit on the actual sky.
- **Guided callsign change checklist**: changing your callsign (from About Me,
  a QRZ-detected change, or a new primary QRZ key) now opens a checklist of
  every connected service that still references your callsign — QRZ Logbook
  keys, QRZ Callsign Lookup login, LoTW certificate, eQSL account, Club Log,
  POTA profile, Ham2K LoFi, and HamAlert triggers. Steps the app can verify
  check off automatically; the rest link straight to the right settings screen
  or website. An unfinished checklist stays pinned at the top of Settings.
- **Change primary QRZ logbook account**: Settings → QRZ Logbook Sync now lets
  you swipe or long-press a connected account to set it as primary. Previously
  only the first-added API key could ever be primary. Removing the primary
  account now promotes the next one instead of leaving no primary (which
  silently stopped QRZ sync and broke the CW Sweep/widget shared credentials).

### Fixed
- **Satellite pointing mode now assumes the phone lies flat on the antenna
  boom**: the boresight is the device's top edge (+Y axis) instead of the
  back camera, matching how a phone is actually strapped to an Arrow/Elk
  boom — flat, screen up, top toward the tip. Previously guidance was 90°
  off unless you held the phone up to the sky. The satellite marker and
  crosshair are now a boom-boresight targeting display that's always on
  (no camera required) and centers the bird in the target when locked;
  the optional camera passthrough remains as background context. The
  tilt-up sky dome keeps its look-through-the-camera boresight.
- **Twisting the antenna no longer disturbs pointing mode**: rolling the
  boom-mounted phone for polarization peaking used to spin the targeting
  display and could rotate the whole UI to landscape mid-pass. The screen
  is pinned to portrait while pointing mode is up (restored on exit), and
  the marker projection uses a world-stabilized basis (screen up =
  sky-up) so only the roll readout responds to twist — azimuth/elevation
  guidance was already twist-invariant.
- **Boom-axis twist calibration in pointing mode**: a strapped phone is
  rarely perfectly parallel to the boom, so rolling the antenna swept the
  indicated elevation around a small cone. A new gyroscope button starts a
  ~2 s calibration — twist the antenna back and forth and the gyro's
  rotation axis (which IS the boom axis in the device frame) replaces the
  assumed +Y boresight for all guidance, lock detection, and the targeting
  display. The trim angle shows under the AZ/EL readout, the axis persists
  across launches, and incoherent or implausible (>30° off) gestures are
  rejected.
- **Satellite transmitters are filtered by AMSAT-reported activity per
  capability**: AMSAT status rows are kept per configuration (`AO-7_[A]`
  vs `AO-7_[B]`) instead of collapsed per satellite, each row's bracket
  tag is bucketed into the app's mode categories (FM / linear / CW /
  digital), and SatNOGS transmitters whose category AMSAT tracks but
  hasn't heard in 7 days are hidden everywhere — info card, pass sheets,
  and the pointing screen's Doppler tuning pick. Categories AMSAT doesn't
  track keep the benefit of the doubt, and if filtering would empty a
  workable bird's list the raw list is kept.
- **carrierwave.app /sweep and /android pages no longer 403**: the flat
  pages (`sweep.html`, `android.html`) collide with the same-named download
  directories, so nginx's `try_files $uri/` redirected to the directory,
  which has no index and autoindex off. Exact-match locations now serve the
  pages at the bare paths while DMG/APK downloads keep working underneath.
- **activities-server no longer OOM-killed every ~4 hours**: raised the
  systemd `MemoryMax` from 512M to 1G for prod and staging (the working set
  had grown to ~505MB, right at the old cgroup cap), and raised the ntfy
  health-check memory alert threshold from 500MB to 800MB to stop the
  alert/recover flapping while still warning before the new cap.

### Security
- **Closed 5 critical unauthenticated auth-bypass holes in activities-server**
  (deepsec audit, CAR-301–305). `POST /v1/register` and `POST
  /v1/challenges/:id/join` no longer disclose or rotate an existing callsign's
  device token to unauthenticated callers (which allowed full account takeover
  and a token-invalidation lockout), and `POST /v1/account/claim-previous` now
  requires verified ownership of the previous callsign before merging/deleting
  an account. Token recovery for existing callsigns goes through the magic-link
  flow; new-user onboarding is unchanged. iOS handles the withheld token.
- **Hardened 13 high-severity server issues** (deepsec, CAR-306–317): E2E sync
  snapshot `seq` is bounds-checked before the destructive GC; `change_callsign`
  can no longer re-key an OAuth identity from a legacy device token; `?callsigns=`
  club lookups are restricted to owned callsigns; the friend-invite page escapes
  its inputs (reflected + stored XSS); invite-only challenge gates enforce the
  token, expiry, and max-uses; `websdr_status` no longer follows redirects
  (SSRF); `POST /v1/sota/zones` requires authentication; and the admin web token
  moved out of localStorage.

### Fixed
- **Server correctness/data-loss bugs** (deepsec HIGH_BUG, CAR-323–340): all
  aggregator HTTP clients now have request timeouts (a stalled upstream no longer
  wedges a poll loop); achievement count/streak queries and the propagation cache
  write no longer silently fail on type mismatches; POTA spot `expire` is clamped
  (no aggregator panic); `leave_challenge`, friend re-requests, the sync push
  race, park-boundary no-match, POTA catalog re-sync cadence, SOTA pending-zone
  leases, and register callsign normalization are all corrected.
- **SOTA integration temporarily disabled everywhere.** The SOTAwatch v2 API
  shuts down 2026-08-31 and its replacement (api-db2) requires prior approval
  under its terms of service before any client may connect. Until the
  migration lands: the shared Rust spot engine no longer fetches SOTA spots
  (both apps), SOTA self-spots and respots throw a clear "temporarily
  disabled" error (iOS toast surfaces it), the iOS widget skips its SOTA
  fetch, the server's SOTA aggregator is off (prod + staging, applied via
  Ansible), and SMS SOTA spots reply with a friendly disabled message. SOTA
  summit reference data (sotadata.org.uk CSV) and SOTA session logging are
  unaffected. Each kill-switch is a single flag/const marked with the same
  comment for easy re-enabling.

### Fixed
- **Server crash-looped hourly on snapshot save (OOM).** The snapshot job
  loaded all six aggregate tables into memory at once (park boundaries alone
  serialize to 268 MB), blowing past the service's 512 MB systemd memory limit
  every hour — no snapshot had succeeded since March. Snapshots now stream
  rows Postgres → disk (and back on restore) one at a time in a JSONL format,
  keeping memory flat regardless of table size. Legacy whole-array `.json`
  snapshot files are cleaned up after the first successful save.
- **POTA stats aggregator now rate-limits and retries.** Requests to
  api.pota.app go through a global pacer (min 500 ms between requests, tunable
  via `POTA_STATS_MIN_REQUEST_INTERVAL_MS`) and transient failures (5xx/429/
  network) retry up to 3 times with exponential backoff, instead of hammering
  the API with back-to-back bursts that were drawing sustained 502s.
- **SOTA spots failed to load with a JSON parse error (both apps).** SOTAwatch
  now injects a synthetic "DEPRECATED" entry with null fields at the head of
  every spots response, which failed the whole-array decode and surfaced as
  "SOTA: JSON parse error: invalid type: null, expected i64" on the Hunter
  page. The shared Rust decoder now treats nullable fields as optional,
  decodes each spot independently so one malformed entry can't take down the
  feed, and filters out the deprecation notice.
- **Session merge didn't regenerate the QSO map (iOS).** Merging two sessions
  now posts the same change signal ADIF imports use, so an open session detail
  view reloads its QSOs, the map preview re-frames around the combined
  contacts, and the full-screen activation map regroups from the live QSO set
  instead of the snapshot taken when the view was opened.
- **Stale callsign notes on long-resident app sessions (iOS).** Callsign notes
  (PoLo sources), server membership enrichment, and the QRQ Crew member list
  only re-downloaded at cold launch, so an app that stayed resident for days
  kept serving old notes (e.g. a member's callsign change never appeared). All
  three caches now also re-check staleness on every app foreground, and the
  QRQ Crew member cache gained a 24-hour TTL instead of caching for the life
  of the process.

## [1.99.0] - 2026-08-27

### Added
- **Third-party OAuth 2.0 / OpenID Connect API (server).** Other people's
  applications can now read, update, and add QSOs in a user's log with that
  user's consent. The activities server acts as an authorization server:
  authorization-code flow with mandatory RFC 7636 PKCE (`S256` only), the
  RFC 8628 device grant for CLIs and headless clients, rotating client-bound
  refresh tokens, RFC 7009 revocation, OIDC discovery + `id_token` + UserInfo,
  and a consent screen the user signs in to on carrierwave.app. Client
  registration is curated via `/v1/admin/oauth/clients` — there is no self-serve
  portal and no dynamic registration, because the client name on the consent
  screen is what the user actually trusts. Users manage connected applications
  through `/v1/oauth/grants`.

  The log stays end-to-end encrypted throughout: a token authorizes *access* to
  the opaque journal, never *decryption*. Third-party clients must ask the user
  for their sync passphrase and derive the data key locally. Protocol spec and
  the accepted risks of that choice are in
  [`server/docs/features/oauth-api.md`](server/docs/features/oauth-api.md), with
  a runnable reference client in `server/examples/oauth-log-client/`.

### Security
- **Default-deny authorization for third-party tokens (server).** Access tokens
  minted for a registered OAuth client carry a `cid` claim and are refused on
  every route not explicitly listed in `src/auth/scope_map.rs`. Third parties
  currently reach only the sync journal (`sync:read` / `sync:write`) and
  OIDC UserInfo (`openid`); clubs, friends, spots, events, contests, and account
  management remain first-party-only. First-party tokens are unaffected. A test
  fails the build if a route is added to `main.rs` without being classified, so
  new endpoints cannot silently become third-party-reachable.
- **Refresh-endpoint escalation guard (server).** A third-party refresh token
  presented to the first-party `/v1/auth/token/refresh` is rejected. Accepting
  one would have minted a token without `cid`, bypassing the scope gate
  entirely. The check runs before rotation, so the rejected attempt does not
  consume the caller's token.

### Fixed
- **Server — a callsign change no longer resurrects the old callsign.**
  `PUT /v1/account/callsign` missed the OAuth identity tables: every token
  re-mint kept stamping the old call into JWTs, and the auth middleware then
  recreated a participants row under it, so the old identity reappeared
  indefinitely. The change now re-points `accounts.primary_callsign` and the
  verified `account_callsigns` claim in the same transaction, bumps
  `tokens_valid_after` so outstanding old-call access tokens die immediately
  (devices recover silently via refresh), and the middleware resolves the
  acting callsign from the account instead of trusting the token's `cs`
  claim. The change also now covers `user_achievements`, `spot_markers`
  (SMS self-spots), and macro authorship, and touches `clubs.updated_at` so
  the `/v1/clubs` ETag moves — clients previously got `304 Not Modified`
  forever and kept showing the old call in club rosters.
- **iOS — callsign lookups could show another operator's old identity
  forever.** The disk-backed operator-profile cache had no TTL: a
  QRZ-enriched row was served on every lookup with no age check, and when
  QRZ forward-resolved an old call to the operator's new one, the fresh data
  was recorded under the new call while the old-call row lived on untouched.
  Rows older than 7 days no longer short-circuit a live lookup (they remain
  an offline fallback), an old call that QRZ resolves forward now has its
  cached row dropped, and the Settings cache rebuild refreshes stale QRZ
  rows instead of preserving them unconditionally.
- **Spot engine — the 30-day enrichment TTL now applies while running.** The
  callsign enrichment cache (operator name/grid next to spots) only enforced
  its TTL when loading from disk; a long-running session served expired
  entries indefinitely. Expired entries are now re-fetched and overwritten
  by the normal enrichment batches.

## [1.98.0] - 2026-08-03

### Added
- **Park n-fer support in hunting mode (iOS + Android).** The Hunter Log now
  handles POTA n-fers — a single QSO crediting two or more parks at once. The
  quick-entry parser accepts multiple space-separated park references
  (`W1AW 20m CW US-1044 US-3791`), storing them all on the contact. Worked-today
  dedup is now per-park: logging a 2-fer crosses out *every* credited park's spot
  row, while working just one park of an n-fer leaves the still-needed park
  available (fixes the prior behavior where a multi-park contact crossed out no
  rows). Shared in the Rust core (`quick_entry`, `hunter_log::band_mode_park_keys`,
  per-park overlap in the logger duplicate classifier).
- **CW Bridge hardware: ESP32-S3-WROOM-1U module rework.** Replaced the Seeed
  XIAO ESP32-S3 board-on-board (U4) with a surface-mount ESP32-S3-WROOM-1U-N16R8
  module (LCSC C3013946) plus supporting hardware. Because the module is a bare
  SoC module (no onboard regulator), the board now generates its own +3V3 rail
  from an AP63200WU-7 synchronous buck (U11, C2071868) off the +5V mux rail —
  the XIAO previously sourced +3V3. Added EN reset (R24/C53/SW4), IO0 boot strap
  (R25/SW5, TS-1187A buttons), and module decoupling. All GPIO→net assignments
  preserved (WROOM-1U pinout matches the XIAO's logical map, no net renames).
  The 1U variant carries an on-module U.FL connector, so the carrier board needs
  no antenna keepout and the module drops into the old XIAO pocket. Schematic
  ERC-clean and BOM/CPL regenerated; PCB placement complete (0 real DRC errors),
  ESP-subsystem routing still to be finished.

### Added
- **Shared map card engine (map port Phase B).** The seven embedded map
  surfaces — session logger map, session detail card, timeline replay, QSO
  detail arc, callsign map section, spots mini-map, and club map — now run on
  the shared Rust core (`MapApi.session_map`/`session_timeline`/
  `qso_detail_map`, timeline decay/SNR curves, and a batch `QrzApi.locate`
  callsign-location lookup with a 30-day on-device cache). Timeline replay
  and the spots mini-map render identically on iOS and Android from the same
  curve math.
- **Android: full-parity Map tab** — grid clusters with callout details,
  geodesic arc overlays, worked/confirmed grid overlay, filter sheet
  (band/mode/park/date/confirmed), and session statistics.

### Changed
- **Propagation check + POTA ADIF export on the shared Rust core (map port
  Phase D).** The "How's my antenna?" propagation check's session engine —
  RBN / PSK Reporter polling, dedup, windowing, and skimmer-grid enrichment —
  now runs entirely in the shared Rust `PropagationApi`; the iOS session is a
  thin observable wrapper that drives `poll()` and mirrors the results (the
  `PropagationCheckSession+Polling` and HamDB-based `PropagationCheckEnrichment`
  Swift paths were deleted, and grid enrichment moved onto the callbook cache /
  QRZ locate flow). The POTA activation ADIF export sheet and the bulk export
  sheet's Combined mode now write through the shared Rust `AdifApi`
  (`exportActivation` / `exportBulk`); Split-by-Park and the session/multi-op
  exports remain on the Swift writer.
- **Merged park boundaries (server).** Multi-unit parks are now unioned into
  a single boundary at ingest on the activities server, so every client —
  including Android, which never had the merge — renders seamless park
  outlines. (activities-server 0.4.90)
- **Parks & Summits map overlays on the shared Rust core (map port Phase C).**
  Every reference-map overlay — park boundaries, historic trails, US
  states/counties, SOTA activation zones, and the WWFF POTA-boundary borrow —
  now fetches, caches, and evicts through `ParkMapApi`, and the rosette
  multiplier finder runs the geometric scan in Rust. The client-side CGPath ring
  merging, per-layer file caches, and the point-in-polygon/multiplier geometry
  were deleted (park boundaries are pre-merged server-side; the client only
  decodes GeoJSON and precomputes render-time skirts). Boundary tap hit-testing
  uses the shared `pointInRing` FFI.
- **Club map opens instantly (grid-first).** Member pins paint immediately
  from their last-known grid squares, then refine in the background to
  precise QRZ/HamDB coordinates (members without a grid on file gain pins as
  the lookup completes). Replaces the hand-rolled QRZ XML client, HamDB
  fallback chain, and 30-day JSON cache (~630 lines of Swift deleted) with
  the shared Rust lookup and an encrypted on-device cache.
- **Timeline replay no longer shows weather/solar/note metadata entries** —
  the old data actor leaked metadata pseudo-modes into the event stream; the
  shared core applies the standard map visibility rule.
- **Callsign prefix hot keys (CAR-290).** A new Prefixes row above the logger
  keyboard stamps a callsign prefix into the entry field with one tap; tapping
  another key swaps the prefix and keeps the suffix. Suggested mode is strictly
  position-local — shared Rust ranks the prefixes most worked near the
  operator's current grid (widening once, with a country-level fallback for a
  cold start); Custom mode is the user's own ordered list. Ships on iOS and
  Android.
- **Keyboard Rows settings hub.** The Logger settings' separate Keyboard Row
  and Command Row pages are consolidated into one Keyboard Rows screen: every
  accessory row (Numbers & Symbols, Prefixes, CW Keyer, Commands) has an
  inline enable switch, drag-to-reorder controls the stacking order above the
  keyboard, and a live preview of the stack is pinned at the bottom of every
  page in the flow. The CW keyer row's auto-appear conditions are documented
  in Settings for the first time. Android gains the same screen (minus the
  keyer row) from the More tab.
- **CW Bridge PCB — USB-C flash port (rev 1).** J9's USB-C data pins are now
  wired to the ESP32-S3's native USB through a new DPDT RUN/FLASH slide switch
  (SW3, C&K JS202011): RUN routes the data lines to the J1 radio host port
  (J9 stays charge-only, so any charger is safe), FLASH routes them to J9 so a
  PC can reach the ROM bootloader over USB-C at the board edge. Both USB-C pad
  pairs (A6/A7 + B6/B7) are fanned out, so the cable works in either flip.
  Schematic + routed PCB at DRC baseline; BOM/CPL/gerbers regenerated.
- **Android — QSO and session editing, matching iOS.** Tapping a QSO now opens
  the shared edit sheet everywhere iOS allows it: the live session logger, the
  Logbook tab, the Hunter log, and the new session detail. The editor gained
  the full iOS field set (time, my-station, activity references, contest
  exchange) with collapsible sections, band auto-derivation from frequency,
  and delete-with-confirmation.
- **Android — session detail with post-session editing.** The Sessions tab's
  idle screen now lists recent completed sessions alongside paused ones;
  tapping any opens a session detail with the QSO list (tap to edit/delete),
  Edit Info (title, callsign, park, equipment, operators, attendees, QSO
  comment, notes — callsign/park changes cascade to the session's QSOs after
  confirmation, as on iOS), Reopen Session, and Delete Session.
- **Split ADIF export from the session list.** The long-press menu on a
  session row now offers Split Export (by UTC day, park, and operator), the
  same sheet previously reachable only from the session detail view.
- **Pebble watchface: date, temperature, UTC day offset.** The Carrier Wave
  Face now shows the date with the current temperature (Open-Meteo, phone
  geolocation) under the local time, and a **+1** marker next to the Zulu time
  whenever the UTC date is ahead of local — so evening QSOs get logged on the
  right day.

### Changed
- **QSO map view-model (filtering, grid clustering, geodesic arcs, camera
  bounds, statistics)** moved to shared Rust (`MapApi`); iOS SwiftData map
  pipeline removed — the map now reads exclusively from the local store.
- **Android — tapping a hunter spot now opens a log sheet, matching iOS.**
  Instead of silently seeding the command bar, a tap on a spot in the Hunter
  tab opens a pre-filled sheet (callsign, frequency, mode, park/summit ref)
  with RST fields defaulting by mode, a More Fields disclosure (grid, state,
  notes), and a Log QSO button — with a "Duplicate QSO" confirmation first
  when the station was already worked today, and the explicit-confirm POTA
  respot offer after logging.
- **Session row long-press menu grouped into sections.** Session actions
  (reopen, merge, edit metadata), ADIF (export, split, import), and view/share
  (map, brag sheet) are now separated by dividers instead of one flat list.
- **Pebble watchface: date and temperature flank the time.** The date (now two
  stacked lines) sits left of the big local time and the temperature sits right
  of it, replacing the small combined line underneath; the UTC row moves up
  into the freed space.
- **Pebble watchface: Routed Gothic lettering.** Local time (40px), UTC (26px),
  date (20px), and temperature (26px) now render in the Routed Gothic drafting
  font (SIL OFL 1.1, subset per size via `characterRegex`) instead of the LECO
  system fonts; the small condition rows stay in system Gothic.
- **Pebble watchface: connection and staleness awareness.** Solar data older
  than 90 minutes draws dimmed instead of silently lying, and losing the phone
  link shows a red marker in the corner with a double vibe.

### Fixed
- **Android — the "+" start-session button hijacked the Hunter tab.** The
  global floating "+" (start activation) rendered on every tab and sat right
  above the Hunter tab's command-bar send button, so "add this hunt" opened
  the session wizard instead of logging the contact. It now appears only on
  the Home and Sessions tabs; the Hunter Log stays a no-session flow, as on
  iOS.
- **iOS — changing a session's park reference silently did nothing.** The Edit
  Info sheet confirmed the change ("updates all QSOs and clears POTA upload
  status") but never applied it. The new park now saves to the session and,
  for non-rove activations, cascades to every session QSO with POTA upload
  status reset so the activation re-uploads under the new park.
- **Android — deleting a Hunter-log QSO never reached other devices.** The
  delete used the store's local-only hard delete, which the sync journal
  doesn't propagate; it now soft-hides the QSO (`isHidden` + dirty), matching
  the iOS delete path everywhere.
- **Android — QSOs deleted on iOS still appeared in the Logbook and Home
  heatmap.** The unfiltered snapshot included soft-deleted (hidden) rows; they
  are now filtered out.
- **Pebble watchface: missing HamQSL fields rendered as valid data.** A missing
  tag in the solar XML was sent to the watch as an empty string, which drew as
  a K-of-0 (green) reading; it now falls back to the `--` no-data sentinel.

## [1.97.0] - 2026-07-16

### Added
- **POTA bulk ADIF export can split by park.** The bulk export sheet (multiple
  selected activations) now offers a **Combined / Split by Park** mode. Split by
  Park writes one ADIF per park activated with that park as the only park in the
  file — n-fer QSOs fan out into each of their parks and the same park across
  different days/activations is merged into a single file — then shares them all
  at once. Combined remains the default single-file export.
- **Magic-link sign-in opens the app directly (iOS + Android).** Tapping the
  emailed verification link now hands off to the app via App Links / Universal
  Links (and a `carrierwave://auth` custom scheme) instead of finishing in the
  browser: the app marks the link clicked and completes sign-in itself, so you
  no longer have to switch back and wait. Shared in Rust
  (`AuthApi.completeFromLink`) — it reuses the existing poll for issued/attached
  handling and needs no server change; a browser tap on another device still
  works via the existing poll. Requires the `assetlinks.json` /
  apple-app-site-association association files served from the activities host
  (added to the Ansible role).
- **Android — the activation logger.** Starting a session now opens a live
  QSO-entry logger (new **Sessions** tab) instead of dropping back to the
  logbook: a session header, a callsign/RST/grid/notes form with mode-default
  RST, SCP suggestions, day-scoped dupe detection, a running QSO list, and
  pause/end — all driven by the shared Rust `SessionApi`. The tab shows a start
  prompt when idle and the logger while a session is active, mirroring the iOS
  Sessions tab.
- **Android: Brag Sheet.** Customizable achievement stats across
  weekly/monthly/all-time periods, backed by the shared Rust engine.
- **Android — the session start wizard reached visual parity with iOS.**
  Icon-led section headers, an operator hero (callsign + grid), a segmented
  mode picker, program chips with icons (POTA selected by default), an
  inventory-backed gear loadout selector with a collapsed summary, a
  collapsed "More Options" disclosure, and a pinned Start button carrying the
  disabled reason. Frequency and park now auto-populate on open, and park
  references show name/location plus your own activation/hunter stats.
- **Android — the interactive frequency scope.** A scroll-to-tune ruler with
  a band/step strip, live spot rows, a Set field, and Find-clear, matching
  the iOS selector.

### Changed
- **The logger command grammar AND handling moved to the shared Rust core.** The
  parser (`FREQ`/`MODE`/`SPOT`/`RBN`/`HUNT`/… with all their aliases) and the
  command-row catalog live in `cw_domain::logger_command`; the *handler*
  (`LoggerCommandApi.handle`/`handleText`) executes the shareable effect — session
  mutations (frequency/mode/grid/callsign/note/session-metadata are applied to
  cw-store) and the one-off HUNT log — and returns a typed outcome (a completed
  `SessionUpdated`, or a `PostSpot`/`Present`/`Message` intent) that both apps map
  to their native side effects (radio tuning, panels, Live Activity — which can't
  live in Rust). iOS `LoggerCommand.parse` delegates to Rust and its `executeCommand`
  routes through the handler (native path kept as the `.off` fallback); Android's new
  logger runs commands through the same handler, so `FREQ`/`MODE`/`NOTE`/etc. now
  execute there for the first time. The Swift command *parser* (`LoggerCommand+Parsing`)
  was stripped to a thin mapping.
- **The activation logger is now all-in on the shared Rust core (iOS).**
  `SessionApi.currentSession()` is canonical for "which session is active" (new
  `fetch_current_session` in cw-store); `logger_form_config` shares the RST-by-mode
  defaults, band, and POTA/contest field visibility; `log_qso` fills blank RST from
  the mode default; and `default_rst(mode)` is exported so the form default matches
  the logged value. iOS QSO logging, active-session restore, and the RST default now
  run **only** through Rust — the Swift QSO-assembly fallback, the SwiftData/UserDefaults
  restoration fallback, and the `.off` gate on the session path were removed. If the
  cw-store seam is unavailable (the `.off` kill switch / experiment disabled) or a Rust
  write fails, the logger surfaces an error instead of silently writing a divergent
  SwiftData-only record. Android's new logger consumes the same API.
- **Activation duplicate detection moved to the shared Rust core.** New
  `FieldStore.activation_duplicate_status` mirrors the hunter `duplicate_status`
  and shares its classifier, but scopes the POTA park match to the operator's own
  activation park (`qso.park`) rather than the contacted station's park — the
  activator's side of the same day-scoped band/mode/park dedup. iOS deletes its
  Swift `filterMatchingQSOs`/`classifyDuplicateStatus` and both platform loggers
  now classify dupes through Rust.
- **Brag Sheet statistics computation and configuration now run in shared
  Rust** (`BragSheetApi`), consumed by iOS and Android; brag config is stored
  in the shared `synced_config` store, and iOS migrates automatically from the
  previous UserDefaults storage. Distance stats honor the mi/km unit preference
  identically on both platforms. Cross-device config sync groundwork is in
  place but **push is gated off** (`CONFIG_SYNC_PUSH_ENABLED = false`) pending a
  release whose forward-compatible sync decoder is the floor version across all
  devices; the pull path now tolerantly skips unknown sync ops.
- **Frequency-scope logic moved to the shared Rust core**
  (`cw_domain::frequency_scope`, exposed via `cw-ffi`). Both iOS and Android
  now call the same implementation for ruler-row building and band-plan
  verdicts — no duplicated logic. Fixed a latent Swift bug where a literal
  `"SSB"` mode was mis-classified as CW.

### Fixed
- **A mistyped callsign can no longer stick to a session.** Starting a session
  now takes your callsign from your profile (About Me) rather than a cached
  copy, so a callsign you've since corrected can't be frozen into that
  session's logged QSOs or its ADIF exports. Addresses a TestFlight report of a
  "fat-fingered" callsign appearing even though the profile was correct.
  (CAR-287)
- **Background sync no longer crashes the app on suspension (`0xdead10cc`).**
  When auto-sync ran as the app was being backgrounded, a large sync could
  outlast the ~30 s background grant and get suspended while a batched cw-store
  commit still held the SQLite file lock — a `RUNNINGBOARD 0xdead10cc` kill
  (TestFlight crash 3428, a recurrence of 3160). The background-task assertion's
  expiration handler now cancels the in-flight sync, so the batched-commit loops
  stop at a safe point *between* commits instead of mid-write. Sync state is
  durable, so the next foreground sync resumes cleanly.
- **CW Bridge PCB — debug-UART header no longer blocks the XIAO's USB-C
  port.** J11 sat flush against the XIAO module's top edge, directly in the
  programming port's plug corridor, so a cable couldn't be inserted. Moved it
  right of the corridor (between D7 and TP4) and re-routed `DEBUG_TX` on
  B.Cu. DRC baseline unchanged (0 unconnected, only the 4 pre-existing J9
  footprint-internal hole clearances); JLC CPL regenerated.
- **Magic-link sign-in no longer fails with a spurious "network error"
  (iOS + Android).** Leaving the app to open the emailed link briefly tears
  down the connection (Android freezes the process/socket on backgrounding),
  and the shared Rust poll loop aborted the whole sign-in on that first
  transient failure — surfacing `error sending request for url …/verify/poll`
  even though the link had just been verified. The poll (`AuthApi`) now
  tolerates transient transport and 5xx failures, retrying until its deadline;
  only genuine client-side (4xx) errors abort immediately.
- **Android — cancelling a magic-link sign-in actually stops it.** The Account
  screen's Cancel now cancels the in-flight poll coroutine (not just the pending
  verification), so it can no longer keep polling in the background or flip the
  UI after you back out.

## [1.96.0] - 2026-07-09

### Changed
- **iOS — the session start wizard was rebuilt around a clear journey.**
  Identity is one block — callsign hero with a plain-text gear line under
  it ("Van POTA · FT-891 · ATAS") whose menu switches, edits, and manages
  loadouts, replacing the full-screen loadout cards. Then the essentials —
  Programs and Radio (mode, frequency, and power in one section with
  frequency and power side by side) with prominent headers — then a single
  collapsed "More Options" row hiding the optional tail (station, people,
  contest add-on, WebSDR, pack checklist, notes, save-as-defaults).
  Advisory cards and instructional footers shrank to one-line hints or were
  dropped so required fields are the loudest thing on screen, and Start
  moved from the toolbar to a pinned bottom button with the disabled reason
  directly above it. Casual and contest wizards follow the same pattern.

### Added
- **iOS — the session start wizard auto-picks a free starting frequency.**
  When the frequency field is empty, it selects your most-activated band —
  constrained to the bands the chosen radio can actually work — then finds an
  open frequency on that band, nestled among live POTA, SOTA, and RBN spots
  with enough clearance to avoid interference (falling back to the mode's
  calling frequency when the band is quiet). A one-line note under the field
  explains why the band was picked and how clear the frequency is, and a
  "Change" button clears it for manual entry or the band suggestions list.
  The pick re-runs when the radio or mode changes but never overrides a
  frequency you typed or a band pill you tapped. The shared spot-nestling
  logic was extracted into `FreeFrequencyPlanner`, and the wizard's band
  suggestions list now folds in SOTA spots alongside POTA and RBN.
- **iOS — the activation wizard prepopulates the park field.** When POTA is
  selected and the field is empty, it fills with the best nearby candidate:
  the park you've activated most often within 16 km (from session history),
  falling back to the closest. The suggestion updates itself when the GPS
  fix lands but never overwrites a park you typed, a saved default, or a
  map/template pre-fill.
- **iOS + Android — set session fields from the quick entry bar.** A
  callsign-less line like `14.046 CW CN87` now updates the active session's
  frequency, mode, and operator grid in one go (shared Rust grammar,
  `parse_quick_entry_session_metadata`). The live command hint and the
  confirmation toast both say the values apply to QSOs logged from now on,
  and tokens a session can't take (parks, states, RSTs, times) are called
  out as ignored instead of silently dropped. On the hunter log (iOS Quick
  Log, Android command bar) frequency and mode become defaults for future
  entries; grid is reported as not settable there.

## [1.95.0] - 2026-07-08

### Added
- **iOS + Android — pull-to-refresh on the hunter spot list.** The Hunter
  Log (iOS) and Spots feed (Android) can now be refreshed on demand by
  pulling the list down, triggering one immediate spot-engine poll instead
  of waiting out the 2-minute timer. A "last refreshed" pill next to the
  list header shows how long ago the engine last polled ("2 min ago"),
  ticking live between refreshes. Requested by Discord users hunting on
  short breaks.
- **Android — POTA respot from the Spots feed (CAR-288).** POTA spots with a
  park reference get a respot button that posts a fresh spot to POTA through
  the shared Rust core (`SpotEngineApi.pota_respot`, unauthenticated
  `POST /spot` like pota.app tooling), keeping an activator you can still
  hear from aging out of the feed. Always confirms first — the dialog shows
  exactly what will be published (activator, park, frequency, mode, your
  callsign) and folds in the 5-minute anti-spam cooldown warning shared with
  iOS.

### Fixed
- **iOS/macOS — stale "fat-fingered" callsign no longer resurrects from the
  Keychain (CAR-287).** The callsign previously lived in three competing
  stores (iCloud-synced Keychain, UserDefaults, UserProfile) with a
  launch-time loop that let a typo'd Keychain value overwrite the corrected
  one on every activation — invisibly, since no screen showed the Keychain
  value directly. `UserProfile.callsign` is now the single canonical store:
  Keychain and UserDefaults are derived caches only ever written from it and
  are reconciled (healed) on every scene activation, the Callsign Aliases
  editor writes through the profile, and the UserDefaults key no longer
  syncs via iCloud KVS. CW Sweep's Settings field — which persisted
  half-typed callsigns into the synced Keychain on a 500 ms per-keystroke
  debounce, the likely source of the bad value — now commits only on
  submit or focus loss, normalized to uppercase.

### Changed
- **Spot engine — spots now publish in fetch time (~1 s), not enrichment
  time (~15 s).** Each poll cycle used to hold every fetched spot hostage
  behind a HamDB enrichment batch of up to 20 sequential lookups (~0.75 s
  each) before notifying the UI. The engine now publishes the merged pool
  immediately after the source fetches land and publishes a second time
  once enrichment completes; the HamDB batch itself runs 8 lookups
  concurrently, and the per-callsign enrichment cache persists to disk
  (30-day TTL) so relaunches stop re-paying lookups for known callsigns.
  Applies to both apps and to pull-to-refresh latency.
- **iOS — hunter-log Spot action now always confirms (CAR-288).** The
  long-press "Spot" respot no longer fires on a single tap: an explicit
  "Spot on POTA?" alert previews the exact post (activator, park, frequency,
  mode, spotter callsign) before publishing, with the previous
  recently-spotted cooldown warning folded into the same confirm. Respots
  (hunter-log and post-QSO) no longer require a POTA sign-in — they post
  unauthenticated like the Android/shared-Rust path; activator self-spots
  still authenticate.
- **iOS — External Data caches now run on the shared Rust core.** The six
  Swift download pipelines (POTA parks, SOTA summits, WWFF directory, FCC
  callsigns, equipment catalog, SOTA activation zones) were swapped onto
  `ReferenceDataApi`: download, parse, TTL/ETag bookkeeping, and storage
  live in cw-store; the Swift services keep only their in-memory query
  surfaces (search indexes, nearby lookups) hydrated via paged FFI reads.
  Existing FCC downloads are reused (SHA seed from the old sidecar — no
  re-download); the POTA cw-store write-through and the shared CSV/disk
  pipeline (`ReferenceCacheDiskIO`, `CSVLineParser`) were deleted.
  Behavior notes: FCC schema-too-new now surfaces as a visible error, SOTA
  zone refreshes only request uncached summits, and the zones section
  shows a spinner instead of per-chunk progress. The map's viewport zone
  fetcher still uses its own Swift POST (follow-up), as does macOS CW
  Sweep's separate parks cache.

### Added
- **Android — External Data downloads, shared in Rust.** The Account
  screen gains an External Data card mirroring iOS: FCC callsigns, Super
  Check Partial, equipment catalog, POTA parks, SOTA summits, SOTA
  activation zones, WWFF directory, and contest definitions, each with
  count/age/refresh plus Download All. Download, parse, and storage for
  the six previously-Swift-only datasets moved into the shared core as
  `ReferenceDataApi` (cw-domain CSV parsers, cw-store schema v10 tables
  `sota_summit`/`wwff_reference`/`sota_zone`, cw-net clients incl. the
  FCC gzip-SQLite bundle with SHA-256 short-circuit and the chunked
  SOTA-zones POST), with iOS's TTLs and ETag behavior preserved. iOS
  still runs its Swift caches — swapping it onto `ReferenceDataApi` is a
  follow-up. Android consumers of the new data (pickers, FCC overlays,
  zone map layers) are also follow-ups; this ships download + cache +
  status. Deviations documented in code: SOTA expiry compare is
  chronological (iOS compares "dd/MM/yyyy" strings), and zone refreshes
  skip already-resolved summits instead of re-requesting all ~180k.
- **Android — SDR Tune-In from the Hunter Log.** Each spot in the hunter
  log's live feed gains a headphones button that listens to the activator
  on a public KiwiSDR: the iOS strategy picker (best signal / near the
  activator / near my location), receiver selection, protocol handshake,
  and PCM decode all run in the shared Rust `SdrApi`; Android adds an
  `AudioTrack` playback path and a mini player bar (live indicator,
  callsign/frequency/receiver, mute, stop) above the command bar.
  Deliberate v1 subset vs iOS: no cellular-data warning, CW
  transcription, recording, QSY/receiver-quality monitors, or
  auto-reconnect (a dropped receiver surfaces as a dismissible error).
- **CW Bridge PCB — debug status LEDs, UART header, and test points.** Five
  0603 status LEDs (all JLC-stocked): PWR (green, +3V3), USB (blue, USB_5V
  present), BOOST (red, boost converter output alive), and ST1/ST2
  firmware-driven LEDs on PCAL6416A P0_6/P0_7 (active-low). J11 2-pin
  header exposes GPIO41 — the only spare native GPIO — as a debug UART TX
  (the board otherwise has no serial console: UART0's default pins carry
  I2S_MCLK/EXP_RST and USB-Serial-JTAG runs the USB host port). Thirteen
  copper-only test points cover the power rails (VBAT, USB_5V, BOOST_5V,
  +5V, +3V3), I²C (SDA/SCL/EXP_INT), and the full I²S link. Board remains
  routed, DRC-clean, 0 unconnected; BOM/CPL regenerated (test points
  excluded via new `in_bom no` handling in `jlcpcb_export.py`). Firmware
  follow-up owed: drive ST1/ST2 via the expander and route a console UART
  TX to GPIO41.
- **Carrier Wave Sync now requires an account (verified email).** The
  server's `/v1/sync/*` routes reject legacy `fd_` device tokens with
  403 `ACCOUNT_REQUIRED`; sync tenants are always email-verified OAuth
  accounts, so a synced log is always recoverable by its owner. iOS sync
  no longer falls back to the legacy device token (new
  `ActivitiesClient.syncAuthToken()`), and the Carrier Wave Sync settings
  screen shows a sign-in step (magic-link email verification) until an
  account session exists. Android and the web logbook viewer were already
  account-only; the web viewer now explains an `ACCOUNT_REQUIRED` failure
  instead of showing a bare status code. New admin endpoints
  `GET /v1/admin/sync/orphans` and
  `POST /v1/admin/sync/orphans/:participant_id/adopt` let a superuser
  inspect pre-cutover participant-tenant sync data and re-key it onto the
  callsign's account (refused with 409 if the account already has sync
  data).
- **Android — Awards & Streaks dashboard card.** Home gains a card backed
  by the shared Rust store aggregates (the same SQL behind the iOS
  dashboard's Rust overlay): current/longest on-air day streak
  (`brag_streaks`), WAS states out of 50 (`was_summary`), and DXCC
  entities worked (`dxcc_worked`).
- **Android — session end now splits multi-day POTA activations.** Ending
  a POTA session runs the shared Rust UTC-midnight split (one completed
  session per UTC day, QSOs/recordings/rove stops reassigned) — the same
  `splitPOTAAtUTCMidnight` behavior iOS runs. Paused sessions also gain a
  Delete action (confirmation dialog; hides the session's QSOs).
- **Android — dupe detection + SCP suggestions in every command bar.** The
  Logger and Session (activation) quick-entry bars now show the same
  day-scoped duplicate badge the Hunter tab already had (worked today /
  new band / new mode / dupe, via the shared Rust `duplicate_status`
  classifier), and all three bars suggest callsigns from MASTER.SCP as
  you type a partial call (Super Check Partial, tap to fill). New Rust
  `ScpApi` downloads MASTER.SCP (ETag-conditional, 7-day window) and
  kv-caches it in the encrypted store — the download half of iOS
  `SCPService` for hosts without their own networking.

### Changed
- **Android is a hunting-focused app for now.** The activation (session
  start) surface and the bare Logger tab were removed; the Sessions
  container is gone. Hunter is now a top-level tab shaped like the iOS
  hunter log: today-stats header, the live spot feed as the body, and
  the quick-entry command bar at the bottom — tapping a spot seeds the
  bar directly. Activation code lives in git history for when sessions
  return.
- **Android — Spots tab now runs on the shared Rust spot engine.** The
  one-shot `SpotsApi` fetchers are replaced by the full `SpotEngineApi`
  (the same engine behind iOS hunter spots and Band Scope): background
  poll loop, merged POTA/RBN/SOTA/WWFF pool, DXCC + distance/bearing
  enrichment from the operator's home grid, per-source counts, and
  needed-status plumbing. New "All" filter chip shows the merged feed;
  the engine pauses while the app is backgrounded and refreshes on
  return. New `EnrichmentApi.cty_content()` FFI accessor feeds the
  engine the cached CTY.dat on Android (iOS keeps its own CTY cache).

## [1.94.1] - 2026-07-04

### Added
- **iOS — Band Scope radio-mode filter.** A new `mode` quick-toggle menu
  (CW / SSB / DIG mode groups, multi-select) joins wpm/dupes/rbn in the
  filter bar. Like the goal-profile predicate, it hard-hides in Heard and
  dims in Scope, compiled to SQL in the Rust core
  (`QuickToggles.enabled_modes` → `UPPER(spots.mode) IN (…)`), and
  participates in the honest `173 → 41` count.

### Changed
- **iOS — Band Scope Scope lens now hides filtered spots.** Filtered
  spots (goal profile, mode filter, RBN/dupes toggles, WPM ceiling) are
  removed from the Scope list instead of rendering dimmed — the dim-only
  rule confused more than it informed. Honesty is preserved elsewhere:
  gap/QSY math still runs on unfiltered data, the scrubber keeps filtered
  ticks visible (dimmed), and the `173 → 41` count still reports
  suppression. A new empty state distinguishes "no spots" from "all N
  spots filtered". Heard is unchanged (hard-hide + WPM dim with glyph).
- **iOS — Band Scope freshness fade retuned.** Calls were darkening too
  early: full ink now lasts 5 minutes (was 2), and the age-fade floor rose
  from 0.4 to 0.5 opacity.
- **iOS — Band Scope restyled to match the app design language.** The Band
  Scope dropped its custom hardcoded dark palette and forced dark mode: it
  now adapts to light/dark via the same semantic system colors as the rest
  of Field (grouped background, systemGray surfaces, separator hairlines,
  primary/secondary/tertiary text), tier accents map onto the standard
  semantic set (needed → orange, club → blue, POTA → green, RBN → gray),
  chips use the app-wide tinted-capsule badge pattern, and fixed-size fonts
  were replaced with Dynamic Type text styles (monospaced for callsigns,
  frequencies, and ages). The spot peek sheet now shows the spot's age and
  colors the mode chip by mode via a new app-wide `ModeColors` mapping
  (CW cyan, phone pink, digital indigo — promoted from the contest chips),
  and it embeds the session logger's callsign preview card
  (`LoggerCallsignCard` — name, flag, QTH/grid/distance/bearing chips,
  club memberships, worked-before count, notes) driven by the same
  streamed lookup pipeline, resolving portable prefixes/suffixes with the
  logger's primary-callsign rules (now shared as `CallsignParsing`). Filter-dimmed rows are clearer: the dim floor rose from 0.2 to
  0.35 and dimmed rows carry a small filter glyph explaining why (Scope
  goal-profile misses and Heard WPM-ceiling dims).
- **Contest engine now runs in the shared Rust core.** The entire Swift
  contest engine (definition parsing, per-QSO scoring, dupe detection,
  multipliers, exchange parsing, WPX prefixes, Cabrillo 3.0 export, schedule
  evaluation, off-time and band-change compliance, CWT prefill) was ported
  to `cw-domain::contest` and both apps re-pointed onto thin FFI facades —
  behavior-identical (byte-identical Cabrillo, all 12 production definitions
  verified against the wire format). Contest definitions are now fetched and
  cached by the Rust core (`contest_definition` table, schema v9) instead of
  the Application Support JSON cache, and contest QSOs ride the same Rust
  `SessionApi` logging path as everything else under `.on` (previously they
  bypassed it). Existing definition caches re-download on first use.

### Added
- **iOS — Band Scope v2: the two-lens spot browser.** The hidden Band Scope
  experiment was rebuilt from the mobile redesign spec: a frequency-sorted
  **Scope** list (sticky 5 kHz headers, pileup clustering, tappable
  clear-spectrum QSY dividers, scrubber strip with viewport sync and
  tap-to-scroll, freshness fade, tune-tap anchor with trust-decaying signed
  deltas and YOU line) and a recency-sorted **Heard** list (per-station
  collapse with heard counts, batched "N new spots" pill with unseen-line
  merge, needs shelf, time buckets, band filter tiles), sharing one tier
  color system (needed/club/human/skimmer), a peek sheet with Tune + Log
  QSO actions, and goal profiles (Everything / Parks / DXCC / Club skeds +
  user-defined). Filtering compiles to SQL in the Rust core
  (`goal_profile.rs` → `scope.spots` queries): Scope dims filtered spots,
  Heard hides them, and the header always shows the honest `173 → 41`
  count. The scope DB now carries spot enrichment columns (entity, park,
  source), a `spot_needs` projection, and a host-seeded `club_members`
  roster (SKCC-complete) to make those predicates answerable in SQL.
- **iOS — Spot SQL editor (spots-engine Phase 5).** The hidden Query Runner
  experiment is now a real editor (`SpotQueryEditorView`, still gated by the
  `.queryRunner` flag): monospace SQL editor with Run / Profile / Format
  (Format via the Rust `format_sql` FFI, matching CW Sweep's formatter),
  error banner with line/column from the engine, row-limit with Show More,
  saved `.cwquery` management (create / save-over / delete, seeded with CW
  Sweep's starter queries), and a static schema reference sheet ported from
  Sweep's schema browser. The engine's `qsos` table is fed from the newest
  log entries so worked-before starter queries have data to join.
- **iOS — "Filter by Saved Query" in the hunter spot filter sheet.** Mirrors
  CW Sweep's band-scope query mode: pick a saved `.cwquery` and the spot
  engine re-runs it after every publish, gating the hunter list to the
  query's `spot_id` result set (`set_band_scope_query` + snapshot
  `allowed_spot_ids`). Query errors surface in the sheet footer and fall
  back to the regular widget filters.
- **iOS — Carrier Wave server sync Phase 7 wiring.** The E2E sync client now
  validates its locally-held data key against the server's passphrase escrow
  (fingerprint check) before every push and refuses on mismatch — the guard
  against the 2026-07-03 poisoned-tenant incident where a stale key uploaded
  ~2k undecryptable QSOs. Creating a passphrase re-checks the server at
  creation time and refuses loudly if an escrow already exists (no silent
  overwrite; old blobs would be unrecoverable). New `CwStoreSyncMode`
  selection seam (Settings → Experiments → Sync Engine, default iCloud) lets
  `CloudSyncJournalEngine` drive `sync_run_once` against the Carrier Wave
  server instead of CKSyncEngine — the authority flip itself stays user-gated
  on two-device verification. A `BGAppRefreshTask`
  (`com.jsvana.FullDuplex.sync-refresh`) runs one enrollment-gated sync pass
  in the background, scheduled on foreground/background transitions. Snapshot
  cadence heuristic (`entries_since_snapshot >= max(30, total_log * 0.2)`)
  now checked on session end + app background; the actual encrypted snapshot
  upload is pending a cw-ffi snapshot export.

### Changed
- **iOS — Band Scope experiment re-pointed at the spot engine.** The
  standalone band scope now queries the engine's `scope.spots` projection
  (all enabled sources) instead of running its own POTA-only ingest into the
  retired GRDB mirror.
- **iOS — Settings reorganized around user intent.** Top-level groups are now
  My Profile / Account & Data / Services / Features / Hardware / General /
  Advanced / Help & Support / About. Every feature screen's settings (Logger,
  Hunter Log, POTA Activations, On Air Now, Hunt & P2P, Dashboard Metrics,
  Contest Calendar) now sit at one consistent depth under Features instead of
  being scattered across Appearance → Navigation, Logging, and Logger
  sub-screens. iCloud sync and Backups moved to Account & Data; the community
  screen (formerly "Activities") moved out of Sync Services and is named
  Community; Callsign Aliases moved to My Profile; Simple Logging Mode moved
  from Appearance into Logger; the two QRZ screens are disambiguated as
  "QRZ Logbook Sync" and "QRZ Callsign Lookup" with cross-references; the
  duplicate Operating Style editor and Hunter Log's duplicate Upload Services
  links were removed; About is split into Help & Support and About. Settings
  search index updated to match the new structure.
- **iOS — settings sub-screens got hero headers.** Each inner settings screen
  (Appearance, Logger, Hunter Log, POTA Activations, On Air Now, Hunt & P2P,
  Dashboard Metrics, Contest Calendar, Logbook Services, Community, iCloud
  Sync, Backups, Carrier Wave Sync, Data & Tools, Experiments, Radio) now
  opens with a large icon, title, and one-line description, matching the
  inner pages of the iOS Settings app. The Carrier Wave Sync row icon was
  removed for a cleaner top-level list.

### Fixed
- **iOS — Band Scope scrubber viewport tracks scrolling correctly.** The
  scrubber's visible-range rectangle was pinned at its left edge: cluster
  ids churn with every spot-engine publish, and rows destroyed by data
  refresh never reported themselves invisible, so orphaned visibility
  entries (including the entire previous band after a band switch) held the
  window minimum down forever. Visibility state is now pruned against live
  cluster ids on every scope rebuild, and rows reclaimed off-screen by the
  lazy list (which never fire the visibility callback) clean up their
  entries via `onDisappear`.
- **iOS — clubs membership apply no longer starves the main thread into a
  watchdog kill (`0x8badf00d`).** The compact membership cache (~82k rows)
  and large club rosters applied as one cw-store transaction, holding the
  global store mutex for multiple seconds; a main-thread store write blocked
  behind it tripped the scene-update watchdog (TestFlight crashes of
  2026-07-02/03). `ClubsApi` now applies membership and roster details in
  2,000-row chunked transactions, releasing the mutex between chunks so
  main-thread writes interleave. The membership ETag commits only with the
  final chunk, so an interrupted apply re-fetches and re-applies cleanly
  (links are idempotent). Clubs, friends, and the first-run cw-store import
  additionally hold background-task assertions so suspension mid-commit
  isn't a `0xdead10cc` kill.
- **iOS — sync no longer gets killed when backgrounded mid-write
  (`0xdead10cc`).** Background QSO/presence saves during sync committed one
  row at a time — each an autocommit fsync under `synchronous=FULL` — so the
  cw-store SQLite lock stayed held for the whole batch, and suspending the
  app inside that window was a RunningBoard `0xdead10cc` kill (TestFlight
  crash 3160). `OffMainStoreSeam` now uses the batch FFI upserts (one
  transaction per table), and `SyncService.syncAll` holds a background-task
  assertion so in-flight writes finish if the user backgrounds the app
  mid-sync.
- **Server — WebSDR bridge now reaches receivers behind the kiwisdr.com
  proxy.** `NNNN.proxy.kiwisdr.com` hosts answer the websocket handshake with
  an HTTP/1.0 307 redirect chain (frp → proxy2 host → port 8073) that
  tungstenite rejects outright, so the logbook viewer's Spots page failed
  with `connect_failed` for every proxied receiver. The bridge now follows
  up to three redirect hops — probing the Location with a plain HTTP request
  when the handshake response is unparseable — re-validates each hop against
  the SSRF rules, and preserves the stream path's case (the redirector
  lowercases `/SND`, which the receiver accepts but never attaches, yielding
  silence).
- **Sync — first pass against a new server now seeds the full log
  automatically (iOS + Android).** Dirty flags are cleared by pushes to *any*
  server, so switching servers (staging → prod) or enrolling a second device
  via an existing escrow uploaded nothing until the manual "Upload Full Log"
  repair. Both clients now track a per-server seeded flag beside the pull
  cursor and mark the whole log dirty on the first pass.
- **Sync — one 429 no longer aborts the pass.** The shared transport retries
  rate-limited and 5xx responses with bounded exponential backoff (safe:
  push is idempotent via `client_entry_id` dedup, blob PUTs overwrite, pulls
  are read-only). Previously a seed upload racing the app's other traffic
  against the per-IP governor failed outright.
- **Sync — the E2E data key is now scoped per server (iOS + Android).** A
  device switching servers silently reused its old data key: iOS
  `refreshStatus` trusted any local Keychain key without validating it
  against the server's escrow, so a whole log could be uploaded under a key
  the server's escrow can't decrypt — poisoning the tenant for every other
  device. The key now lives in a per-server slot (like the cursor and seeded
  flag); after a server switch the device correctly asks for that server's
  passphrase. Legacy unscoped keys are ignored and swept on forget.
- **Sync — decryption failures no longer masquerade as "network: aead
  error".** Pulled ciphertext the local key can't open is now surfaced as a
  key mismatch with an actionable message (re-enter the sync passphrase),
  e.g. after the escrow was recreated on another device or the device still
  holds a key recovered from a different server.
- **Clubs/friends sync wrote each row in its own fsync'd transaction.** The
  shared Rust `ClubsApi`/`FriendsApi` applied server results row-by-row under
  `synchronous = FULL`; a realistic membership cache (~82k rows across SKCC,
  QRPARCI, FISTS, NAQCC, CWops, …) took 6–7 minutes on tablet hardware while
  holding the global store lock, and any interruption aborted before the ETag
  was stored — so the next sync re-downloaded and re-ground everything. The
  apply (and its ETags) now commits as one transaction: one fsync, atomic,
  seconds instead of minutes. Benefits both platforms.
- **Android — friends and clubs never synced automatically.** Signing in left
  the Friends/Clubs tabs empty until the manual Refresh/Sync buttons were
  tapped. The app now syncs both at launch (when a session exists) and right
  after sign-in, mirroring iOS. Syncs run as single-flight app-scope jobs, so
  switching tabs or leaving a screen no longer cancels a sync mid-apply, and
  the Friends/Clubs screens join an in-flight launch sync instead of showing
  a stale empty cache. Also fixes a startup race where the launch coroutine
  could touch `authApi` before it was initialized.
- **Android — logger stamped QSO timestamps in milliseconds.** The standalone
  Logger wrote `qsoDate`/`importedAt`/`modifiedAt` in Unix millis while the
  cw-store contract (iOS + the shared Rust `SessionApi`/`ActivityLogApi`) is
  Unix seconds, corrupting date grouping and cross-surface rendering. The
  write path now stamps seconds, all formatters are seconds-native, and a
  one-time startup fixup rewrites legacy millis rows (values past year ~5138
  are unambiguous).
- **iOS — Home's "Resume session" row landed on the Sessions screen instead
  of the session.** The hero row only switched tabs; a paused session (or one
  the manager hadn't restored yet) left the user on the idle intent screen
  needing a second "Continue" tap. The row now posts
  `didRequestResumeSession`, and the Sessions tab resumes the most recent
  open session directly — flipping straight into the live logger.

### Changed
- **Android — sync card shows live steps and timings (iOS parity).** Enroll
  and sync surface the same phase labels as iOS ("Deriving encryption key…",
  "Downloading…", "Uploading…") with an elapsed-seconds readout, and the
  result line now includes per-step timings ("Pushed 2000 · pulled 13 in
  9.4s (prep 0.2s · down 1.1s · up 8.1s)"). Sync now drives the split
  pull/push FFI calls like the iOS client instead of the opaque
  `syncRunOnce`.
- **Android — sync card clarifies key removal.** "Turn off on this device" is
  now "Forget sync key on this device" with a caption explaining the server
  escrow is untouched and when to use it (key mismatch after a server or
  passphrase change).
- **iOS — spots engine moved to shared Rust core (Phase 4 swap).** The hunter
  feed, activator per-callsign spots, Logger RBN panel, POTA/SOTA hunt list,
  On Air card activity/friend spots, and the Logger's S2S summit enrichment
  are now served by the shared `SpotEngineApi` (fetch, merge/dedup, distance/
  region enrichment, and needs matching all in Rust; TuneIn hands off engine
  spots unchanged). New default-off sources arrive with it: DX Summit, DXHeat,
  DXWatch, and telnet DX cluster — toggles live in the Hunt spot filter sheet,
  and the cluster node (host/port, W3LPL default, presets from Sweep) is
  configured in Settings → Hunt & P2P. The Swift fetch/enrichment stack
  (SpotsService actor, SpotMonitoringService hunter fetch + enrichment,
  SpotNeedsMatcher matching, SOTAClient path behind SOTASpotsCache) was
  removed.

### Added
- **Android — operator profile settings.** Callsign + home grid moved from
  compile-time constants to a persisted, editable "Operator profile" card on
  the Account screen (grid validated as Maidenhead). Existing installs seed
  the profile from the newest QSO so logbooks keep their identity.
- **Android — activity heatmap on Home.** GitHub-style 52-week QSO grid
  (month labels, 5-level intensity, auto-scrolled to the current week),
  mirroring the iOS activity card. Counts come from an uncapped paged scan —
  the FFI has no per-day aggregate yet.
- **Android — Carrier Wave Sync (E2E sync server).** Passphrase-escrow
  enrollment (recovers an existing account key or mints + uploads a fresh one
  and queues the full logbook for the first push), manual "Sync now" plus one
  best-effort pass at launch, per-server pull cursor, data key in the
  Keystore-backed secure store. New shared-Rust escrow-envelope client for
  `PUT/GET /v1/sync/key` (`cw-sync` `put/get_key_blob`, `cw-ffi`
  `sync_put_key`/`sync_get_key`) — also unblocks iOS Phase 7. Server side is
  staging-only until prod deploys the sync routes.
- **Web — Spots map view.** The Spots page gets a Table | Map toggle: spots plot
  at their reference (park/summit) coordinates with band-colored markers, and
  tapping one starts a listen session with its ranked KiwiSDR receivers overlaid
  on the same map, color-coded by hearing likelihood (distance + receiver SNR +
  availability). The listen panel's receiver picker gets a matching Chips | Map
  toggle. New deps: leaflet + react-leaflet (CARTO dark basemap).
- **Server — spots carry reference coordinates.** `GET /v1/spots` now joins
  `pota_parks` (and cached SOTA activation-zone centroids) to return
  `latitude`/`longitude` per spot. This also fixes web receiver ranking, which
  silently fell back to an unranked directory list because POTA/SOTA spots never
  carry `spotterGrid`.

### Fixed
- **iOS — launch crash loop on large logs after updating to 1.94.0
  (watchdog 0x8BADF00D).** The SwiftData → cw-store seed import re-runs on the
  first launch of every new app version and wrote each row as its own SQLite
  transaction on the main thread. Under the store's durability pragmas
  (`synchronous=FULL` + `fullfsync`) that is two disk barriers per row —
  minutes of blocked main thread on 100k-QSO logs, so iOS killed the app
  (scene-update / failed-to-terminate watchdog) and the import restarted from
  scratch on relaunch, looping forever. The importer now does each batch
  entirely off-main on a fresh `ModelContext` (bounded memory per the
  PERFORMANCE.md batching pattern — no more paging 100k rows through the main
  context's row cache) and commits it as a single transaction via new cw-ffi
  batch upsert methods (`upsert_qsos` + 11 sibling entities, atomic per batch,
  one observer notify). 500 rows now cost one fsync cycle instead of 500, and
  the run loop stays responsive throughout. (Diagnosed from 5 device .ips
  reports, 2026-07-02.)

## [1.94.0] - 2026-07-01
- **iOS — session lifecycle now delegates to the shared Rust core (C2 remainder, `.on` mode).**
  `pause`/`resume`/`finish`/`end`/`merge`/`delete` (and `recordConditions`) run through the shared
  `SessionApi` — the same code Android uses — with the Swift path kept as an automatic fallback on
  any delegation failure. Ending a session runs the POTA UTC-midnight split and average-WPM
  metadata in Rust and reflects the results back into SwiftData (mirror-suppressed, CloudKit
  unaffected). Rove stops cut over to the structured cw-store `rove_stop` table via seam
  write-through + import backfill, with the legacy blob kept transitional for the CloudKit replica
  and UI. New `FfiReflector` overloads cover `LoggingSession`/`SessionSpot`/`ActivationMetadata`.
  Behavior is unchanged until the sessions entity is flipped Rust-authoritative (user-gated on
  two-device verification).

### Fixed
- **Web — logbook frequency shown/exported 1000× too small.** The logbook viewer
  treated `SyncQso.frequency` as kHz and divided by 1000, but the sync wire
  value is already MHz (cw-ffi projects the store's `freq_khz / 1000` onto the
  wire). 20m FT8 rendered as `0.014` instead of `14.074`. Fixed the display in
  the table, mobile row, and dedupe pane, and the ADIF `FREQ` export (which was
  also 1000× low). No conversion is now applied.

### Fixed
- **KiwiSDR listening dropped after ~10 s (both iOS and web).** Modern KiwiSDR
  firmware classifies any client that opens only the audio websocket — without
  fetching web assets from the same IP — as a "non-Kiwi app" and kicks it with
  `MSG too_busy` at exactly 10 s (`EXT_API_DECISION_SECS`; the receiver's per-IP
  `web_served` counter must reach 3). The original Swift Tune In client was
  already subject to this on updated receivers. Both the Rust client
  (`cw_net::kiwisdr::connect`) and the web bridge (`/v1/websdr/stream`) now
  fetch a handful of the receiver's assets (`/`, `/kiwisdr.min.js`,
  `/config/config.js`, `/status`) before opening the audio socket, as a browser
  loading the UI does, so the stream is allowed to continue. Verified a 35 s
  stream survives against live v1.843 receivers that previously kicked at 10.5 s.
- **KiwiSDR modern stream path.** Use `/ws/kiwi/{ts}/SND` (modern firmware) with
  a fallback to the legacy `/{ts}/SND` path; the legacy path on modern firmware
  completes the handshake but never attaches a stream (silent).

### Added
- **Rust core — Sessions + Hunter Log delegation (iOS, hidden experiment).**
  `ActivityLogManager` and `LoggingSessionManager.logQSO` now delegate to the
  shared Rust core (`ActivityLogApi` + `SessionApi`) when the experiment flag
  is `.on`, with reverse-reflector hydration (`FfiReflector`) keeping SwiftData
  mirrors in sync. Includes structured rove-stop storage, POTA UTC-midnight
  session split, end-of-session WPM averaging, and NOAA conditions merge in
  `SessionApi`. Rust APIs receive lowercase ids (Swift `uuidString` is
  uppercase and silently missed rows); any delegation failure falls back to
  the SwiftData path so no QSOs are dropped.
- **Rust core — SDR selection + listening ported and cut over (iOS).** The entire
  KiwiSDR stack behind Tune In / WebSDR recording now lives in the shared Rust
  core: `cw_domain::kiwisdr` (mode/passband tables, IMA ADPCM decode, SND/MSG
  protocol parsing, public-directory parsing with the kiwisdr.com HTML fallback,
  `/status` parsing, Tune-In candidate dedup, QSY detection, receiver-quality
  rules), `cw_net::kiwisdr` (directory fetch + daily disk cache, bounded
  `/status` enrichment, tokio-tungstenite websocket audio client with auth
  handshake, compression, tuning, AGC, keepalive, and server-redirect
  following), and a new async `cw-ffi` **`SdrApi`** (directory search, streamed
  enrichment, all three Tune-In strategies with RBN + HamDB lookups in Rust,
  live audio via a PCM callback listener, stoppable QSY + receiver-quality
  monitors, `kiwi_mode_info`). The Swift `Services/WebSDR/` stack now delegates:
  `KiwiSDRClient`/`WebSDRDirectory`/`KiwiSDRStatusFetcher` are thin FFI wrappers,
  `KiwiSDRADPCM` and the Swift mode tables are deleted, and
  `TuneInManager`'s selection + smart features call the shared core. Swift keeps
  only playback (ring buffer + AVAudioEngine), recording, and
  followed-activator storage. `RbnClient` gains a per-callsign spot fetch.
- **Web — spots page with KiwiSDR listening.** The logbook viewer gains a Spots
  page (active spots from `/v1/spots`, auto-refresh) with per-spot Listen:
  receiver ranking via the shared Rust `cw-domain` KiwiSDR logic compiled to
  WASM, KiwiSDR websocket audio bridged through new server proxy endpoints
  (`/v1/websdr/directory`, `/v1/websdr/status`, `/v1/websdr/stream`) to avoid
  CORS/mixed-content, IMA ADPCM decode in WASM, and AudioWorklet playback.
- **Web — logbook pagination + duplicate finder.** The logbook viewer
  (`server/logbook-web/`) now **paginates** the QSO table at 100 rows/page
  (numbered prev/next control; resets to page 1 on query/sort change) instead of
  rendering the entire log at once. A new **Find duplicates** button scans the
  log for repeated call/band/mode within an adjustable time window (default
  ±15 min), groups them with an auto-chosen keeper (confirmed → most-complete →
  earliest) and pre-selected duplicates, and — on confirm — **soft-deletes** the
  selected QSOs by pushing `Delete` journal entries back to the E2E sync server.
  This is the viewer's first write path: the WASM crate gains `seal_blob`
  (gzip + ChaCha20Poly1305, byte-compatible with the apps' `cw-sync` push), and
  `sync/writeClient.ts` builds snake-case `JournalPayload`s, `POST /v1/sync/push`,
  then PUTs each ciphertext to the presigned R2 URL. Deletes are soft
  (`is_hidden`) and propagate to every device on next sync. **Manual deploy
  step:** the R2 `cwlogs` CORS policy must now also allow `PUT` (not just `GET`)
  for uploads to succeed in-browser. New `logbook/dedupe.ts`,
  `sync/writeClient.ts`, `components/DedupePane.tsx`; guarded by the new
  `cw-sync` `browser_delete_wire_json_deserializes` wire-format test.
- **Web — account pane with "sign out everywhere".** The logbook viewer (`server/logbook-web/`) gains an **Account** button in the header that opens a modal listing the account's active sessions (device name / platform / last-active, from `GET /v1/auth/devices`) and a **Sign out everywhere** action (with an inline confirm) that revokes every device and bumps the account kill epoch via the existing `POST /v1/auth/logout/all`, invalidating all outstanding tokens — including this tab's — before clearing local state and bouncing to login. No server changes; both endpoints already existed behind JWT auth. New `src/auth/account.ts` + `src/components/AccountPane.tsx`.
- **Web — logbook viewer for the E2E sync server.** A standalone browser app (`server/logbook-web/`, Vite/React/TS) served same-origin by activities-server at **`/logbook`** that lets a user browse the logs they've stored on the E2E-blind sync server — with **all decryption in the browser**, so the server stays blind. Login reuses the iOS account flow (email magic-link + PKCE → JWT). A new WASM crate **`cw-web-crypto`** compiles the exact Rust `cw-crypto` (Argon2id + ChaCha20Poly1305) to wasm, so there's zero wire-format drift: the user's sync passphrase unwraps the escrowed data key locally (`open_escrow`), then each journal blob is fetched from Cloudflare R2 (presigned GET), decrypted + gunzipped (`decrypt_blob`), and folded — upserts/deletes in server-sequence order — into the current QSO set. UI: sortable/filterable table (search by callsign; filter band/mode/date range) + client-side ADIF export. The passphrase and data key live in memory only (never storage). The wasm `pkg` is vendored + committed so the frontend builds offline in CI/Docker; the release workflow + Dockerfile now build and package `logbook-web/dist`. **One manual deploy step:** the R2 `cwlogs` bucket needs a CORS policy allowing browser GET from the server origin (see `server/docs/features/logbook-web.md`). Not gated on the CloudKit→sync authority flip — read-only, additive. Plan: `docs/plans/2026-07-01-logbook-web-viewer.md`.
- **Server — non-CloudKit sync server (E2E dumb log, horizontally scalable).** New `/v1/sync/*` surface that replaces CloudKit as the sync transport: a per-user append-only journal the server never parses. `push` reserves a contiguous block of monotonic per-tenant sequence numbers via one atomic `sync_cursor` row (`ON CONFLICT … last_seq + $n RETURNING`) and returns presigned PUT URLs; clients upload **opaque ChaCha20Poly1305 ciphertext** blobs straight to object storage, so the app tier moves metadata only and stays stateless (poll delivery, no per-connection state). `changes?since=` streams ordered index rows + presigned GETs; `snapshot`/`bootstrap` bound journal growth and give new devices a one-round-trip baseline; `key` escrows the passphrase-wrapped (Argon2id) data key the server can't read. Blobs live in an S3-compatible bucket (Cloudflare R2 verified end-to-end) behind a `BlobStore` trait (in-memory impl for tests, `S3Store` for prod); metadata + the wrapped-key blob live in Postgres (`046_sync.sql`: `sync_entry`/`sync_cursor`/`sync_key_blob`). Auth reuses Phase-5 OAuth (tenant = account UUID). Client side: new `cw-crypto` crate (KDF/AEAD/escrow) and `cw_sync::HttpSyncTransport` implementing the existing `SyncTransport` trait, plus `cw-ffi` escrow + `sync_run_once` exports; `SyncQso` was brought to full wire-parity with the Swift journal's `QSOFields` (39 fields, merge rules ported from `CloudSyncConflictResolver`). Verified: 686 cw-core tests, DB-backed server round-trip (push→upload→changes→download, idempotency, snapshot+bootstrap) against live Postgres, and a live R2 presigned round-trip. Not yet live for users — the iOS `BGTaskScheduler`/key-setup UI + the `CKSyncEngine`→`HttpSyncTransport` authority flip (needs two-device verification) remain. Design: `docs/superpowers/specs/2026-06-30-sync-server-design.md`.
- **Server — Phase 5 OAuth multi-device sign-in.** A callsign can now be used on more than one device. Previously the only token-minting path was *onboarding*, which always tried to create a brand-new account and so hit the exclusive `upper(callsign)` index (`CallsignTaken`) the moment a second device verified an already-registered callsign — there was no "sign in to my existing account" flow at all. Now an unauthed `verify/start` for a callsign that already belongs to an account is treated as a **sign-in**: the magic link is addressed to the account's **on-file** email (directory address if resolvable, else the address it verified under) — **never** a fresh user-supplied one, so a stranger can't graft a device onto someone else's callsign — and the verification is bound to that account. At `/token` (and `/verify/poll`), a bound account that already owns the callsign mints a **new device + its own refresh family** (201), giving each device an independent session (and `logout`/device-revoke scope); the D8 multi-callsign *attach* path (callsign new to the account) still returns 204, and brand-new onboarding still creates the account. The land-grab defense is unchanged — a *different* account still cannot claim a callsign. New `db::auth::find_account_for_callsign`; `issue_from_claim` split into sign-in / attach / onboarding; new DB + HTTP tests (incl. on-file-email-wins-over-attacker-supplied and two-devices-one-account). Design: `docs/plans/2026-06-21-phase5-oauth-overhaul.md`.
- **Android — live spot monitoring + callsign enrichment (new shared Rust APIs).** Android gains a **Spots** tab streaming POTA / RBN / SOTA / WWFF spots and inline **callsign enrichment** badges, both built on three new `cw-ffi` surfaces so the logic is shared, not duplicated per-platform: **`SpotsApi`** (async, wraps the existing `cw_net` POTA/SOTA/WWFF clients + a new `RbnClient` proxying through `{activities}/v1/rbn/spots`) returning the same `Ffi*Spot` records the iOS decoders produce; **`QrzApi`** (a new `cw_net::QrzClient` — QRZ XML session auth + callbook lookup ported faithfully from `CallsignLookupService+QRZ`, credentials via the existing host `SecureStore`, in-memory session-key cache with single-flight re-auth); and **`EnrichmentApi`** (DXCC entity via `cw_domain::cty` + SKCC membership via `cw_domain::skcc` + club membership from the store, with CTY.dat / SKCC roster downloaded once and cached in the encrypted store for offline cold starts). The Spots tab polls every 60 s, colors rows via `band_derive`, shows DXCC/SKCC/QRZ/club badges, and tap-to-log prefills the Logger quick-entry; QRZ credentials are entered on the Account tab. New Rust modules carry parity unit tests (QRZ XML parse, SKCC index, enrichment wiring); `cargo` clippy + workspace tests green (306+), Kotlin bindings regenerated, Android `:app:assembleDebug` green. Polo callsign notes deferred (no global source — club-configured). See `docs/plans/2026-06-28-android-spots-and-enrichment.md`.
- **Rust core — medium facade swaps cut over to the shared Rust core (iOS + Android).** Six domain subsystems whose Rust ports already existed + were parity-tested but whose apps still ran duplicated Swift now delegate to the core, with the Swift logic deleted: **CAT protocols** (`cw_domain::civ`/`kenwood`/`yaesu` → Swift `CIVProtocol`/`KenwoodProtocol`/`YaesuProtocol` + mode enums — command builders, response parsers, BCD/frame handling); **spot decoders** (`cw_net::pota`/`sota`/`wwff`/`pskreporter` → `POTASpot`/`SOTASpot`/`WWFFSpot`/`PSKReporterSpot`, joining the earlier `rbn` cutover — JSON/HTML/XML decode + derived band/MHz/epoch fields, with new `parse_response` decoders + tests added to `cw-net`); **ADIF** (`cw_domain::adif`/`adif_validator`/`adif_catalog` → `ADIFParser`/`ADIFFieldValidator`/`ADIFCatalog` — tokenizer, the full `validate_*` family + `validate_for_upload`, mode/band/submode tables); **band/mode** (`cw_domain::band`/`mode`/`band_plan` → `BandUtilities`/`ModeEquivalence`/`BandPlan` — band derivation, mode classification/equivalence/dedup, US band-plan segments); and **callsign/DXCC/CTY** (`cw_domain::callsign_detector`/`callsign_edit_distance`/`cty` → `CallsignDetector`/`CallsignEditDistance`/`CTYParser`/`DXCCEntity`, the CTY database exposed as a UniFFI object like SCP). New `cw-ffi` modules `cat`/`pota`/`sota`/`wwff`/`pskreporter`/`adif`/`band_mode`/`callsign`/`cty`; `CwFfi.xcframework` + Kotlin bindings regenerated. The original Swift suites (CIV/Kenwood/Yaesu `ProtocolTests`, `ADIFParserTests` + `ADIFFieldValidator*`, `BandUtilitiesTests`/`ModeEquivalenceTests`, `CallsignDetectorTests`) pass unchanged as the cutover-parity gate; Rust clippy + workspace tests green; iOS app + CarrierWaveCore + Android app all build. Deliberately left Swift-side: the `CWTextElement` rendering path (`CallsignDetector.parseElements`) and propagation/antenna/azimuthal (stateful render-hot-path math) — both deferred per `docs/plans/2026-06-28-rust-core-remaining-ports.md`; dashboard analytics was already cut over.
- **Rust core — RBN spots, Super Check Partial, SKCC roster, and Polo notes ported + cut over (iOS + Android).** Four previously Swift-only domain pieces now live in the shared Rust core and are consumed by both apps: `cw_net::rbn` (`RbnSpot` + the three response shapes + derived band/MHz/formatted/epoch — port of `RBNSpot.swift`), `cw_domain::scp` (`ScpDatabase`: dedup/sort + prefix/substring/near-match — port of `SCPDatabase.swift`), `cw_domain::skcc` (pipe-delimited roster parser + award resolution + by-callsign index — port of `SKCCMembershipStore.swift` parsing + `SKCCMember.swift`), and `cw_domain::polo_notes` (Ham2K Polo callsign-notes line grammar + Unicode emoji/name/note split — port of `PoloNotesParser.swift` + `PoloNotesEntry.swift`). Exposed over UniFFI (`cw-ffi` modules `scp`/`skcc`/`polo_notes`/`rbn`); the Swift facades (`SCPDatabase`, `SKCCMembershipStore.parse*`, `PoloNotesParser`, `RBNSpot.decodeResponse`, `RBNClient.fetchSpots`) now delegate to Rust and the duplicated Swift logic is deleted, with the original `SCPDatabaseTests`/`SKCCMembershipStoreTests`/Polo enrichment tests passing unchanged as the cutover-parity gate. 39 new Rust parity tests; clippy clean. `CwFfi.xcframework` + Kotlin bindings regenerated; iOS app + CarrierWaveCore/Data packages + Android app all build.
- **Android — configurable activities-server URL.** The Android app's activities-server base URL (clubs + OAuth) is no longer hardcoded. New `ServerConfig` persists it in shared prefs (defaulting to production); `CwApp` reads it at startup and exposes `updateBaseUrl(...)`, which rebuilds the OAuth + clubs FFI clients against the new server (leaving the old clients intact if the URL is unusable). A "Activities server" card on the Account screen lets the operator point at a staging or local dev server. Mirrors the iOS `ActivitiesClient` base-URL configuration.
- **iOS — Phase 5 OAuth client core (additive; dual-token).** New `OAuthClient` actor (app target) implements the client half of `/v1/auth/*`: PKCE-bound magic-link verification (`startVerification` → `exchange`), single-flight refresh, and `logout`. The rotating refresh token is stored in the Keychain (`activitiesOAuthRefresh`); the short-lived access token is held in memory only (never persisted). PKCE uses the server's `hex(sha256(verifier))` S256 variant. `ActivitiesClient.ensureAuthToken()` now prefers a valid OAuth access token when a session exists and otherwise falls back to the legacy `fd_` device token (the server's dual-auth accepts both), so this is fully additive. Remaining client work: onboarding/verify UI + the magic-link return path (universal link or poll, O4) to deliver the `code` to `exchange`, and migrating the remaining direct `getAuthToken()` call sites. (App-target compilation verified by Xcode Cloud on merge; SwiftFormat + SwiftLint clean.) Design: `docs/plans/2026-06-21-phase5-oauth-overhaul.md` (§10).
- **Server — Phase 5 OAuth directory-email verification tier (D6/F1).** New `auth/directory.rs` resolves a callsign → its on-file email via the QRZ.com XML API (session-key caching + re-auth on timeout; `Null` when `QRZ_USERNAME`/`QRZ_PASSWORD` are unset, plus a `Fixed` map for tests). `verify/start` (and the authed multi-callsign `callsigns/verify/start`) now prefer the directory: when an on-file address exists, the magic link is sent **there** and the verification is recorded as `directory_email` (the only tier permitted to inherit legacy callsign-keyed data); a user-supplied address is used only as a fallback at the weaker `user_email` tier. Critically, an attacker-supplied email **cannot** redirect a directory-resolvable callsign (F1) — proven by test. Fail-closed: no QRZ creds → directory tier off → everything stays `user_email` (no inheritance). 188 server tests pass; clippy-clean. Remaining: legacy `fd_` rejection (final cutover) + client/iOS wiring. Design: `docs/plans/2026-06-21-phase5-oauth-overhaul.md`.
- **Server — Phase 5 OAuth dual-auth + JWT middleware + revocation (additive).** The existing protected social-API routes now accept **either** a Phase 5 OAuth JWT access token **or** a legacy `fd_` device token — no hard cutover. A JWT request resolves/ensures a `participants` bridge row so every callsign/`participant_id`-keyed handler keeps working unchanged, and `AuthContext` gains an optional `account_id`. New surface: `auth/jwt_middleware.rs` (`require_jwt_auth` for the account-management routes), `auth/revocation.rs` (in-process revocation cache refreshed across a horizontal pool via Postgres `LISTEN/NOTIFY`, D10/F3), and authenticated endpoints `/v1/auth/{logout/all, devices (GET/DELETE), callsigns/verify/start}` (multi-callsign attach, D8). `revoke_account` now `pg_notify`s the revocation channel. The verifier (JWT keys + cache + listener) is built once and shared by the dual-auth middleware and the `/v1/auth/*` routes; when keys are unset the server falls back to legacy `fd_`-only. 180 server tests pass (incl. dual-auth HTTP + revocation cache); clippy-clean. Remaining: directory-email resolution, legacy `fd_` rejection (the final cutover), and client/iOS wiring. Design: `docs/plans/2026-06-21-phase5-oauth-overhaul.md`.
- **Server — Phase 5 OAuth2 auth overhaul, server-side foundation (additive; not yet live).** The gating piece for the `cw-sync` server transport. Fully additive — existing `fd_` device-token auth is untouched, and the new `/v1/auth/*` routes only mount when JWT signing keys are configured. Delivered: migration `044_oauth_accounts.sql` (unified `accounts` identity keyed on UUID with callsign as a verified *attribute*, plus `account_callsigns`, `devices`, `refresh_tokens`, `email_verifications`, `revoked_jti`); `auth/jwt.rs` (EdDSA/Ed25519 access tokens, 15-min TTL, alg-locked verification with mandatory `aud`/`iss` + clock-skew leeway + a `tokens_valid_after` emergency-revocation epoch); `auth/tokens.rs` (opaque `cwr_` refresh tokens, SHA-256-hashed at rest, PKCE S256 helpers); `db/auth.rs` (account/device creation with the deferred primary-callsign FK, `assert_account_owns_callsign` IDOR guard, idempotent refresh rotation with family reuse-detection + grace-window replay, email-verification create/click/exchange); `auth/mailer.rs` (Resend over reqwest + a dev NullMailer); and the `/v1/auth/verify/start`, `verify/complete`, `token`, `token/refresh`, `logout` handlers (magic-link verification → account + token issuance → rotation, PKCE-bound, with email-bomb rate limiting). Security-hardened per an adversarial design review (callsign-takeover, JWT confusion, refresh self-DoS, IDOR, magic-link leak). 30 new tests (unit + DB-gated integration + an HTTP onboarding→token→refresh→logout flow), all green; clippy-clean. Remaining: the middleware swap migrating existing handlers off `participant_id` → `account_id`, directory-email callsign→email resolution, the multi-callsign attach flow, and the client/iOS wiring. Design: `docs/plans/2026-06-21-phase5-oauth-overhaul.md`.
- **Rust core — Phase 4 analytics read surface complete (hidden experiment).** The non-list aggregation reads (Phase 4 item #6) now have a full SQL-`GROUP BY` catalog in cw-store, fronted by the `AnalyticsReadSource` protocol (Rust `FieldStore` impl + pure-Swift `AnalyticsAggregator` oracle) and parity-tested entirely in the package loop (no device). Aggregates: `qso_distinct_counts`, `qso_count_by` (band/mode-family/DXCC/month), `was_summary`, `dxcc_worked` (with cw-domain lat/lon), `qso_activation_rollup`, `qso_grid_tiles`, `service_presence_counts` (uploaded/pending, deduped by qso_id, primary-callsign + configured-service aware), `qso_park_rollup` (per-park activation-days + hunt QSOs + last-worked, comma-split refs — retires `MyParksView`'s unbounded scan once routed), `qso_state_counts` (valid 50-state), `session_equipment_rollup` + `session_combo_rollup` (over `logging_session`), and `brag_period_metrics` (the SQL-trivial brag subset; distance/streak/window/new-this-period/activation-grouping metrics stay SwiftData-side by design). Every aggregate reuses the `.cwquery` `WHERE` compiler + `cw-domain` grouping keys and applies the canonical visible-QSO filter (hidden + metadata exclusion) where the Swift source does. 19 cw-store cargo tests + 12 Swift cross-impl parity tests; clippy + swiftlint clean. App-target routing of the consuming actors (StatsComputationActor, POTAAwardsActor, GridOverlayDataActor, AsyncServicePresenceCounts, EquipmentStatsActor, MyParksView, BragSheetComputationActor) onto `AnalyticsReadSource` (gated by `CwStoreQSOMode`) is the remaining, device-gated step. Design: `docs/plans/2026-06-20-rust-analytics-surface-design.md`.
- **Rust core — Phase 4 generic write seam + main-actor write-site routing for EquipmentItem, ActivityLog, RadioMacro (hidden experiment).** New app-target `EntityWriteSink<Model>` — a generic write seam (the `RustCountReadSource` factory idiom) mirroring `QSOWriteSink`'s contract: in `on` it writes cw-store FIRST (canonical) then a `CwStoreMirror`-suppressed SwiftData save; `shadow`/`off` are unchanged (the unsuppressed mirror dual-writes in `shadow`). `EntityWriteSinkFactory` wires the per-entity `upsert_*`/`delete_*` FFI for all 11 uniform entities (everything except QSO/ServicePresence, which keep dedicated sinks); a type-keyed `EntityWriteSinkRegistry` routes `commitUpsert`/`commitDelete` from call sites. Registered/cleared alongside the QSO sinks in `applyQSOMirrorMode`. User-CRUD write sites are routed for **EquipmentItem** (detail edit/delete, browser + inventory-picker add), **ActivityLog** (create/activate/deactivate/delete/switch-profile/grid/location in `ActivityLogManager`, batching co-mutated logs), and **RadioMacro** (create/duplicate/tombstone/edit/install/update across the macro views; tombstone routes as an upsert). Un-routed sites stay correct via the mirror (cw-store as a follower), so this is safely incremental. Deferred: LoggingSession + the off-main entities (SessionSpot ingestion, WebSDRRecording, ActivationMetadata, CloudSyncMetadata, standalone ServicePresence marking) are the consumer-snapshot unwind; WebSDRFavorite is blocked on an app-vs-package type collision; UploadDestination has no app-target write site. Full app target builds (arm64 sim). Handoff: `docs/plans/2026-06-18-rustification-finish-handoff.md`.
- **Rust core — Phase 4 list read sources with full field+order parity for the 8 remaining peripheral entities + LoggingSession (hidden experiment).** Following the EquipmentItem template, every non-QSO entity now graduates past the count-only backbone to a real list read cutover. New package-level read sources (protocol + SwiftData impl + Rust `FieldStore` impl, each with a `*Snapshot` mirroring its `Ffi*` type exactly): `ActivationMetadataReadSource`, `ActivityLogReadSource`, `CloudSyncMetadataReadSource`, `RadioMacroReadSource`, `SessionSpotReadSource`, `UploadDestinationReadSource`, `WebSDRFavoriteReadSource`, `WebSDRRecordingReadSource`; and `LoggingSessionReadSource` is upgraded from count-only to a full `all() -> [LoggingSessionSnapshot]` covering all ~75 columns. Each exposes `count()` + an ordered `all()`; ordering uses the entity's stable key (`id` where present, else the natural key — `recordName` for CloudSyncMetadata, `hostPort` for WebSDRFavorite, composite `(parkReference, date)` for ActivationMetadata). Both backends produce snapshots via the canonical `SwiftDataStoreImporter.project(_:)` mapping (no duplicated field logic); Rust list reads go through the bounded `fetch_*` FFI (cw-store hard-caps at 1,000 rows). New per-entity `*ReadSourceTests` assert column-for-column round-trip fidelity through cw-store plus parity after a mutate+re-upsert — 18 new tests, all green on the package test loop (`swift test`, no app target / device required). Write seams + write-site routing for these entities remain app-target work (deferred, needs an on-device verification pass). Handoff: `docs/plans/2026-06-18-rustification-finish-handoff.md`.
- **Rust core — Phase 4 EquipmentItem list read source with full field+order parity (hidden experiment).** EquipmentItem is the first peripheral entity to graduate past the count-only backbone to a real list read cutover. New package-level `EquipmentItemReadSource` (protocol + SwiftData impl + Rust `FieldStore` impl) exposes `count()` and an id-ordered `all() -> [EquipmentItemSnapshot]`. Because the equipment catalog is a plain table scan (no app-target query compiler, unlike QSO), **both** backends produce snapshots — so the new `EquipmentItemReadSourceTests` assert column-for-column round-trip fidelity through cw-store (every projected field of `FfiEquipmentItem`), not just the row count, plus parity after a mutate+retire re-upsert. `EquipmentItemSnapshot` mirrors `FfiEquipmentItem` exactly; the SwiftData side reuses the canonical `SwiftDataStoreImporter.project(_:)` mapping so there's no duplicated field logic. The Rust list read goes through the bounded `fetch_equipment_items` (cw-store hard-caps `fetch_*` at 1,000 rows — the bounded-fetch invariant, ample for a few-dozen-row inventory). Handoff: `docs/plans/2026-06-18-rustification-finish-handoff.md`.
- **Rust core — Phase 4 read sources + write seam for LoggingSession & ServicePresence (hidden experiment).** Two new package-level read sources, each with a SwiftData impl and a Rust (`FieldStore`) impl routed by `CwStoreQSOMode`: `LoggingSessionReadSource` (first slice of the largest non-QSO read-cutover surface) and `ServicePresenceReadSource` (backs the presence write-seam parity). Both start by proving the total row-count invariant — the exact pattern QSO took before its list migration — via a new generic `StoreCountParity` comparison; richer field/order parity arrives with the per-view list migration. New app-target `ServicePresenceWriteSink` mirrors `QSOWriteSink` for the standalone sync-upload marking path (presence mutations that do **not** ride a QSO save): in `on` it upserts presence to cw-store first/canonically then does a `CwStoreMirror`-suppressed SwiftData save; `off`/`shadow` are unchanged. The sink + registry are constructed alongside `QSOWriteSink` in `CarrierWaveApp.applyQSOMirrorMode`; rerouting the existing presence-save call sites onto it is deferred (the off-main marking paths come with the consumer-snapshot unwind). New package tests (`LoggingSessionReadSourceTests`, `ServicePresenceReadSourceTests`) assert count parity after mirrored upserts and a standalone `needsUpload` flip. The remaining nine peripheral entities (ActivationMetadata, ActivityLog, CloudSyncMetadata, EquipmentItem, RadioMacro, SessionSpot, UploadDestination, WebSDRFavorite, WebSDRRecording) share a generic count-read-source backbone — `SwiftDataCountReadSource<Model>` over `PersistentModel` + a `RustCountReadSource` with one factory per entity wiring its `FieldStore` count method — so all 12 entities now have parity-checked count reads; `CountReadSourceTests` proves it end-to-end on the three trivially-constructible id-keyed entities (relationship/natural-key fixtures deferred to their cutovers). Handoff: `docs/plans/2026-06-18-rustification-finish-handoff.md`.
- **Rust core — entity delete FFI for the remaining 11 cw-store entities.** `cw-store` + `cw-ffi` gained `delete_*` for `LoggingSession`, `SessionSpot`, `ActivationMetadata`, `ActivityLog`, `EquipmentItem`, `RadioMacro`, `WebSDRRecording`, `WebSDRFavorite`, `UploadDestination`, and `CloudSyncMetadata` — joining the existing `delete_qso`/`delete_service_presence`. id-keyed entities delete by `id`; natural-key entities use their real key (`activation_metadata` `(park_reference, date)`, `websdr_favorite` `host_port`, `cloud_sync_metadata` `(entity_type, local_id)`). Each FFI wrapper fires `notify(.Delete)` (drops the DB lock first, like the QSO path) so observers can re-enter the store. This unblocks `CwStoreMirror` covering non-QSO entity *deletes* (without it the mirror would orphan rows). New cw-store delete unit tests for the id + both composite + host_port key shapes (86 cw-store tests; clippy clean); `CwFfi.xcframework` regenerated (device/sim/macOS slices) and the Swift bindings restaged. Deletes are idempotent — a missing key succeeds.
- **Rust core — QSO cutover sub-project C (Logbook reads from the Rust store).** The Logbook list (`LogsListContentView`) now renders a backend-agnostic `QSORowSnapshot` supplied by a `LogbookSnapshotSource`, routed by the hidden off-by-default `cwStoreQSOMode` experiment: `off`/`shadow` → SwiftData (behavior-identical to before), `on` → the Rust cw-store query path. `QSORowSnapshot` was widened to every field the row cell needs (frequency, RST, grid, park, name, power, state, LoTW/QRZ confirmation) plus a `[PresenceSummary]` for the per-service badges; the Rust `fetch_qsos_query` projects presence in one batched `WHERE qso_id IN (...)`, and the SwiftData path derives the same shape from `qso.servicePresence`. Writes (swipe/bulk delete, group-into-session) and the detail screen stay on SwiftData via an id-bridge (`LogbookIDBridge`: snapshot id → live `QSO`); in `on` mode a `CwStoreMirror.drain()` read-after-write barrier runs before re-paging. Filtered search now paginates the whole match set in `on` (the legacy SwiftData path keeps its bounded batch window). Acceptance gate: `QueryParityTests` extended to assert presence parity between the SwiftData mapper and the Rust projection; new Rust `presence_projection_matches_fixture` + FFI `fetch_qsos_query_projects_presence` tests. Design: `docs/plans/2026-06-16-qso-cutover-C-design.md`.
- **Rust core — Phase 2 mechanical port batch 3 (ADIF catalog + validator + CallsignDetector).** `adif_catalog` ports ADIF 3.1.7 mode (~60) + band (~33) + submode→parent (~70) tables from `ADIFCatalog.swift` (US state table deferred until a downstream consumer needs it). `adif_validator` ports `ADIFFieldValidator.swift` end-to-end: per-field validators (callsign, band, mode, submode/parent, freq-in-band, date YYYYMMDD with leap-year math, time HHMM/HHMMSS, grid 2/4/6/8-char Maidenhead) plus the `validate_for_upload` composite. `callsign_detector` ports the regex-based core of `CallsignDetector.swift`: `extract_callsigns` (uppercased, deduped), `detect_primary_callsign` (context priority DE-identifier > CQ-call > response > unknown, last-wins within tier), and grid/power/RST extractors. Adds `regex = 1` as a `cw-domain` dependency. The `CWTextElement` rendering surface is intentionally deferred (UI-side, comes when that layer is also ported). Workspace at 155 Rust tests (was 134).
- **Rust core — Phase 2 mechanical port batch 2 (ADIF + Propagation).** `adif` ports `ADIFParser.swift` end-to-end (hand-rolled `<field:length>value` tokenizer that avoids a regex dependency, case-insensitive `<eor>`/`<eoh>` splitting, submode-wins-over-mode semantics, callsign uppercased + band lowercased). `propagation` ports `PropagationEstimator.swift` with identical SFI/K/UTC math and exact label thresholds (Low/Moderate/High/Very High for SFI; Quiet/Unsettled/Active/Storm/Severe Storm for K-index) so UI strings stay stable across the language boundary. Workspace at 134 Rust tests (was 120). Clippy clean.
- **Rust core — Phase 2 mechanical port batch (Levenshtein, Morse, CTY, rig protocols).** Seven new pure-logic modules in `cw-domain`, all parity-tested: `callsign_edit_distance` (Levenshtein for spotted callsigns + near-match search), `morse` (full International Morse code table including prosigns + word-level pattern distance), `cty` (AD1C CTY.dat parser → `DxccEntity` + `CtyDatabase` with longest-prefix lookup that handles portable indicators like `W1ABC/VP9`), `text_protocol` (shared `;`-terminated response extractor), `kenwood` (K3/Elecraft ASCII command builder + FA/MD/XT/RT/RO/PC parsers + `KenwoodMode` round-trip), `yaesu` (Yaesu CAT ASCII + IF information-frame parser + `YaesuMode` 1-F hex chars), `civ` (CI-V binary frame builder/extractor with extra-preamble tolerance, 5-byte LSB-first BCD frequency, `CivMode` mapping). Workspace now at 120 Rust tests (was 77). Clippy clean under `-D warnings`.
- **Rust core — Phase 1 FT8 closure.** `cw-ft8` now wraps the vendored `ft8_lib` C library end-to-end. New `build.rs` compiles the same C sources (`ft8/*.c`, `common/monitor.c`, `fft/kiss_fft*.c`) the Swift CFT8 SPM target uses, with matching `HAVE_STPCPY` define, and generates Rust bindings via `bindgen` over the same headers the Swift module map exports. New safe wrappers `decoder.rs` (monitor → candidates → decode), `encoder.rs` (`ftx_message_encode` + continuous-phase 8-FSK synth), and `wav.rs` (12 kHz mono 16-bit PCM loader) mirror `FT8Decoder.swift` / `FT8Encoder.swift`. Parity gate: new `tests/wav_parity.rs` decodes the same four WAV fixtures Swift uses (`191111_110615/110630/110645`, `websdr_test5`) and asserts at least half of each fixture's `kgoba/ft8_lib` expected messages appear in the output (the same threshold Swift's `FT8DecoderTests` uses). Encoder round-trip test confirms `encode("CQ K1ABC FN42")` decodes back to the same text. Workspace now at 77 Rust tests.
- **Rust core — Maidenhead grid math ported + parity tested.** Second module through the Phase-0 pipeline (after QueryLanguage): `cw-domain::maidenhead` mirrors `MaidenheadConverter.swift` — grid↔coordinate at 4/6/8-char precision, haversine distance, initial bearing, tile bounds, region enumeration with the same 2000-grid cap. Exposed through `cw-ffi` as `maidenheadCoordinate`/`maidenheadGrid`/`maidenheadDistanceKm`/`maidenheadBearing`/`maidenheadIsValid`. New Swift shim `MaidenheadConverter+Rust.swift` adds `coordinateViaRust(_:)` / `gridViaRust(_:precision:)` / `distanceKmViaRust(_:to:)` / `bearingViaRust(_:to:)` / `isValidViaRust(_:)`. New `MaidenheadRustParityTests` (4 tests, ~40 vectors across 8 grids + 7 coordinates + 3 precisions + 4 grid pairs) asserts: coordinate agreement to 1e-9, grid string equality, distance/bearing within 0.01, validity agreement. Workspace now at 68 Rust tests.
- **Rust core — GitHub Actions CI for cw-core.** New `.github/workflows/cw-core-rust.yml` runs `cargo clippy -- -D warnings` and `cargo test --workspace` on Linux for every push that touches `rust/cw-core/`. A second job on `macos-15` runs `./scripts/build-xcframework.sh` and the Swift parity gates (QueryAnalyzer + Maidenhead), uploading `CwFfi.xcframework` as a 14-day artifact. Cached cargo registry/target keeps the OpenSSL/SQLCipher vendored build out of the critical path. Fixed one pre-existing clippy lint (`sort_by` → `sort_by_key` in `query/analyzer.rs`) so the strict `-D warnings` gate is clean.
- **Rust core — Phase-0 UniFFI loop closed end-to-end.** The `cw-core` Rust workspace (59 tests, 6 crates) is now consumed by `CarrierWaveCore` through UniFFI. `cw-ffi` grew a library-mode `uniffi-bindgen` binary target and bumped to `uniffi = 0.31` (fixes a Swift 6.2 duplicate-attribute error in 0.28's generated output). New `rust/cw-core/scripts/{generate-swift-bindings.sh,build-xcframework.sh}` cross-compile a 3-slice `CwFfi.xcframework` (ios-arm64 device, ios-arm64-simulator, macos-arm64_x86_64 universal — staticlibs only, since iOS can't ship arbitrary dylibs and vendored OpenSSL only resolves as `.a`) plus generate the Swift bindings; both stage into `swift/packages/CarrierWaveCore/{Vendored,Sources/CarrierWaveCwFfi}` (gitignored). `Package.swift` gains a `CwFfi` binary target + `CarrierWaveCwFfi` Swift target. New `QueryAnalyzer.analyzeViaRust(_:qsoCount:)` lifts `FfiQueryAnalysis` back into Swift's `QueryAnalysis`. New `QueryAnalyzerRustParityTests` runs 11 vectors through both analyzers and asserts agreement on `usesIndex`, `estimatedCost`, `requiresConfirmation`, `shouldWarn`. First-time setup in `docs/SETUP.md`. Handoff at `docs/plans/2026-06-13-rust-core-handoff.md`.
- **Hardware — CW Bridge JLCPCB assembly metadata.** Every component in `cw_bridge.kicad_sch` now carries a hidden `LCSC` field with a verified JLCPCB part number (68 symbols; jellybean passives map to Basic-library parts, ICs/connectors to Extended). New `hardware/bridge/jlcpcb_export.py` generates `production/cw_bridge_bom.csv` + `cw_bridge_cpl.csv` in JLC's upload format (pad-bbox centroids, Y-up, community rotation offsets for SOT-23/TSSOP/QFN/VSSOP). Parts JLC doesn't stock (Molex vertical USB-A J1, CUI TRS jacks J7/J8, 2×4 header J3) stay on the BOM with a blank LCSC column for hand assembly. Ordering caveats (stock flags, L2 inductor substitution, XIAO consignment check, rotation review list) in `hardware/bridge/production/README.md`.
- **iOS Field — Home hero: the next action is always one tap away.** New `HomeHeroCard` pinned (non-toggleable) to the top of Home. With an open session it shows a single prominent Resume row (active or paused, with the session title); when idle it shows Start Session + Hunt Spots tiles, with the hunter role putting Hunt first. Hunt reuses the hunt-widget deep-link plumbing so first-time Hunter Log setup behaves correctly. The open-session check is one `fetchLimit = 1` fetch, refreshed on tab return, QSO log, and external session start. Files: `HomeHeroCard.swift` (new), `DashboardView+Layout.swift`.
- **iOS Field — `OperatorRole` model (fixes missing type).** The Hunter Log promotion and On Air card changes referenced `OperatorRole` without the type ever being committed — the build was broken on main. New `Models/OperatorRole.swift` defines the persona enum (`activator` / `hunter` / `mixed` / `newcomer`) with the canonical `operatorRole` storage key, display metadata, and `current()` / `persist()` helpers. Roles bias defaults, never hide functionality (policy: `docs/ux-north-star.md` §6).
- **iOS Field — Onboarding persona step.** Onboarding gains a third step after the callsign lookup: "How do you operate?" with four selectable role cards (Activator / Hunter / A Bit of Everything / New to Ham Radio). The selection is optional, persists to `OperatorRole.storageKey`, and immediately drives the existing role-aware defaults (Hunter Log tab landing, On Air card sections). An "Operating Style" menu picker in Settings → My Profile lets the user change it anytime. Files: `OnboardingView.swift`, `OnboardingView+Steps.swift`, `OnboardingView+Actions.swift`, `SettingsView+Sections.swift`.
- **iOS Field — Explore feature gallery.** New "front door" for feature discovery: a curated `ExploreView` listing ~15 marquee features (Tune In, FT8, Brag Sheet, Session Replay, Video Export, Awards, Smart Spots, Hunter Log, …) each with a 5-second pitch, a "find it" navigation hint, a maturity badge where applicable, and an inline enable toggle for hidden experiments (Propagation Check, Weather Radar). Reached from More → Explore Features and a new link on the dashboard Getting Started card. Files: `Views/Explore/ExploreFeature.swift`, `Views/Explore/ExploreView.swift`, `MoreTabView.swift`, `DashboardGettingStartedCard.swift`.
- **Docs — UX North Star.** New `docs/ux-north-star.md` encodes the product rules that keep the app's user journey simple as the feature surface grows: the three-jobs IA model, the naming glossary, the Home-slot rule, the front-door (Explore) rule, the experiment graduation policy, the `OperatorRole` persona system, onboarding-as-first-win, flows-open-light, badge budget, and a new-feature checklist. Linked from the root `CLAUDE.md` Quick Reference and `swift/ios/CLAUDE.md`. `docs/design-language.md` gains a companion "Visual Hierarchy" section (one hero per screen, ≤2 badge types per row, mutually exclusive panels).
- **iOS Field — Hunter Log "new since you looked" divider.** `ActivityLogSpotsList` now anchors a `+N new since you looked` divider above the first already-seen spot when sorted by Recent. A new `@AppStorage("hunterLastViewedSpotTimestamp")` advances on `.onDisappear`; on the next `.onAppear` the boundary is frozen for the viewing session so the divider doesn't slide as each 2-minute poll cycle delivers more rows. The divider is hidden when no prior view exists, when every visible spot is new, or when the user picks a non-temporal sort. Helpers live in `ActivityLogSpotsList+UnreadDivider.swift` (new file). Files: `ActivityLogSpotsList.swift`, `ActivityLogSpotsList+UnreadDivider.swift`.
- **iOS Field — Sessions-tab operator-style affordances.** Extends the `OperatorRole` persona (added in onboarding/Profile, four cases: Activator / Hunter / A Bit of Everything / New to Ham Radio) to the Sessions tab: a one-time `OperatorRolePromptCard` appears above the intent grid for users who skipped onboarding's persona step, and a dedicated `Settings → Logger → Operating Style` entry point writes the same `@AppStorage("operatorRole")` key as `Settings → My Profile`. Activator-focused ordering now comes from the per-type session wizards (`SessionOperationType` — the Activate wizard leads with the activation section), which subsumed the earlier `emphasizesActivation` flag. Hunter role gives the Quick Start card extra prominence (`prefersQuickStart`). Files: `OperatorRole.swift`, `SessionsIntentView+RolePrompt.swift`, `OperatorRoleEditView.swift`, `LoggerDetailSettingsView.swift`, `SessionStartSheet.swift`.
- **iOS Field — "Same as Last Session" quick-start.** Single-tap card above the 2×2 intent grid that bypasses `SessionStartSheet` entirely — calls `LoggingSessionManager.startSession` directly with the most recent finished session's mode, frequency, programs, equipment, power, callsign extras, and operator roster. Park reference is intentionally dropped for prior activations (operators move between parks; starting at yesterday's park is a footgun). Hidden when no finished session exists or when the first-launch tour hasn't run. Files: `SessionsIntentView+QuickStart.swift`, `SessionsIntentView.swift`.
- **iOS Field — Inline "Today's Gear" row.** New section in `SessionStartSheet` between the loadouts strip and the rest of the form that shows the currently-applied radio/antenna/key/mic as chips (with the applied loadout name if any) and taps to open `LoadoutEditSheet` for one-off tweaks. Restores the cheap "swap one piece of gear today" path that the previous loadouts-only design forced through a modal detour. Hidden when no equipment is selected. Files: `SessionStartSheet+Gear.swift`, `SessionStartSheet.swift`.
- **iOS Field — Dashboard "Show more cards" footer.** Dashed-outline row beneath the visible cards on the lean dashboard that opens the customize sheet and lists the hidden categories (e.g. "stats, social, tools"). Replaces the previous discoverability hole where the only signal that more cards existed was the slider icon in the toolbar. Hidden once every available card is visible. Files: `DashboardView+Layout.swift` (`AddCardsFooter`, `showAddCardsFooter`, `hiddenCardSummary`).
- **iOS Field — Simple Logging Mode.** New opt-in toggle (Settings → Appearance → Logging) that mutes the situational chips in the in-session header — operating shift, equipment, duration, space weather, and SDR/radio status — leaving the essentials (callsign, QSO count, park, frequency/band, mode). Keeps the controls bar short and scan-free during a pileup while preserving the full detail for anyone who wants it. Stored in `loggerSimpleMode`; the situational chips are grouped into a single `situationalChips(_:)` builder. Files: `AppearanceSettingsView.swift`, `LoggerView.swift`, `LoggerView+SessionHeader.swift`, `LoggerView+SessionBadges.swift`.

### Changed
- **Server — branded the account verify landing page.** `GET /v1/auth/verify/complete` (the magic-link target) now renders a Carrier Wave–themed page instead of bare `<h1>/<p>` markup: dark gradient backdrop, the real iOS app icon (inlined as a `data:` URI), a purple-tinted card with status icon, kicker, headline, and footer, for both the "Callsign verified" and "Link expired" states. Stays fully self-contained (inline `<style>` + inlined icon, no external fetches) under a tightened CSP (`default-src 'none'; style-src 'unsafe-inline'; img-src data:`); `Referrer-Policy: no-referrer` + `Cache-Control: no-store` unchanged, so the code still can't leak via referrer/XSS. Icon source of truth is `swift/ios/.../AppIcon.png` (downscaled 120px, `server/src/handlers/app_icon.b64`).
- **iOS Field — QSO Rust Store write-cutover (W0), hidden experiment.** In `on` mode, hide/unhide now write the Rust cw-store as the canonical store and project to SwiftData for CloudKit sync; SwiftData stays the system of record for sync, the Rust store becomes authoritative for these writes. `QSOWriteSink` seam + `CwStoreMirror` echo-suppression. `off`/`shadow` behavior is unchanged.
- **iOS Field — QSO Rust Store write-cutover W1 (interactive writes), hidden experiment.** Logging a new QSO and editing one now write the Rust cw-store first/canonically in `on` mode via the same seam (`QSOWriteSink.upsert` / `commitUpsert`); `setHidden` now delegates to the shared upsert path. `off`/`shadow` unchanged.
- **iOS Field — QSO Rust Store write-cutover W2 (bulk writes), hidden experiment.** Bulk hide, group-into-session, and "Delete All Hidden" now write the Rust cw-store first/canonically in `on` mode via `QSOWriteSink` batch upsert/delete. ADIF/LoFi import stay mirror-followed for now (background-context; cw-store-first deferred). `off`/`shadow` unchanged.
- **iOS Field — QSO Rust Store write-cutover W3 (restore + all imports), hidden experiment.** The Hidden-QSOs restore paths (`AllHiddenQSOsView.restoreQSO` / `restoreAllQSOs`) and **every** import write path now write the Rust cw-store first/canonically in `on` mode via `QSOWriteSink`: top-level `importADIF`, `importFromLoFi`, session-targeted `importADIFIntoSession`, and QRZ/POTA redownload. Imports commit through a new `commitImportedQSOs` helper in bounded 500-row chunks (with `Task.yield()` between them) so a large import doesn't block the main thread, then flush any non-QSO leftover (e.g. LoFi activation metadata, session counter). The in-place-update imports surface their mutated rows via `QSOProcessResult.updated([QSO])` so adopted/enriched existing QSOs ride the cw-store-first batch instead of being swallowed by the suppressed seam save. `off`/`shadow` unchanged.
- **iOS Field — On Air card spots condense to a one-line summary.** The dashboard On Air card's inline POTA / SOTA / Friends-on-air sections (up to ~12 rows plus headers) collapse to a single count row ("2 friends on air · 5 POTA · 3 SOTA") for non-hunters — the card is a glance surface and the full rows with badges and tap-to-spot live on the On Air sheet, one tap away (the whole card opens it). Hunters keep the existing "Open Hunter Log" link. The now-dead card-side row builders were deleted; `loadFriendSpots` stays (it feeds the summary and the sheet). Cuts the lean Home scroll roughly in half. Files: `OnAirCard.swift`, `OnAirCard+ActivitySpots.swift`, `OnAirCard+FriendSpots.swift`.
- **iOS Field — Per-type session wizards restored after bad rebase.** The tailored Activate / Casual / Contest wizards (`SessionOperationType`, originally commit `306461e`) were silently dropped when the UX-audit branch was rebased onto a main that never received them. Restored and reconciled: the Activate wizard's program-led ordering subsumes the audit's `shouldShowActivationFirst` role flag (removed along with `OperatorRole.emphasizesActivation`); the audit's shared callsign hero, loadouts strip, and Today's Gear row stay above the wizard sections in every layout. Files: `SessionStartSheet+Wizards.swift` (restored), `SessionStartSheet.swift`, `SessionStartSheet+Sections.swift`, `SessionsIntentView.swift`, `SessionsIntentView+Actions.swift`, `OperatorRole.swift`.
- **iOS Field — Verb-first tab naming pass.** Tab display strings now follow the naming glossary (`docs/ux-north-star.md` §2): Dashboard → **Home** (`house` icon), Logs → **Logbook** (`book.closed` icon), Activity → **Friends**. The Sessions and Map tabs keep their names; `AppTab` raw values, AppStorage keys, and deep-link targets are unchanged, so existing tab orderings and integrations are unaffected. The Friends tab's navigation title follows suit. Files: `TabConfiguration.swift`, `ActivityView.swift`.
- **iOS Field — CW Transcription and Log Scanning graduated from Experiments.** Both alpha features are now stable: `.transcription` and `.logScanning` cases removed from `ExperimentalFeature`, their `ExperimentalBadge`s and `isEnabled` guards deleted. The CW tab (transcription) is no longer opt-in — it's always available and ships hidden-by-default in the tab bar, so users add it from More → Customize. The Logbook's "Scan Handwritten Log" import is now always present. Both keep their Explore cards (moved to the ready-to-use catalog). Files: `ExperimentalFeature.swift`, `TabConfiguration.swift`, `LogsListView+Toolbar.swift`, `RecordingPlayerView.swift`, `ExploreFeature.swift`, `swift/ios/CLAUDE.md`.
- **iOS Field — Awards & Certificates and Brag Sheet graduated from Experiments.** Both beta features are now stable: `.awards` and `.bragSheet` cases removed from `ExperimentalFeature`, their `ExperimentalBadge`s and `isEnabled` guards deleted, and the Sessions tab's Awards link is now always present. Dashboard card visibility (Customize sheet) is unchanged — only the experiment gate is gone. A graduation policy now lives in `swift/ios/CLAUDE.md` + `docs/ux-north-star.md` §5: experiments are reviewed every release, and stable betas graduate by default after 2+ releases. Files: `ExperimentalFeature.swift`, `DashboardLayout.swift`, `SessionsView.swift`, `POTAAwardsDashboardCard.swift`, `DashboardView+BragSheet.swift`, `swift/ios/CLAUDE.md`.
- **iOS Field — More tab gains a "Discover" section.** Explore Features and Propagation Check (when enabled) now live under a persistent Discover header. Files: `MoreTabView.swift`.
- **iOS Field — Hunter Log promoted to the Sessions tab's default landing for hunters.** When `OperatorRole == .hunter` and a Hunter Log is configured, the `.logger` tab lands directly on `ActivityLogView` instead of the 2×2 intent grid, and relabels itself "Hunter Log" / `binoculars.fill` in both iPhone tab bar and iPad sidebar. The intent grid stays one tap away via a new `list.bullet.rectangle.portrait` toolbar item on the Hunter Log. Non-hunter roles see identical behavior to before. The dashboard → spot tap → Hunter Log handoff (`pendingHunterSpot`) is preserved through a one-shot capture in `SessionsTabView.hunterDefaultContent`; `QuickLogSection` gains an `onChange(of: initialSpotInfo?["callsign"])` so a fresh in-place delivery actually re-applies (`.onAppear` only fires once per ActivityLogView instance). `ActivityLogManager.loadActiveLog()` is now internal so `SessionsTabView` can refresh after first-time setup completes via the sibling `SessionsIntentView` manager. Files: `SessionsTabView.swift`, `ContentView.swift`, `QuickLogSection.swift`, `ActivityLogManager.swift`.
- **iOS Field — Dashboard On Air card stops duplicating hunter spots.** When `OperatorRole == .hunter`, the dashboard's POTA / SOTA / Friend spot sections are suppressed in favor of an inline "Open Hunter Log for live spots →" link (reuses the existing `target: "hunt"` widget deep-link plumbing). The Hunter Log spot list is strictly more capable — worked-before badges, dupe partitioning, needs matching, club / SKCC / friend chips — and is now the default destination of the `.logger` tab anyway. Non-hunter roles see the existing sections unchanged. The OnAir *sheet* still surfaces every section on demand. Files: `OnAirCard.swift`, `OnAirCard+ActivitySpots.swift`.
- **iOS Field — Compact callsign hero in session wizard.** `SessionStartSheet+Hero.swift` collapses the ~96pt callsign card to a ~36pt single-line bar when nothing about the operator's identity or location needs attention (callsign set, no prefix/suffix, not club mode, resolved grid, no GPS error). Reclaims the screen real estate above the loadouts strip for established users while keeping the full hero for empty-callsign, club, portable-prefix, and GPS-pending cases.
- **iOS Field — Activation-first wizard ordering for portable ops.** When the operator's role is Activator, programs are already selected, or a map pick handed us a park / SOTA reference, `SessionStartSheet` promotes the activation section above mode and frequency. Park reference is the only field a portable op mutates every session, so it belongs at the top of the first screen, not in section six.
- **iOS Field — Calmer logger: one panel at a time + non-jumping banners.** The seven logger bottom panels (RBN, Solar, Weather, Map, POTA, P2P, WebSDR) plus the Radio panel were each driven by an independent flag and could stack on top of one another. They now route through a single `LoggerView.present(_:)` helper that keeps them mutually exclusive — opening one closes the rest. Separately, the in-session banners (network health, duplicate status, callsign-lookup card / error) now fade in with `.opacity` instead of sliding down from the top edge, so the callsign field no longer jumps under the user's thumb mid-typing. Files: `LoggerView.swift`, `LoggerView+Commands.swift`, `LoggerView+Layout.swift`, `LoggerView+SessionBadges.swift`.
- **iOS Field — Quick Start session setup.** `SessionStartSheet` now opens light: only the four essential sections (Station, Mode, Frequency, Activation) are shown, with Power, Equipment, Gear reminders, SDR, Operators, Attendees, Notes, and Templates collapsed behind a one-tap "More setup options" row. The contest section stays up top only when the operator arrived via the Contest intent (or already picked a contest); otherwise it lives in the advanced group. Validation is unchanged — a callsign (plus any program references) is still all that's required to Start. Files: `SessionStartSheet.swift`, `SessionStartSheet+Sections.swift`.
- **iOS Field — Per-type session wizards (activation / casual / contest).** `SessionStartSheet` no longer shows one undifferentiated form for every intent. A new `SessionOperationType` (`SessionStartSheet+Wizards.swift`) drives three tailored layouts that share the callsign hero, loadouts strip, and station block: **Activate** leads with the program picker (POTA/SOTA/WWFF/TOTA) and keeps the full portable kit — pack checklist, SDR, multi-op operators/attendees — with contest available as an optional add-on for park-during-contest ops; **Casual** strips to the essentials (mode, frequency, power, SDR, notes) with no program/contest/checklist/multi-op clutter so ragchewers get on the air fast; **Contest** leads with the contest picker, keeps power and multi-op operators, and hides the program picker to stay focused. The navigation title now reflects the wizard ("Activate" / "Casual Session" / "Contest"). The Sessions intent grid passes the type through (`startActivate`/`startCasual`/`startContest`); generic entry points (logger "+", map park selection) default to the full-featured `.activation` layout, so their behaviour is unchanged. Replaces the previous shared `setupSections` / `hasContestContext` progressive-disclosure model. Files: `SessionStartSheet+Wizards.swift` (new), `SessionStartSheet.swift`, `SessionStartSheet+Sections.swift`, `SessionsIntentView.swift`, `SessionsIntentView+Actions.swift`.
- **iOS Field — Lighter dashboard by default.** The dashboard now ships lean: only the essential cards (Getting Started, Activity, On Air Now, Sync Services) appear by default, instead of all ~13 cards stacked into a long scroll. Every other card — Statistics, Streaks, Grid Tracker, WAS, Smart Spots, Awards, Brag Sheet, Favorites, Equipment, Friend Activity, Callsign Lookup — is now opt-in from the **Customize Dashboard** sheet, which is reworded as an "add the cards you want" surface (most toggles start off; "Reset to Default Layout" restores the lean set). Existing users who had already customized their dashboard keep their exact layout; the lean default only applies when the dashboard has never been customized (empty `dashboardHiddenCards`). The lean state writes a full materialized hidden set on first toggle so untouched cards stay hidden. Files: `DashboardLayout.swift` (`essentialDefaults`, lean-aware `isCardVisible`, `setCardVisible` materializer), `DashboardCustomizeSheet.swift`.

### Fixed
- **iOS Field — Removed QRZ API keys no longer resurrect.** Swiping Remove on a QRZ account in Settings → QRZ Logbook deleted the callsign mapping, but the legacy single-key Keychain entries (`qrzApiKey` / `qrzCallsign`, kept in sync for CW Sweep / widget compat) were left behind whenever no primary mapping remained. On the next visit `getCallsignMappings()` hit its legacy auto-migration path and re-created the mapping from the stale key, so the "removed" account reappeared. `saveCallsignMappings` now deletes the legacy keys when the new list has no primary, and `removeCallsignMapping` also drops the callsign's bookId map entry. Files: `QRZClient+Mappings.swift`.
- **iOS Field — Landscape dashboard re-balances after the lean default.** Follow-up to the lean dashboard default: `TwoColumnLayout`'s split index was fixed to the count of visible cards from a hard-coded "left group" (`gettingStarted, activity, onAir, friendActivity, callsignLookup`), so a fresh install — Activity + On Air + Sync Services — put two tall cards on the left and a single short card on the right, leaving the right half of landscape nearly empty. `leftColumnCardCount` now splits at the midpoint of all visible children (floor, so the right column carries the extra item when the count is odd), and walks back if it would end the left column on a section label so "Stats & Awards" / "Your Data" headings stay anchored to their group. Visible-child order is exposed via a new `visibleChildKinds` mirror of `adaptiveDashboardContent`. Files: `DashboardView+Layout.swift`.

### Removed
- **iOS Field — Four experiments retired (Events, Activation Recommendations, Speech to Text, Horizon Survey).** All four were alpha experiments that hadn't earned a path to stable, so they're deleted rather than left as zombie flags (graduation policy: `docs/ux-north-star.md` §5). Removed the enum cases from `ExperimentalFeature` plus every feature view, service, model, and Explore card: **Events** also drops the gated Events tab (`AppTab.events`, all tab-config/ContentView/MoreTabView wiring) and `Models/EventTypes.swift` + `ActivitiesClient+Events.swift`; **Recommendations** drops the Sessions "Suggest a session" link, `RecommendationEngine`/`RecommendationContextBuilder`, and the `Recommendation*` models; **Speech to Text** drops the logger phonetic-mic button, `PhoneticSpeechService`, and `PhoneticInterpreter` (the shared `NATOPhonetics` table stays — still used by the callsign card); **Horizon Survey** drops the LIDAR capture views and `HorizonProfile`. Files across `swift/ios` and `swift/packages`.
- **iOS Field — Dead stat-explanation popover removed.** `StatExplanationPopover` / `ActivationExplanationPopover` (a second, lighter "how this number was derived" surface) were defined but never instantiated anywhere — `StatExplanationSheet` is the only explanation surface actually used. Deleted `StatExplanationPopover.swift` so there's one explanation path, not two.
- **iOS Field — "Report Inaccuracy" removed from dashboard glance surfaces.** The per-stat long-press "Report Inaccuracy" action (which generated a diagnostic JSON bundle) is gone from the dashboard stats grid (`DashboardIsolatedCards.swift`) and the stat-detail drilldown rows (`StatItemRow.swift`) — it was cognitive noise on a glance surface and signalled distrust in the app's own numbers. The "What's This?" explanation remains on both. The full reporting flow (`ReportInaccuracyView`) is unchanged and still reachable from the deeper award screens (WAS 250, POTA Awards).

## [1.93.0] - 2026-05-30

### Added
- **iOS Field — Contest as a first-class Sessions intent (CAR-276 PR2).** The Sessions tab's 2×2 intent grid is now `Activate / Hunt / Casual / Contest` — replacing the previous `Activate / Hunt / Casual / Suggest`. Tapping Contest presents `SessionStartSheet` with the contest picker auto-presented on first appearance (when no `loggerDefaultContestId` is set); returning contesters with a remembered contest get one-tap entry. The Suggest intent (gated by `.recommendations`) demotes to a secondary "✨ Suggest a session →" link below the grid when the experiment is enabled, so the primary grid stays uncluttered for the 99% of operators who haven't opted in.
- **iOS Field — Richer contest picker inside session start and QSO edit.** The thin `ContestPickerView` is replaced by `ContestCalendarView` operating in a new picker mode (`onSelectDefinition` callback). The picker presents the full calendar/catalog browser — Live-now section, schedule captions, month/week/day modes — so the operator can both browse and select in one place. Catalog rows become tap-to-select Buttons in picker mode; calendar event taps still open `ContestDetailSheet` for info. A Cancel toolbar item is added in picker mode via `@Environment(\.dismiss)`.
- **iOS Field — `SessionLifecycleAPI` protocol (CAR-276 PR1).** Cross-platform session lifecycle vocabulary in `CarrierWaveData/Protocols/` (active session getter + pause/resume/finish verbs). iOS `LoggingSessionManager` conforms; macOS will gain its own conformer in a later PR. Zero user-visible change.
- Foundation for radio macros: shared step schema, code-generated Swift + Rust verifier with raw-bytes opcode decoding, typed `RadioMacroStep` enum, strict template engine, RIT/XIT moved to vendor catalog (CAR-268)
- Radio macros persistence + executor wiring (CAR-269): `RadioMacro` SwiftData model joins the existing `CloudSyncJournalEngine` for iCloud sync (with `cloudDirtyFlag` outbound + capability/registry/tombstone columns); `.cwmacro` UTI registered on iOS and macOS for AirDrop/Files/Finder open-in; `MacroSpecHash` (SHA-256 of canonical steps JSON) for raw-bytes acceptance gating; region-aware `BandPlan` tables (US, IARU R1/R2/R3) with synchronous loader; `MacroSafetyGate` async pipeline (verifier → protocol-match → post-substitution band-plan → TX policy) returning allow/confirmation/refuse; `MacroExecutor` now releases PTT on the success path too (was already releasing on failure); `RadioSessionMacroSink` (iOS) and `MacRadioSessionMacroSink` (macOS) actor adapters bridging `MacroExecutorSink` to the live `RadioSession`; `MacroImportCoordinator` validates incoming `.cwmacro` documents with provenance routing and capability-dominance checks.
- **Server — Radio macros server registry (CAR-271).** Activities server gains the `/v1/macros*` surface for the macros catalogue. New `041_macros_registry.sql` schema covers `macros` (slug-unique, version-bumped on conflict), `macro_versions` (per-version spec history), `macro_reports` (Phase 2), `macro_tombstones` (slug propagation list), `macro_run_events` + `macro_run_aggregates` (telemetry with 90-day raw retention rolled into daily success/failure roll-ups). Public reads filter `status='approved'`: `GET /v1/macros` with `tag/applies_to/search/max_format` filters, `GET /v1/macros/:slug` returning the full `RadioMacroDocument`, `GET /v1/macros/:slug/versions`, `GET /v1/macros/versions?slugs=` returning `{ version, format }` per slug for bulk update checks, and `GET /v1/macros/tombstones?since=` for poll-based withdrawal propagation. Authenticated `POST /v1/macros/:slug/run-event` rate-limits to 60/min/token via `governor::RateLimiter::keyed` and stores only `device_hash = HMAC-SHA256(TELEMETRY_HMAC_KEY_<YYYY-MM-DD>_<MACROS_TELEMETRY_SECRET>, "<participant_id>:<slug>")` — daily+per-slug rotation, never reversible to a user. Admin endpoints (POST / GET / PUT / PATCH / DELETE under `/v1/admin/macros`) run every write through the slug + tag + band-plan validators and the Rust verifier; rejections return 400 with the issues serialized. Verifier hand-written core in `server/src/macros/verifier.rs` mirrors Swift `MacroVerifier`, consuming the codegen-emitted `verifier_generated.rs` plus opcode tables loaded via `include_str!` from the Swift package's `Resources/macro-opcodes/` (one source of truth for both languages); a shared fixture corpus (`macro-verifier-cases.json`) replays through both verifiers so CI catches drift. New CI-V opcode `21` entries (RIT freq / RIT on-off / XIT on-off) added to the shared `civ.json` so non-transmit control commands aren't pessimistically floored at `transmits=true`. Standalone `Tools/cwa/` Rust crate ships the admin CLI (`cwa macros sync <dir>` walks `.cwmacro` files and POSTs each; `cwa macros withdraw <slug>` PATCHes status; `cwa macros list [--status]`; `cwa macros verify <file>` offline shape check), configured via `CWA_BASE_URL` + `CWA_ADMIN_TOKEN`. Seven starter `.cwmacro` documents shipped under `server/seed_macros/` (qsy-to-spot, ic705-gps-quick-tx, ft991a-voice-memory, pota-hunter-cw, power-profile-mobile, k3-tuner-cycle, rit-clear-center); a `macros_seed_corpus` test guard fails CI on accidental schema break. Ansible `activities_server` role gains `tasks/seed_macros.yml` post-deploy step that reads each starter on the controller and POSTs idempotently to the running server with the admin token from vault. `aggregators::macros_retention` background task sweeps daily (`MACROS_RETENTION_INTERVAL_HOURS`, default 24), aggregating raw events into `macro_run_aggregates` and deleting events older than `MACROS_RETENTION_RETAIN_DAYS` (default 90), both halves in one transaction. Refactored `server` from binary-only to bin + thin `lib.rs` facade so integration tests can call handlers directly. Test coverage spans verifier unit + shared corpus, db layer, public endpoints, telemetry (including the 60/min cap), admin flow, seed corpus, retention sweep, and an end-to-end seed → admin POST → public GET round-trip — 144 tests total.
- **iOS Field — Radio macros editor (CAR-270).** User-facing surface for the radio macros feature, gated by `ExperimentalFeature.radioControl` and reached via Settings → Experiments → Radio CAT Control → Macros. `MacrosLibraryView` exposes Mine / Browse / Updates segmented tabs (Browse + Updates are placeholders pending Plan E); the Mine tab uses `@Query` over `RadioMacro` with swipe-to-delete (tombstones rather than hard-deletes so iCloud sync survives) and swipe-to-duplicate. `MacroDetailView` is the read-only summary with capability chips, applies-to protocols, args, and a human-readable step list with Run / Edit / Export menu. `MacroEditorView` splits across four sections (header / capabilities / args / steps): SF Symbols icon picker, tags chip editor, applies-to multi-protocol toggles, 5 capability toggles with a "Remove conflicting steps" prompt when disabling a toggle whose steps still require it, mandatory min/max bounds on frequency arguments, reorderable swipe-to-delete steps, and a bottom safe-area `MacroVerifierIssuesBanner` whose error issues block Save via `MacroEditorModel.canSave`. Eleven per-kind step editors under `StepEditors/` — `MacroStepKindPicker` groups by intent with safety chevrons on TX kinds; `FrequencyStepEditor` is unit-aware (Hz / kHz / MHz) with common-band quick picks; `CWStepEditor` previews template substitution live against `MacroContext.preview` with tap-to-insert tokens; `RawBytesStepEditor` is the danger surface with a permanently-visible red warning banner and live hex validation; `VendorCommandPickerView` drives off `RadioCommandCatalog.shared`. `MacroRunSheetView` surfaces pre-flight `MacroSafetyGate` decisions (orange for confirmation, red for refusal), per-type arg prompts, a streaming executor log with per-kind iconography, and an outcome banner; cancellation is cooperative via `Task.cancel`. `MacroAppSafetyEnvironment` wires `MacroSafetyEnvironment` against `RadioService`, `UserRegionProfile` (mapped to R1/R2/R3 region strings), and a `macroGlobalInhibitTx` UserDefaults key (off by default; settings surface ships later). `MacroImportSheet` runs `MacroImportCoordinator.evaluate` on appear, surfaces provenance with non-registry sources highlighted, and gates raw-bytes installs behind a "Trust raw bytes?" alert. Three `@Observable` view-models in CarrierWaveData (`MacroLibraryModel`, `MacroEditorModel`, `MacroExecutionModel`) carry the state and are reusable from CW Sweep when Plan G lands.
- **Website — Public macros catalog at carrierwave.app/manual/macros and per-macro pages at /manual/m/<slug> (CAR-273).** Adds a Hugo section to the manual that surfaces the activities-server registry to the open web. `scripts/sync-website-macros.sh` runs ahead of `hugo --gc --minify` in the deploy pipeline: it fetches `GET /v1/macros` into `data/macros.json` and one Hugo content file per slug from `GET /v1/macros/:slug` as JSON front matter; files for slugs no longer in the upstream catalog are pruned so withdrawals propagate without a separate tombstones pass. `layouts/macros/list.html` renders the catalog as a card grid with client-side search / radio-family / transmits-only filters; `static/js/macros-live-refresh.js` re-fetches `/v1/macros` at page load and replaces the grid with the latest data (the build-time output is the no-JS fallback). `layouts/macros/single.html` renders each macro's description (plain text only — no Markdown), capability chips, a human-readable step list (covering all 11 `RadioMacroStep` kinds — `setFrequency` → "Tune to 14.0570 MHz", `setPTT` → "Press PTT", `rawBytes` flagged with a raw-bytes warning), an args table with min/max bounds, an "Open in Carrier Wave" `cwmacro://import?slug=…` deep-link button, and OG / Twitter card metadata served via a project-level override of the theme's `head.html` partial. Catalog artifacts are gitignored — the live server is the only source of truth.
- **iOS Field — Radio macros Browse + update propagation + opt-in telemetry (CAR-272).** Final macros plan stitches the iOS app to the activities-server registry stood up in CAR-271. New `MacrosRegistryClient` actor (CarrierWaveData) wraps the five public endpoints — `GET /v1/macros` (search/filter list), `GET /v1/macros/:slug` (full document), `GET /v1/macros/versions?slugs=` (bulk version check), `GET /v1/macros/tombstones?since=` (since-cursor delta), and authenticated `POST /v1/macros/:slug/run-event` — with a `RegistryAuthTokenProvider` closure so the package never has to know about the iOS Keychain. `MacrosRegistryService` actor runs a 30-minute foreground-debounced poll on every `scenePhase = .active`, comparing each installed `RadioMacro.registry.registryVersion` against the server's `versions` map, stamping `tombstoned` + `tombstoneReason` onto any local row whose slug appears in the tombstones response, and advancing a persisted lastSeen watermark. iOS `MacrosRegistryHolder` is the `@Observable` singleton wrapper that owns the actor and republishes its Sendable `MacrosRegistrySnapshot` to SwiftUI views. Browse tab is now real: server-paged list with 250 ms search debounce, pull-to-refresh, an "Installed" capsule when the local library already has the slug, and a `MacroBrowseDetailView` that fetches the document, shows the same sections as `MacroDetailView`, and installs through a new `MacroImportCoordinator.evaluate(spec:provenance:)` overload running the same verifier + capability-dominance gate as the `.cwmacro` import path. Updates tab lists installed-and-stale macros (vLocal → vRemote) and opens `MacroUpdateReviewView`, which renders a section-per-field diff produced by the new `RadioMacroSpecDiff` utility (capabilities expand to one row per flag; steps roll into added/removed/changed buckets) with three actions: Update, Keep My Version, View on carrierwave.app. Raw-bytes acceptance is gated through `UserDefaultsRawBytesAcceptanceStore` keyed on `<specId>:<MacroSpecHash.canonical(spec)>`; the apply path invalidates the stored hash before mutating the row so the safety gate re-prompts on the new bytes. Tombstoned macros stay visible in the Mine tab with server-originated reasons (`withdrawn`, `admin_removed`, `author_deleted`) rendered as an orange capsule on `MacroRowLabel`, Run/Edit disabled, and a Registry Status section in `MacroDetailView` offering "Delete from My Library" (permanent) and "Keep as Read-only Artifact" actions. Locally-deleted rows still hide. Optional run telemetry: `MacroTelemetryReporter` posts to `POST /v1/macros/:slug/run-event` only when `UserDefaults["macrosTelemetryOptIn"]` is true (default false) and only for registry-installed macros; `RegistryRunEventBody.from(outcome:)` strips error messages down to the first 4 alphanumeric/dash tokens (capped at 64 chars) so user-typed callsigns/frequencies never leave the device. A Settings → Experiments → Radio CAT Control toggle exposes the opt-in with copy naming exactly what's shared. 30 new package tests cover the client, service, diff utility, raw-bytes store, tombstone reason parser, and wire-body builder.
- **Macros — Yaesu CAT vendor catalog.** New `Resources/RadioCommands/yaesu-cat.json` shipping 15 common Yaesu CAT commands (VFO-A/B tune, mode, PTT, power, split, RIT/XIT enable + clear, noise blanker, preamp/IPO, attenuator, AGC, VFO swap, A→B copy). Coverage targets the FT-857/897/817/991(A) and FT-DX10/710/DX101 generations. The catalog is loaded at app launch alongside the existing `civ-icom.json` and `kenwood-elecraft.json`.

### Changed
- **iOS Field — Sessions Intent Picker graduated from Experiments (CAR-276 PR2).** The `.sessionIntentPicker` experimental flag has been removed; `SessionsIntentView` is now the canonical landing for the Sessions tab whenever there's no active session. The legacy `SessionsIdleView` is retired in the same release. The migration code at `TabConfiguration.unhideLoggerOnce()` continues to ensure users who hid the tab when it was still called "Logger" see it reappear as "Sessions" on first launch of v1.93.0.

### Fixed
- **iOS Field — "Add Step" no longer dismisses the macro editor.** `MacroEditorView+StepsSection` attached two `.sheet` modifiers (`addStepPicker`, `editStepTarget`) directly to the `Section` inside the editor's `Form`. With `MacroEditorView` itself presented as a sheet from the library / detail views, presenting one of these nested sheets collapsed the parent presentation instead of stacking — the editor closed entirely on tap. Both sheets are now hoisted onto the root `Form` in `MacroEditorView.body` so they stack above the editor as intended.
- **Macros — Vendor command catalog now bootstraps at app launch.** `RadioCommandCatalog.shared.loadBundled()` was only ever called from unit tests, so the shared catalog stayed empty in both `Carrier Wave: Field` and `CW Sweep` — the Vendor Command step picker rendered the "No catalog commands loaded" empty state regardless of selected protocol. Added the call to `CarrierWaveApp` (after `MacrosRegistryHolder` configure) and to `CWSweepApp`'s startup `.task` so the bundled CI-V, Kenwood/Elecraft, and Yaesu catalogs are registered before the editor ever opens.
- **Macros — Tapping a vendor command in the picker now actually selects it.** `MacroStepEditorSheet` built the picker's `commandId` / `args` bindings from `case let .vendorCommand(commandId, args) = draft` pattern captures. Inside a single tap, `VendorCommandPickerView` writes both bindings in sequence (`commandId = command.id`, then `seedDefaults` writes the args binding), and the second setter's closure captured a stale `commandId` from the pre-tap render — so the args write clobbered the freshly-set id back to its previous value and the row never registered as selected. Both bindings now read from `draft` directly via `if case let … = draft`, so successive writes within a single tap compose instead of racing.
- **Macros — Yaesu vendor commands now encode as ASCII CAT.** The payload encoder in `RadioCommandCatalog` and `MacroExecutor` lumped `.yaesu` in with `.civ` / `.flex` through `parseHexBytes` (vintage FT-1000-style binary CAT) — incompatible with the ASCII command syntax used by every modern Yaesu rig (FT-857 onwards). Yaesu now routes through `Data(resolved.utf8)` for payload encoding and shares Kenwood's `;` terminator on the framing path, matching the new `yaesu-cat.json` template format. Vintage binary CAT can still be sent via the `rawBytes` step.
- **Macros — Install button shows its icon and step rows list real vendor-command arguments.** The registry `MacroBrowseDetailView` install button rendered as a bare, content-sized "Install" pill: `.frame(maxWidth: .infinity)` was applied to the `Button` *outside* `.buttonStyle(.borderedProminent)`, so the prominent capsule shrank to fit the label and dropped the leading `square.and.arrow.down` glyph. The frame now sits on the label content with an explicit `.labelStyle(.titleAndIcon)` and `.controlSize(.large)`, so the button fills the row and always shows the download icon. Separately, vendor-command step summaries showed only an opaque `kw.elecraftMenuSet (2 args)` count; a new shared `RadioMacroStep.formatVendorArgs(_:)` (keys sorted for stable output) renders the actual values — `kw.elecraftMenuSet(menu=1, value=on)` — across the iOS step list, the CW Sweep step list, and the registry update diff.

### Removed
- **iOS Field — Standalone Contests destination (CAR-276 PR2).** The Activity-tab `Community → Contests` community row that navigated to `ContestCalendarView` is removed; contests are now reached exclusively through the Sessions tab's Contest intent. The dashboard `OnAirSheet`'s `ContestsSectionView` keeps showing active and upcoming contests for at-a-glance awareness but drops its "See All" / "See full calendar" navigation links. Per-contest detail sheets still open as before from row taps. The dead `ContestsBrowserView` struct (an unused duplicate of `ContestCalendarView`'s catalog mode) is deleted; its row/entry/caption helper types remain in the same file. iOS `ContestPickerView.swift` (the thin server-catalog list picker) is deleted — replaced by `ContestCalendarView` in picker mode.

## [CW Sweep 0.13.0] - 2026-05-28

### Added
- **CW Sweep — Toolbar control for the active session.** New `SessionToolbarControl` sits next to `LayoutPicker` in the workspace toolbar when the Logger sidebar item is selected. The control shows a red record indicator + session label (park / SOTA / WWFF / contest id / callsign) and exposes End and Pause via a menu. The same actions are mirrored under an "Active Session" section in the Cmd+K command palette. `WorkspaceView` owns a single `MacSessionManager` so both surfaces stay in sync via `.didChangeLoggingSession` notifications. Previously the only way to stop a session was to navigate back to the Sessions landing strip.
- **CW Sweep — Retire standalone Contests sidebar item + relocate Cabrillo (CAR-276 PR8).** `SidebarItem.contests` is removed from the enum, the sidebar, and `ContentAreaView`'s dispatch; `ContestRootView.swift` is deleted. Cabrillo export survives as a `Sessions` panel toolbar item on the new `ContestSessionContainer` — when an active contest session is operating, the toolbar shows "Export Cabrillo" wired through the existing `ContestManager.cabrilloText(clubName:email:)` API and `.fileExporter`. Contest discovery still goes through the Contest intent on the Sessions landing → existing `ContestPickerView`. The two other Q14 entry points (session row context menu, end-session prompt) are deferred to PR9 polish since they require past-session Cabrillo re-export support that the current `ContestManager` doesn't offer. Saved layout configs that reference the removed `.contests` raw value will fail to deserialize and the sidebar falls back to its default selection — acceptable transitional behaviour.
- **CW Sweep — Contest-aware Sessions panel (CAR-276 PR7).** When the active session has `contestId` set, the Sessions sidebar now dispatches to the new `ContestSessionContainer` — which loads the matching `ContestDefinition` from the server catalog, spins up a `ContestManager` bound to the session, and renders the existing `ContestOperatingView` (score, exchange entry bar, band breakdown, recent QSO list). Non-contest sessions continue to render the standard `CustomLayoutView`. PR7 is a chrome-dispatch step only: the Q9 commitment to unify the parser (`ParsedEntryView` accepting an optional `ContestExchange` so the standard quick-entry box drives contest exchanges too) is intentionally deferred to a follow-up to keep the existing run/mult tagging, off-time tracking, and band-change accounting code paths untouched. Known limitation: `ContestManager.start()`'s `resumeOrCreateSession` may double-create a session if its resume predicate doesn't match the row started via `MacSessionManager`; PR8 audits and consolidates.
- **CW Sweep — Contest intent (CAR-276 PR6).** The Contest card on the Sessions landing now opens the existing macOS `ContestPickerView`; selecting a definition starts a `LoggingSession` with `contestId` / `contestCategory` / `contestPower` populated from the definition's defaults via `MacSessionManager`. Picked id is persisted to `@AppStorage("loggerDefaultContestId")` (shared key with iOS PR2) so the future PR9 polish can implement returning-contester bypass. The existing `ContestRootView` sidebar item is still present and functional — PR8 retires it once the contest-aware logger entry (PR7) is in shape. Contest discovery from the dashboard `OnAirSheet` and any other ambient surfaces remains unchanged.
- **CW Sweep — Silent backfill of loose QSOs (CAR-276 PR5).** New `SessionBackfillService` in CarrierWaveData runs at CW Sweep launch and groups all `loggingSessionId == nil` QSOs into synthetic per-UTC-day `LoggingSession` records titled `"Pre-unification log · YYYY-MM-DD"`. After PR5 the data invariant "every QSO has a session" holds for all operator-side records, so consumers of QSO data can stop defensively handling the loose case. Idempotency is keyed on `NSUbiquitousKeyValueStore` (with `UserDefaults` fallback for no-iCloud users) so a second device upgrading after the first device finished backfill skips the work. A kill switch (`disableSessionBackfill` `UserDefaults` flag) is available for users who'd rather opt out; PR9 will expose it in the Experiments hub. Backfilled sessions are real `LoggingSession` records — users can rename, merge, split, or delete them like any other session. iCloud sync re-uploads them naturally via the existing `cloudDirtyFlag` plumbing.
- **CW Sweep — Session lifecycle wiring (CAR-276 PR4).** The new `MacSessionManager` (in `Services/Session/`) is the macOS-side session lifecycle service — slim sibling of iOS `LoggingSessionManager`, conforms to the cross-platform `SessionLifecycleAPI` from CarrierWaveData. Activate / Hunt / Casual intent taps on the Sessions landing now present a real `MacSessionStartSheet` (callsign, mode, frequency, activation type, optional POTA/SOTA/WWFF reference) instead of the PR3 placeholder; on Start the manager creates a `LoggingSession`, posts `cwDidChangeLoggingSession`, and `SessionsSidebarRoot` swaps the landing for `CustomLayoutView`. The Continue strip's Resume / Finish actions are now wired through the manager. iOS-style side effects (Live Activity, POTA spot polling, WebSDR auto-start, TOTA GPS tracking) are deliberately excluded — they don't apply to CW Sweep's desktop workflow. Contest intent still routes through the legacy `ContestRootView` until PR6 lands the unified picker. Auto-Casual-on-first-QSO from `ParsedEntryView` is deferred: `SessionsSidebarRoot` hides `ParsedEntryView` whenever no session is active, so the codepath isn't reachable from this PR; PR9 polish will revisit the landing UX (quick-log strip vs current intent-only).
- **CW Sweep — Sessions sidebar landing (CAR-276 PR3).** The `.logger` sidebar item is renamed "Sessions" and now dispatches based on session state: when no `LoggingSession` is active it renders the new `SessionsLandingView` — a 2×2 intent grid (Activate / Hunt / Casual / Contest) mirroring iOS `SessionsIntentView`, with a `Continue` strip of paused sessions below. Existing in-progress contest sessions created by `ContestManager` populate the strip automatically (they're the only sessions CW Sweep creates today). When a session is active, the sidebar swaps to the live logger (`CustomLayoutView`) so the contester operating workflow is unchanged. Intent card actions and the resume/finish buttons are stubbed in PR3 — they show a "Coming in PR4" placeholder. PR4 will wire the macOS session-start sheet and a cross-platform-conforming session manager. The new `SessionsSidebarRoot` uses `FetchDescriptor`-based queries per macOS performance rules; refresh is timer-free and reacts to a new `cwDidChangeLoggingSession` `Notification.Name` that PR4 will start posting.
- **CW Sweep — Radio macros parity (CAR-274).** Brings the macros experience to the macOS companion app. New Settings → Macros tab and a dedicated `Macros` Window (Cmd+K palette → "Macros…") host `MacrosLibraryView` with the segmented Mine / Browse / Updates tabs ported from iOS. `MacroDetailView`, `MacroEditorView` (header / capabilities / args / steps in extensions, 11 step editors, kind picker, step editor sheet), `MacroBrowseDetailView`, `MacroUpdateReviewView`, and `MacroImportSheet` mirror the iOS Plan C/E shapes, swapping iOS-only modifiers (`navigationBarTitleDisplayMode`, `keyboardType`, `textInputAutocapitalization`, `EditButton`, `.insetGrouped`) for macOS equivalents (context menus, `.formStyle(.grouped)`, native toolbar placements). `MacroRunWindowController` opens runs in their own non-modal `NSHostingView`-backed `NSWindow` with a static registry retaining live windows until they close, so multiple macros can be in flight at once. Finder drop is wired via a `FinderDropTarget` view modifier accepting `app.carrierwave.macro` and `public.json` UTIs and routing the bytes through `MacroImportCoordinator` with `.files` provenance. New `cwmacro://import?slug=…` custom scheme + `applinks:carrierwave.app` associated domain land in `Info.plist` / `.entitlements`; `MacroURLHandler` parses both, fetches the document via the shared `MacrosRegistryHolder.client`, and publishes through `MacroURLBridge` (`@MainActor @Observable`) which the drop target observes so a single `MacroImportSheet` surface covers drops and URL launches. macOS `MacroAppSafetyEnvironment` reads protocol from `SharedEnvironment.shared.radioManager` and IARU region from a `userIARURegionOverride` UserDefaults key (R2 default until callsign-derived region ports over). `MacrosRegistryHolder` is configured at app launch alongside `CloudSyncService` and runs auth-less against the public registry endpoints.

### Changed
- **CW Sweep — Polish + release v0.13.0 (CAR-276 PR9).** Bumps `MARKETING_VERSION` to `0.13.0` and `CURRENT_PROJECT_VERSION` to 16. Adds the corresponding macOS `WhatsNewEntry`. Backfilled "Pre-unification log" sessions in the Continue strip now render with an `archivebox` icon and the synthetic `customTitle` so operators can tell them apart from operator-started sessions at a glance. New `docs/features/sessions-unification.md` documents the initiative end-to-end (outcome, PR sequence with commit hashes, design context pointer, known follow-ups).

### Fixed
- **CW Sweep — Contester layout no longer drifts as the log fills.** The contester operating layout now pins the score panel to a slim fixed slot in the trailing column so it stays put regardless of QSO count.
- **CW Sweep — Manual frequency/mode changes now stick when no radio is connected.** `RadioManager.tuneToFrequency(_:slot:)` and `setMode(_:slot:)` guarded on a live `RadioSession` and silently returned `false` when nothing was connected, so every manual tune path (Cmd+Shift+P radio palette, band-map click-to-tune, vim `:freq`) was a no-op without a radio — `radioManager.frequency` never moved and logged QSOs never inherited the operator's chosen frequency. Both now fall back to recording the change in app state (the focused slot's `RadioSlotState` plus the legacy mirrored fields read by the logger, status bar, and band map) and return `true`. In the Activator role, mid-session QSYs made without a radio are also persisted back onto the active `LoggingSession` so a session reload no longer restores the stale start-of-session frequency.

### Removed
- **CW Sweep — `SidebarItem.contests` and `ContestRootView` (CAR-276 PR8).** Replaced by the Contest intent on the Sessions landing + `ContestSessionContainer` (which hosts `ContestOperatingView` and the Cabrillo toolbar). `ContestBrowserView`, `ContestEntryBar`, `ContestOperatingView`, `ContestPickerView`, etc. all remain — they're rendered from `ContestSessionContainer` instead of `ContestRootView`.

## [1.92.0] - 2026-05-22

### Added
- **iOS Field — RST Sent auto-advances to RST Received once full (CAR-197).** When the user types into the RST Sent field, focus jumps to RST Received once the value reaches the mode's expected length: 3 chars for CW/digital (599), 2 for phone (59). Length comes from the existing `isCWMode` derivation, so the threshold tracks the session mode without a separate setting. Only fires when the value's length crosses the threshold upward, so deleting characters or shrinking the field doesn't re-trigger focus.
- **iOS Field — Hunter spot monitor now rotates through 6m FT8 alongside HF.** PSK Reporter hunter fetch picks one band per poll cycle from a fixed list; 6m (50.313 MHz dial ±3 kHz) joins 20 / 40 / 15 / 10 / 17 so VHF sporadic-E openings show up in the hunter spot stream without the user needing to switch sources.

### Changed
- **iOS Field — Activity grid taps open a unified day summary.** Replaces the hunter-only `DailySummaryView` (reachable only from `RecentQSOsSection`'s "See All") with `DaySummaryView` in `Views/Dashboard/`. Tapping any non-empty `ActivityGrid` cell now pushes the new view; the old tap-popover (date + activation/hunter counts) survives as a long-press context-menu peek. Day content: hero with date + QSOs/Sessions/<DXCCs|States|Bands|Modes> stat strip and band/mode pills; insights carousel (map + states mosaic) broadened from hunter-only to all-day QSOs; band timeline; **Sessions** section listing every `LoggingSession` that overlaps the UTC day as a rich card sorted by first sliced QSO. Each session card drills into `SessionDetailView`. Hunter log and orphan ("loose") QSOs appear as inline-expandable virtual cards. Sessions that straddle UTC midnight are sliced on both days with a `continued` / `continues` / `continues & continued` chip. New background pipeline: `DaySummaryDataActor` pages QSOs and overlapping sessions for the day in batches of 1000 (no hard cap on total) and emits a Sendable `DaySummarySnapshot`, honouring the no-parallel-full-table-scans rule. Files added: `Services/DaySummaryDataActor.swift`, `Services/DaySummarySnapshot.swift`, `Views/Dashboard/DaySummaryView.swift`, `Views/Dashboard/DaySummaryView+Insights.swift`, `Views/Dashboard/DaySummaryView+Sessions.swift`, `CarrierWaveTests/DaySummaryDataActorTests.swift` (12 cases). Removed: `Views/ActivityLog/DailySummaryView.swift` and its insights extension.
- **iOS Field — Hunter Log day summary now mirrors the session detail layout.** `DailySummaryView` switched from an ad-hoc `ScrollView` of grey-card panels to a `List`-based layout matching `SessionDetailView`: a Tier 1 hero (full date + callsign, monospaced stat strip showing QSOs / DXCC / States with bands/modes as a fallback, FlowLayout band & mode pills with parenthesised counts), a swipeable Insights carousel (tappable map preview with a "{matched} of {total}" chip and a US states mosaic when domestic QSOs are present — both push to full-screen detail views on tap), the existing band timeline, and the QSO list with station/grid dividers. Extracted `SessionStatStrip` / `StatStripCell` / `CountedPill` into `Views/Components/` so session and day summaries render from one set of primitives — touching either screen no longer drifts the other. `DailySummaryView+Map.swift` was replaced by `DailySummaryView+Insights.swift`, the dead `statStrip` / `statCell` / `countedPill` helpers were removed from `SessionDetailView+Hero.swift` and `+Components.swift`.

### Fixed
- **Server — per-IP rate limit, CORS allowlist, and request body cap (CAR-143).** `tower-governor` global layer at 10 req/s burst 20 per IP, with a tighter per-route layer on `POST /register` at 1 req/min burst 1 (the abuse vector the production-readiness audit flagged). `CorsLayer` dropped from `allow_origin(Any)` to an explicit allowlist (`https://carrierwave.app`, `https://activities.carrierwave.app`, `http://localhost:5173` for Vite dev) with methods restricted to GET/POST/PUT/DELETE/OPTIONS and headers to Authorization + Content-Type — native iOS/macOS clients bypass CORS so they're unaffected. `DefaultBodyLimit::max(1 MiB)` caps request bodies globally so a malicious caller can't pin memory streaming gigantic JSON; upload endpoints can override per-route. Plus explicit per-field length validation on `RegisterRequest` (callsign ≤ 16, deviceName ≤ 128) so a single request can't push multi-megabyte strings into the users / participants tables even within the 1 MiB body cap.
- **Server — constant-time admin token comparison (CAR-144).** `require_admin` middleware switched from `token != admin_token` (short-circuits on the first mismatched byte) to `subtle::ConstantTimeEq` over the token byte slices, so timing side-channels can no longer be used to brute-force the admin token one byte at a time.
- **iOS Field / CW Sweep — Clear All QSOs now re-bootstraps the logbook from iCloud immediately (CAR-264).** Kyle reported wiping Sweep's local store and finding the cloud-backed logbook never repopulated, defeating the implicit-backup property of iCloud sync. Root cause was the `CKSyncEngine` state token surviving the wipe on both apps: `CloudSyncJournalEngine.start()` gates snapshot bootstrap behind `isFirstSync = (loadSyncState() == nil)`, but neither clear-data path touched `UserDefaults["journalSyncEngineState"]`, so after a wipe `isFirstSync` was false, bootstrap was skipped, and `fetchChanges()` saw the cloud journals as "already applied" against the stale token. A real fresh install dodged the bug because deleting the app on either OS clears Preferences along with the data store. New `CloudSyncJournalEngine.resetForLocalWipe()` actor method stops the engine, drops the persisted state + `cloudSyncDeviceId` + journal sequence + snapshot-upload throttle, clears the cached model context, and restarts — which lands in the snapshot-bootstrap + full-journal-refetch path the same way a fresh install does. Rotating the deviceId fixes the secondary gap where own-device journals were being skipped on inbound, so QSOs logged on the wiping device since the last snapshot are recoverable. Wired through `CloudSyncService.resetForLocalWipe()` on both apps, called from `clearAllQSOs` (iOS) and `ClearLogConfirmationSheet.performClearLog` (Sweep). Confirmation copy on both surfaces updated so the user knows the logbook will re-download from iCloud and that disabling sync first is the way to get a clean wipe.
- **CW Sweep — Status bar QSO count no longer inflates against CloudKit mirror rows (CAR-262).** `StatusBarView.loadCounts` deduped by `QSO.id`, but CloudKit's private + shared zones can produce mirror rows that share content with *different* UUIDs — those slipped past the set and pushed the status-bar count well above the user's actual unique QSO total (Kyle reported the status bar reading "way more QSOs than I have" while the Sync Diagnostic Report showed the correct number). Switched to dedup by `QSO.deduplicationKey` (callsign + band + canonical mode + timestamp rounded to 2 min — the same key Dashboard's `computeQSOStats` uses) and replaced the inline `mode != "WEATHER" && mode != "SOLAR" && mode != "NOTE"` filter with `QSOMode.isMetadata(qso.mode)` so the status bar reads from the project's single source of truth.
- **iOS Field — Legacy `OP: <nickname>` segments scrubbed from existing QSO notes (CAR-258).** CAR-243 stopped emitting the prefix going forward on 2026-05-06, but QSOs created before that still carried `"OP: Bob"` (or ` | OP: Bob | …`) baked into their local notes. New one-time `OPPrefixBackfillService` (façade over `BatchedRewrite`) splits `qso.notes` on the legacy ` | ` joiner, drops any segment with the literal `OP: ` prefix, and rejoins — clearing the field entirely when nothing else remains. Scoped to QSOs with `notesUserAuthored == false` so user-typed text is never touched, and gated by a once-per-device UserDefaults flag inside the existing `runRepairChainIfNeeded` background pass. QRZ-side cleanup needs no code: REPLACE uploads already omit `<comment:>` when notes aren't user-authored (CAR-243), and QRZ blanks fields absent from a REPLACE payload, so any natural re-upload clears the prior comment server-side.
- **iOS Field — Hunter Log sort picker now reorders the Club Members section too.** `ActivityLogSpotsList+Clubs.swift` was re-sorting `clubMemberSpots` alphabetically by callsign, ignoring the user's Recent / Frequency / Needs selection. Because club members render above Other Spots, the top of the list never moved on sort changes — which read as "sort doesn't work." Dropped the hardcoded `.sorted` so the section inherits ordering from `clubFilteredSpots` (which already respects `sortOrder`).
- **iOS Field — FT8 audio "input too high" warning no longer gets stuck.** Four converging causes diagnosed and fixed in `FT8AudioEngine` / `FT8AudioOverloadTracker` / `FT8AudioLevelBar`. (1) `vDSP_desamp` in the 4:1 decimator was reading 14 floats past the end of every tap buffer because `outputCount = samples.count / ratio` ignored the FIR window's `filterLength - 1` requirement — the uninitialised heap memory occasionally landed near ±1.0 and produced phantom near-full-scale peaks at the tail of every buffer, latching the overload tracker into critical on perfectly clean input. Trimmed `outputCount` to `(samples.count - filterLength + 1) / ratio` so reads stay in-bounds. (2) Wide-band peak detection is the wrong measurement for FT8: a single strong adjacent-channel signal (broadcast splatter, out-of-passband carrier, even a busy band's combined crest factor) pinned the meter even when the FT8 passband was healthy. Added a 200–2900 Hz Butterworth bandpass (`FT8AudioBandpassFilter`, cascaded 2nd-order biquads with delay-line state retained across buffers) and now measure RMS/peak on the filtered output. The overload tracker requires BOTH band-limited RMS in the danger range (≥ -3 dBFS) AND sustained near-full-scale peaks (≥ 0.99 for ≥ 50% of a 5 s window) to enter `.critical`. (3) The tracker only reset on full `stop()`, so a route change (USB-C DAC unplug, headset switch) or input-picker swap kept the previous device's clipped-peak history alive and the banner stayed latched against a quieter new device. Added an `onRouteChange` callback wired through `FT8AudioEngine` → `FT8SessionManager` → `audioOverload.reset()`, plus an explicit reset on `selectAudioInput`. (4) The 50 Hz tap callback was wrapped in `Task { @MainActor in … }` and could backlog the main actor during heavy SwiftUI redraws (waterfall, decode lists); queued stale loud samples were timestamped at `record()` time, all collapsing onto "now" and instantly filling the clip window. Rate-limited the level callback to ~10 Hz at the source and added a `captureTime` field on `FT8AudioLevel` so the tracker uses actor-side capture timestamps rather than main-actor record-time. Plus a 1.5 s watchdog in the tracker that reverts to `.ok` if no samples arrive while critical (covers route-change / interruption pauses where nothing else calls `record()`).
- **Infra — Let's Encrypt cert renewal is now automated.** The pip-installed certbot in `roles/certbot/` never shipped with a renewal timer, so cert renewal had been silently manual since the box was provisioned. `activities.carrierwave.app` hit 90 days first and expired on 2026-05-16, breaking the iOS contest-definition download (and every other client) for ~3 days; `swl.carrierwave.app` was 6 days from the same fate. Roots of the renewal failure: (1) no systemd timer, (2) every site's port-80 nginx server redirected `/.well-known/acme-challenge/` to HTTPS, where the request was proxied to the app and the SPA's index.html came back instead of the challenge file. Patched all four nginx templates (`activities_server`, `activities_server_staging`, `cw_swl`, `website`) to serve the ACME challenge path directly out of `/var/www/html`, normalised the website cert's webroot to `/var/www/html` for consistency, and added `certbot-renew.{service,timer}` to `roles/certbot/files/` (twice-daily check, 1 h randomised delay, `--deploy-hook 'systemctl reload nginx'`). Live server already reconfigured and both expired/expiring certs renewed.

## [1.91.0] - 2026-05-19

### Added
- **iOS Field — Weather Radar overlay on the Map tab.** The `.weatherRadar` experiment now extends to the Parks & Summits map. New `cloud.rain` toolbar button toggles a NEXRAD CONUS base-reflectivity overlay directly on the map alongside park polygons, trail polylines, and pins — no separate sheet. To make this work the Map tab moved from SwiftUI `Map { … }` (which has no `MKTileOverlay` equivalent) to a `UIViewRepresentable`-wrapped `MKMapView` (`ParkSearchMapKit`, `ParkSearchMapKit+Sync`): boundaries become tagged `BoundaryFillOverlay`/`BoundarySkirtOverlay`, trails become `TrailLineOverlay`/`TrailSkirtOverlay`, pins host the existing `ParkPinView`/`SummitPinView` SwiftUI views inside `MKAnnotationView` via `UIHostingController` (with `safeAreaRegions = []` so the anchor sits correctly), and the radar tile overlay is rendered in the same view as everything else — so it moves in lockstep with the basemap during pan/zoom instead of trailing one render-cycle behind. Region binding is two-way: user pans now write back to `mapRegion`, preventing unrelated state changes (boundary fetch, summit refresh) from snapping the map back to the home grid on every re-render. `recenterOnMyLocation()` bumps a one-shot `recenterToken` that triggers `setUserTrackingMode(.follow)`. Selection (tap a park polygon, trail, or pin) and the swipe-down-to-dismiss callout still work.
- **iOS Field — Per-radio connection profile + session auto-connect (CAR / unified equipment config).** Adds `RadioConnectionProfile` (transport / protocol / device UUID / host / port / CW-Bridge route) to `EquipmentItem`, stored as JSON so the schema doesn't migrate every time the profile grows. `LoggingSession` gains a local-only `radioItemID` FK; `LoggingSessionManager.connectRadio()` now prefers the session's radio profile and falls back to the legacy `RadioService.connectToSavedDevice()` path. New per-item connection sheet (`RadioConnectionSheet`) and a Connection section on `EquipmentItemDetailView` for radios; the global Radio settings is reachable via deep link from inside the sheet for device scanning / RS-BA1 auth / SmartLink. One-shot migration (`RadioConfigMigration`) lifts the singleton `RadioService` UserDefaults state onto the matching (or synthesised custom) radio item, and back-fills `radioItemID` from `LoggingSession.myRig`. `RadioCatalogMetadata` infers protocol / supported transports / CW Bridge compatibility from existing catalog data, so this lands without server changes. `InventoryPickerSheet` learned an `onItemSelected` callback so the session start sheet captures the item FK alongside the display-name string. CW Bridge routing is explicit per session (`bleViaBridge` toggle on the BLE profile) — ownership alone doesn't switch routing. Status chip in the logger HUD and per-item Keychain credentials are deliberately deferred to a follow-up. Plan: `docs/plans/2026-05-17-unified-equipment-config.md`.
- **iOS Field — Weather Radar experiment (US only).** New `.weatherRadar` experimental feature (alpha, hidden by default) adds a NEXRAD CONUS base-reflectivity tile overlay on top of an `MKMapView`, plus a compact NWS alerts chip on the radar map. The chip mirrors the existing Space Weather chip pattern: a severity-tinted capsule (worst severity + count) opens a `WeatherAlertsSheet` rendered as a `List` with a colored impact summary header and one row per alert (icon + event + headline + area + `EventTimelineBar`). Reached via a new cloud-rain button in the existing `WeatherPanelView` header. Centers on the session's grid if known, then falls back to GPS, then to the geographic center of the contiguous US. The radar tile template (`https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png`) is Iowa State's free Mesonet cache (~5 min refresh, no API key); alerts come from `https://api.weather.gov/alerts/active?point=lat,lon`. Toolbar exposes an opacity picker (25 / 50 / 75 / 100%) and a manual "Refresh Alerts" action. Three new files: `Services/WeatherRadarService.swift`, `Views/Weather/WeatherRadarView.swift`, `Views/Weather/WeatherAlertsBanner.swift`.
- **CarrierWaveData — Radio CAT macros with a data-driven vendor command catalog.** New `Macros/` subsystem: `@Model RadioMacro` for SwiftData/iCloud persistence, `RadioMacroDocument` for sharable `.cwmacro` JSON, `MacroTemplateEngine` for `{TOKEN}` / `{name:format}` placeholder expansion (BCD LSB-first, zero-padded decimal, space-separated hex), and `MacroExecutor` that dispatches steps through a `MacroExecutorSink` protocol — keeping radio surface decoupled for testing. High-level steps (`setFrequency`, `setMode`, `setPower`, `ptt`, `setRIT/XIT`, `sendCW`, `delay`, `clearRITXIT`) ship with the bridge protocol; vendor commands (CI-V `16 02 {level}` etc.) live in `Resources/RadioCommands/*.json` so adding an Icom or Kenwood command is a JSON change, not a release. Bundled catalogs cover 15 IC-7300/7610/705/9700 commands and 4 TS-480/590/890/K-line commands. Includes protocol gating (`appliesTo`), arg validation (min/max/enum), CI-V slave address injected from the connected radio at framing time, and a `.rawBytes` escape hatch. No UI yet — editor and run surface are follow-up work.
- **iOS Field — Propagation Check detail view, redesigned end-to-end.** Tapping a saved propagation check on the root list now routes to a full results screen (`PropagationCheckResultsView`) instead of being swallowed by `List(selection:)`. Inline map card draws geodesic arcs from the operator's grid to each skimmer with band-colored pins (and a "You" pin at home); the region auto-fits on appear and re-fits as HamDB enrichment resolves new skimmer grids. New spots list section enumerates every captured spot newest-first (callsign, band, source RBN/PSKR, timestamp, SNR, distance from operator). New azimuthal/standard map toggle reuses `AzimuthalMapView` with sector density centered on the operator's grid. Map card honors the user's `shareMapStyle` choice — midnight / warm / ocean / arctic / ember themes render via `FlatMapRenderer` with band-colored `MapPinMarker`s (matching the share card + session detail map), while adaptive / flat / globe continue to use the interactive MapKit `Map`. Charts (timeline + distance histogram) extracted to `PropagationCheckCharts.swift` to stay under the 300-line type-body limit.
- **iOS Field — Propagation Check stats now read from HamDB-enriched skimmer grids.** Band breakdown, geography breakdown, distance histogram, and the "Max distance" headline all switched from the frozen denormalized `blob.spots.skimmerGrid` to `effectiveEntries` — `blob.spots` patched with grids resolved through `GridCache.shared`. Enrichment mirrors `SpotsService.enrichSpotsWithGrids`: cache hit first, parallel HamDB lookups for misses, results written back so the RBN spotter map and the propagation check share the same skimmer-grid set across the app. Skimmers that had no grid in the spot feed now contribute to stats once HamDB resolves them.
- **iOS Field — Propagation Check detail view supports editable notes + equipment per check.** `PropagationCheck` model gained optional `notes`, `radio`, `antenna`, `key`, and `mic` fields. New pencil toolbar button opens `PropagationCheckMetadataEditSheet`, which reuses the session metadata sheet's `RadioPickerSheet` + `EquipmentPickerSheet` so saved equipment lists are shared across surfaces. `PropagationCheckMetadataCard` renders notes + equipment on the detail view and hides itself when nothing is set.

### Changed
- **iOS Field — Parks & Summits map clustering moved off the main thread via ClusterMap quadtree.** MKMapView's built-in `clusteringIdentifier` clustering is main-thread-bound and degraded badly above ~10k annotations; at parks+summits scale (≈10k POTA + ≈12k SOTA pins) it froze the UI on every region change regardless of batched adds, collision tuning, or display-priority tweaks. Adopted vospennikov/ClusterMap 2.1.1 (actor-backed quadtree) so the clustering pass runs off-main and MKMapView only ever sees the visible cluster bubbles + de-clustered leaves for the current zoom — never the full 22k pin set. New `MapPinItem` value type (nonisolated, ID + coord + kind) is the cluster manager's payload; full `POTAPark` / `SOTASummit` records are looked up from their caches at MKAnnotation materialization time, keeping the quadtree small (~40 bytes per item). `MapClusterAnnotation` / `MapClusterAnnotationView` render a count bubble at the cluster centroid (green for parks-only, brown for summits-only, teal for mixed); tapping zoom-to-fits the underlying members. Coordinator's `syncClusterData` rebuilds the quadtree only when the input signature actually changes, and `triggerClusterReload` is 80 ms-debounced on `regionDidChange`. `loadNearbyParks` / `loadNearbySummits` now load the full set off-main via `Task.detached` (the radius-limited paths are gone — viewport filtering happens inside the cluster manager).

### Fixed
- **iOS Field / CW Sweep — Keyer bar in CW sessions no longer disappears when the bridge is connected but the firmware's initial USB-status push is dropped or raced.** The keyer row's visibility predicate (`LoggerView+CWKeyer.cwKeyerVisible` on iOS, `RadioManager.bridgeUSBConnected` on macOS) requires `bridgeUSBConnected == true`, which was set only when the bridge fired a `Status::UsbConnected` event. On handshake the firmware pushes the cached status frame once; if the iOS/macOS event stream wasn't draining yet (handshake reconnect, BLE silently re-subscribed without re-handshake, or first connect on cold launch), the push could be missed and the keyer bar stayed hidden until the user kicked something. Now adds a client → bridge `StatusReq` message — both apps interrogate the bridge immediately after handshake and again every 3 seconds while framed, so missed pushes self-heal within one tick. Firmware re-emits the same dump it already sends on handshake (status, radio info if detected, jack status, battery), so all existing event handlers light up unchanged. Touches `proto/cwbp.proto` (new `StatusReq`), `firmware/src/main.rs` (extracted `send_state_dump` helper, new `Msg::StatusReq` arm), iOS `BridgeFrame` / `BridgeProtocol` / `RadioService+Bridge`, and macOS `BridgeFrame` / `BridgeProtocol` / `RadioManager+Bridge`.
- **iOS Field — Restoring an iCloud backup on a new device no longer fails with "The backup file could not be found."** On a new device, iCloud Drive replicates the backup directory listing via metadata sync but doesn't download file contents until something asks for them. `BackupService.stageRestore` was calling `validateBackup` / `copyICloudBackupToLocal` against placeholders, both of which bail with `BackupError.backupFileNotFound`. New `BackupService+ICloudDownload.swift` calls `FileManager.startDownloadingUbiquitousItem` on the bundle's `database.sqlite` and every file under `SessionPhotos/`, then polls `URLResourceKey.ubiquitousItemDownloadingStatusKey` until everything is `.current` (or 180 s elapses, which surfaces a new `BackupError.icloudDownloadTimedOut` with a connection-check prompt). `BackupSettingsView` shows a download progress overlay during the wait so the user sees `N of M files ready` instead of a frozen screen.

## [1.90.0] - 2026-05-09

### Added
- **iOS Field — New Hunt widget for hunters.** Small home-screen widget showing propagation rating ("Excellent" / "Good" / "Fair" / "Poor"), K/A/SFI circular gauges, the 80/40 / 30/20 / 17/15 / 12/10 band condition grid, and a binoculars badge with the live count of active POTA + SOTA + RBN spots. Refreshes every 15 minutes (spot freshness > solar). Tapping the widget deep-links via the new `carrierwave://hunt` URL to the Hunter Log (`ActivityLogView`), presented as a `fullScreenCover` from `SessionsTabView` so it works regardless of whether a logging session is active. Falls back to the Hunter Log setup sheet if no log exists yet. Solar comes from `SolarFetcher` (HamQSL XML, with App Group fallback when offline); spot count comes from `SpotsFetcher` aggregating POTA / SOTA / RBN feeds with 30-minute freshness cutoff.
- **iOS Field — Solar widget now surfaces a space-storm summary line.** `DONKIPollingService` writes the worst active space-weather event (geomagnetic storm / solar flare / CME) to a new `WidgetSpaceWeatherSnapshot` in the App Group on every poll. The Solar widget's small variant adds a one-line "<event type>: <impact>" row beneath the K/A/SFI gauges with an impact-tinted SF Symbol; the lock-screen rectangular variant shows the same headline below its gauges; the inline lock-screen variant swaps in the storm headline whenever impact is moderate or worse. When no events are active the line reads "All quiet" with a shield icon. Snapshot is read at timeline-build time so the widget refreshes on every `WidgetCenter.reloadTimelines(ofKind: "SolarWidget")` triggered by a new poll.

### Changed
- **iOS Field — Session "End" button now reads "END" (all caps).** Both portrait and landscape session-header end buttons (`LoggerView+SessionHeader.swift`, `LoggerView+Landscape.swift`) bumped to all-caps text to match the visual weight of the red destructive treatment.
- **iOS Field — Tapping the Solar widget no longer auto-opens the On Air Now sheet.** The `carrierwave://conditions` deep link previously navigated to the Dashboard tab and immediately presented the OnAirCard pull-up sheet via `pendingConditionsNavigation`, which made it impossible to enter the app from the widget without dismissing a sheet first. The deep link now just selects the Dashboard tab; the dead navigation binding (`pendingConditionsNavigation` / `navigateToConditions`) was removed from `ContentView`, `DashboardView`, `OnAirCard`, and the iPad detail / MoreTab call sites.

### Fixed
- **iOS Field — Dashboard scroll and Grid Tracker typing no longer chop on tab return.** Five-cause perf regression diagnosed and fixed: (1) `Friendship` `@Query` in `OnAirCard`, `FriendsOnAirCard`, and `FriendActivityCard` invalidated bodies on every unrelated SwiftData save (CloudKit syncs, log inserts, ActivityItem writes) — three card bodies cascading into the dashboard tree on each save tanked scroll perf during sync. Replaced with `@State [Friendship] = []` + manual `FetchDescriptor` fetch in `.task`. (2) `DashboardView`'s `.onChange(of: selectedTab)` kicked off four concurrent full-table scans (asyncStats, presenceCounts, equipmentStats, bragSheetStats) that each emitted staged `@Observable` writes to the main actor — violating the "Serialize concurrent full-table scans" rule and continuously re-evaluating the dashboard during the recompute window. Now serialized with `await waitUntilComplete()` between stages and deferred 300 ms so the tab transition animation finishes first. (3) `OnAirCard.loadAllData` re-fired on every dashboard appearance (5 parallel network/database fetches, ~11 staged `@Observable` writes per appearance); added a 60 s freshness window. (4) `GridTrackerDetailView` filter+sort ran on every keystroke and was invoked once per visible row for `.last`, allocating a fresh uppercased `String` per callsign per call; hoisted to a debounced (`150 ms`) `@State` cache recomputed only on input changes, with case-insensitive `range(of:options:)` instead of per-callsign `.uppercased()`. (5) `GridHeatmapView` Canvas redrew ~32 000 cells on every keystroke in the search field above it because the parent passed a fresh closure each frame; added `Equatable` conformance (compares summary fingerprint, ignores closure) and `.equatable()` so the heatmap only redraws when the underlying grid data actually changes.
- **iPadOS Field — Sidebar tab settings now match what's actually shown.** On first launch on iPad, `TabConfigurationView` listed CW / Activity / Events / Remote under "Hidden" because it read the iPhone-style `defaultHidden` set, but the iPad sidebar (`iPadVisibleTabs`) used a different default (no hidden tabs) — settings claimed tabs were hidden while the sidebar still showed them, and toggling a tab from settings would silently inherit the iPhone-default hidden set. Both `refreshTabs` and `toggleTab` now pass `forIPad: isIPad` so settings agrees with the sidebar. Sidebar column also constrained to a more compact width (~220 pt) so the detail pane has more horizontal room.
- **iOS Field — Ended sessions no longer resurrect themselves after kill/relaunch.** Long-standing bug: a session ended on iPhone would come back as the active session on the next launch, even after multiple ends. Root cause spanned four layers, all now fixed: (1) `LoggingSession.apply(remote:)` blindly overwrote `status` and `endedAt` from inbound LAN snapshots — CW Sweep on Mac (or another peer) holding a stale "active" view of the session would replay it onto the just-ended local record, clearing `endedAt` and flipping `status` back to `.active`. Now refuses to overwrite when the local row is already ended and the remote claims it's still active; (2) `applyActiveSessionShouldChange` would forcibly flip `session.status` back to `.active` if a continuity notification arrived for a completed session — now bails early when `endedAt != nil` or `status == .completed`; (3) `mostRecentlyStartedActiveSession()` trusted `statusRawValue` alone — now post-filters out rows with `endedAt != nil`; (4) `loadActiveSession()` heals corrupt rows on cold launch — if the restored session has `endedAt` set but `status == .active` (the state past resurrections produced), force-flip back to `.completed`, save, and clear `UserDefaults` so the user's end sticks. The user's deliberate end-session action now always wins against remote noise.
- **iOS Field — Activation Suggestion widget now opens directly to the Sessions tab.** Previously the widget had no `widgetURL`, so tapping it fell through to whatever tab was last selected (often Dashboard). Now routes to `carrierwave://logger`, matching the Active Session widget's behavior and putting the user one tap away from starting an activation.

## [1.89.0] - 2026-05-07

### Added
- **iOS Field — Activation start wizard auto-suggests the 3 nearest references within 10 mi (CAR-257).** Selecting a program now immediately surfaces the closest references for that program — no need to tap into search first. POTA and SOTA already showed nearby suggestions but with `limit: 5` and no distance cap (~100 km default), so a user in dense park country saw a long list of irrelevant entries; the limit is now 3, the radius is now 16 km (~10 mi), and the section header reads "Nearby (within 10 mi)" so the search radius is honest. WWFF gained the same treatment via a new `NearbyWWFFSuggestions` view. Implementation is fully synchronous: the user's grid (`myGrid`, falling back to `loggerDefaultGrid`) → coordinate via `MaidenheadConverter` → in-memory haversine pass over `POTAParksCache` / `SOTASummitsCache` / `WWFFReferencesCache` snapshots — no GPS request, no spinner, no async lifecycle. The picker sheet (magnifying-glass button) is unchanged for users who want to search by name or browse beyond 10 mi.
- **iOS Field — 8-character Maidenhead grid option for `MY_GRIDSQUARE` (CAR-256).** `MaidenheadConverter` only emitted 6-char grids, fine for HF logging but too coarse for VHF/UHF and grid-square contests. Added `MaidenheadConverter.Precision` (4 / 6 / 8) on the core API; `coordinate(from:)` learned to parse the 7th/8th characters and report the center of the 1/10×1/10 subsquare cell, so 8-char grids round-trip. `QuickEntryParser.isGridSquare` accepts 8-char input alongside 4/6. New iOS `GridPrecisionPreference` (UserDefaults-backed, nonisolated so GPS callbacks don't have to hop actors) is read by `GridLocationService` and `LocationSessionService`. A new "Grid Square" section in **Settings → Logger** picks 4 / 6 / 8.
- **iOS Field — Inline S2S Summit field for SOTA logging (CAR-254).** The QSO model and ADIF S2S exporter already had `qso.sotaRef` plumbed end-to-end, but the Logger had no inline input — the only way to set it was through the buried edit sheet, awkward at a summit. The expanded-fields row now shows a Summit field for SOTA sessions in place of Park (POTA's Park is already auto-enriched from spot lookup, so it yields primary placement); dual POTA+SOTA sessions show both, Summit on the primary row next to Grid and Park beneath. Refactored the conditional layout into a `referenceFieldsRow` helper. Quick-entry tokenization for SOTA references (typing `W6/CT-225` straight into the entry line) is intentionally a follow-up — this lands the inline field that was missing.
- **iOS Field — SOTA / POTA session grid pinned to summit/park surveyed coordinates (CAR-255).** `startSession` previously fell back from caller-provided `myGrid` straight to GPS, which is unreliable at session start (cold fix, indoors, locked phone in a backpack at the summit). New `resolveSessionGrid` helper resolves `session.myGrid` in priority order: caller-provided, then SOTA summit lat/lng from `SOTASummitsCache`, then POTA park lat/lng from `POTAParksCache`, then GPS. Honours the user's grid precision preference (CAR-256), so 8-char users automatically get 8-char grids derived from summit/park coords. Reverse lookup (suggesting the nearest summit from current GPS) is intentionally out of scope here — that's a separate UX surface.

### Changed
- **iOS Field / watchOS — SOTA activation threshold is 4 QSOs, not 10 (CAR-253).** The Logger session-header QSO chip and the watch's activation progress ring both hardcoded 10, so SOTA-only sessions never hit their actual 4-QSO qualifying line — the chip stayed orange even after the activation was valid. Added `LoggingSession.activationThreshold` (POTA=10, SOTA=4, WWFF=44; min across programs for dual sessions) so iOS, watch, and widgets read one shared source. The widget already had the right values; iOS chip and watch ring now both read the per-program target. Casual / AoA sessions continue to fall through to the plain "N QSOs" display. POTA-specific award/bragsheet `>= 10` checks are unchanged — those are POTA program rules, not generic activation thresholds.

### Fixed
- **iOS Field — Nearby-spot frequency popup no longer reappears after dismissal (CAR-252).** The frequency-warning banner used the warning's message string as its dismissal key and called `dismissedWarnings.removeAll()` on every `session.frequency` / `session.mode` change. Any retune, mode auto-switch, or session-model re-emission of the same value cleared the dismissed set and the popup popped right back. Added a stable `FrequencyWarning.dismissalKey` (defaults to message); spot warnings use `spot:<activator>:<reference>` so dismissal also survives spot-feed refreshes that update the suggestion text ("spotted 1m ago" → "2m ago", new spotter, etc.). Dropped the eager `removeAll()` in the freq/mode onChange handlers; the dismissed-set is now cleared only when the active session id changes (new session = clean slate).
- **iOS Field — Reject Upload / Reopen Session confirmations now appear from the session detail view (CAR-250).** Both `confirmationDialog` modifiers were attached to `SessionsView` (the parent), so when the user tapped these from inside a pushed `SessionDetailView`, the dialog stayed dormant until the user popped back to the Sessions list. `SessionDetailView` now owns its own `confirmationDialog`s for both actions; the parent's callbacks (`onReject` / `onReopen`) became direct invocations of `rejectActivation(_:)` and a new `performReopen(_:)` helper, so confirming inside the detail view runs the action immediately instead of double-prompting via the parent. The `SessionRow` swipe-action path still routes through the parent's existing dialog and `reopenSession()` flow, since those rows are in the parent's view hierarchy.

### Added
- **iOS Field — SOTA session details now have Brag Sheet and Export ADIF.** SOTA-only sessions (and any non-POTA session) reached `nonPOTASessionDetail` which never wired `onShare` or `onExport`, so the action menu was missing both buttons. The activation share card was also keyed off `POTAActivation` directly. Refactored: introduced a program-neutral `BragSheetSource` value type that wraps reference code, name, icon, callsign, qsos, display date, and program; `ActivationShareCardView` / `ActivationShareCardForExport` / `ActivationShareRenderer` now consume `BragSheetSource` so the same card renders POTA, SOTA, and casual sessions. The "park" header section is now `ActivationShareCardReferenceInfo` and parameterizes the SF Symbol so SOTA shows "mountain.2.fill" + summit code. New `SessionADIFExportSheet` covers per-session ADIF export with no POTA upload prompt; ADIFExportService gained a `generateSessionADIF(for:activatorCallsign:references:)` path that emits `MY_SOTA_REF` for SOTA sessions, `MY_SIG`/`MY_SIG_INFO`/`MY_POTA_REF` for POTA sessions, and both for dual sessions, with a QSLMSG line summarising whichever combination is in play (and S2S / P2P tags from each QSO's own references).
- **iOS Field — SOTA self-spotting and multi-program SPOT dispatch.** `SPOT` previously hardcoded POTA — sessions activating SOTA only, or dual POTA+SOTA, got a "SPOT requires active POTA session with frequency" error. The command now dispatches per-program: POTA spots fan out across every park reference (n-fer behaviour preserved), SOTA spots one self-spot to SOTAwatch (`api2.sota.org.uk/api/spots`) using the session's `sotaReference`. The success toast lists every reference that was spotted; if every program failed, the first error is surfaced. TOTA spotting is intentionally not wired up — TOTA's `POST /activations` endpoint is an activation summary (no frequency/mode), not a realtime spot. `SPOT REPEAT` and the QSY auto-spot use the same dispatcher, so SOTA-only sessions also get repeating and post-QSY spots.

## [1.88.0] - 2026-05-07

### Fixed
- **iOS FT8 — Mode-toggle race that could leave FT8 silently broken until force-quit.** Toggling Logger mode away from FT8 fired a fire-and-forget `Task { await ft8Manager.stop() }` and immediately set `ft8Manager = nil`. `FT8AudioEngine.stop()` ended with `try? AVAudioSession.sharedInstance().setActive(false, …)` — process-scoped. If the user toggled back to FT8 before the old `stop()` finished, the new manager's `start()` already called `setActive(true)`, then the old `stop()`'s `setActive(false)` raced in and killed the just-activated session. Result: black waterfall, no decodes, no level meter, "FT8 didn't work at all." Removed the `setActive(false)` from `stop()` — the audio session belongs to the process, not to a per-mode component, and the OS reclaims it on background/terminate.
- **iOS FT8 — Start failures were silently swallowed.** `FT8SessionView.task` did `try? await ft8Manager.start()`, so any failure (unsupported sample rate from a Bluetooth/USB-C route the OS picked, mic permission denied, audio session interruption mid-init) left the user staring at a black waterfall with no diagnosis. `FT8SessionManager.start()` now stores the error string in a new `startupError` property; the session view renders an orange `FT8StartupErrorBanner` with a Retry button (driven by a new `retryStart()` that fully tears down the engine before re-running configure + start). `FT8AudioEngine.start()` also cleans up partial state on throw (removes the tap, stops the engine) so the retry starts from a known-good baseline.
- **iOS FT8 — Waterfall FFT and per-bin percentile sort were running on the main actor.** Every audio buffer (~6×/sec) hopped to `@MainActor` to run a 2048-point vDSP FFT, dB conversion, and 496 sliding-window sorts (~61 elements each) for the per-bin reference clipping fix — landing on the same thread as SwiftUI rebuilds and the TX/RX state transitions in the conversation card. Plausible contributor to the freeze-on-answer reports. Split `FT8WaterfallData` into a small `@MainActor @Observable` published-state class (just the rolling `magnitudes` rows) and a new `FT8WaterfallProcessor` actor that owns the FFT setup, Hann window, and pending-sample buffer. Audio callbacks now flow through `Task { await processor.process(samples) }`; the processor publishes finished rows back to `FT8WaterfallData` via a single `@MainActor append(rows:)` hop. The per-bin percentile algorithm (window size, percentile, sliding-sort) is byte-for-byte identical to the existing fix.

### Added
- **Server — Enriched share link landing pages now ship a great-circle map and live club chips.** The QSO card client-side renderer learned a simplified equirectangular world map: continents painted in dim cyan, dim grid every 30°, an orange great-circle arc with soft glow between `myGrid` and `theirGrid`, glowing endpoint dots (orange = me, cyan = them) with callsign labels. Distance and compass bearing are computed from the Maidenhead grids and added as badges. Both callsigns kick off a parallel `fetch` against `/v1/callsign-enrichment/{callsign}` and render any returned memberships as inline pill chips (e.g. `🎹 CWops #1532`, `🤜 BKG #29`, `🔑 SKCC #6707T`) — the membership data is public so this stays consistent with the "fragment never reaches the server" privacy property. The shell's CSS is fully Carrier Wave-themed: orange/cyan accents, an inline wave-logo SVG in the brand bar, a soft signal-gradient page background, accent rule on the card top edge, and orange-tinted note callouts. Map gracefully wraps the antimeridian (path is split into segments instead of drawing a horizontal line across the world). Activation, callsign, park, and summit cards reuse the same map rendering and brand styling.
- **Server — Enriched share link landing pages (`/link/{call,park,sum,qso,act}/:id`).** The QSO/callsign/park/summit/activation share URLs produced by iOS Field and CW Sweep finally have somewhere to land. Each route returns a self-contained HTML page that ships a small inline shell + `/link/static/link-card.js`; the JS reads the `#d=<base64url(JSON)>` fragment locally and renders a styled card matching the in-app `LinkPreviewCardView` (kicker, big monospaced identifier, badges for band/mode/RST/freq/grid/park, UTC timestamp, optional notes). The fragment is never sent in HTTP requests, so QSO/activation data still never reaches the server — the page only carries opaque path tokens. Universal-link AASA file at `/.well-known/apple-app-site-association` claims `/link/*` for both iOS (`com.jsvana.FullDuplex`) and macOS (`com.jsvana.CWSweep`) bundle IDs so recipients with the app installed deep-link straight into the matching detail view. Website nginx now proxies `/link/` and `/.well-known/apple-app-site-association` to activities-server so the apex `carrierwave.app` domain serves the routes without any new hostname. Schema-version-aware: a payload with `v` greater than the page's known version renders a graceful "update Carrier Wave to view this share" card.

### Fixed
- **iOS Field — `{MYCALL}` in the CW memory keyer now actually resolves to the operator's callsign.** The CW Messages editor and list both read the wrong UserDefaults key (`stationCallsign` instead of `loggerDefaultCallsign`), so the in-editor preview and the slot-row preview always fell back to the placeholder `W6JY` regardless of the operator's profile. Both views now read the canonical `loggerDefaultCallsign` key.

### Added
- **iOS Field — `{MYNAME}` macro for the CW memory keyer.** New macro that expands to the operator's first name (e.g. `TU {MYNAME}` → `TU JAY`). The first name is mirrored from the user profile into `UserDefaults["loggerDefaultName"]` (and synced via iCloud KVS alongside the callsign), with a one-shot keychain backfill on the keyer settings screen for users who saved their profile before this change. `{MYNAME}` is now part of the shared macro vocabulary (`RemoteCWMacros.known`) and is included in the context dict that ships to the CW Bridge / Sweep with every `CW_SLOT_PLAY` frame. The editor's macro pill strip exposes it next to `{MYCALL}`.

### Changed
- **iOS Field — Contest sessions now use a unified "strike card" that fits above the keyboard fold.** During CWT (and any contest with member-list enrichment) the separate QRZ card + RST/QTH row + contest exchange card collapse into one dense card: callsign + membership chips (`🎹 #3573`) + dupe / NEW MULT badge in the header, a single status line summarising name · state · grid · distance · bearing · prior-contact-count, two big monospaced exchange inputs (NAME and # OR S/P/C, 50pt tall and centered for thumb targeting at 100 QSOs/hour), and a tertiary `47Q · 47P · 12M · 564` score footer. Callsign + strike card now both stay visible while the keyboard is up, so the operator never has to scroll to reach the exchange fields. Implemented in `LoggerView+ContestStrike.swift`; non-contest sessions keep the existing `LoggerCallsignCard`. Compact RST/QTH row stays available below the strike card for the rare CWT QSO that isn't 599/599.

### Added
- **iOS Field — CWT auto-fill now works for non-CWops members too.** Per CWT rules, non-members send first name + state / province / DXCC prefix. `ContestEnrichmentMatcher.prefill` now accepts an optional `fallbackIdentifier` and an optional `entry` (membership), so a station with no CWops row still gets both fields prefilled: name from QRZ nickname, identifier from the resolved fallback. `LoggerView` resolves the fallback as state for US (`MD`) / Canada (`ON`), or the DXCC primary prefix from `LocationPrefixLookup.entity(forCallsign:)` for DX (`DL`, `JA`, `VK`, …) — picked from the callsign rather than QRZ's `<state>` field so a German station gets `DL` not whatever region tag QRZ may have stored. Member numbers still take precedence for CWops ops; `fallbackIdentifier` is only consulted when no membership row exists for the callsign.

### Fixed
- **iOS Field — CWT auto-fill now puts the operator's CWT nickname (from the QRZ `<nickname>` tag, e.g. `TIM` for K5OHY instead of the registered first name `Timothy`) in the `name` field, ALL CAPS, and clears name + member number when the callsign is cleared.** Three pieces: (1) `ContestEnrichmentMatcher` reduces the source name to the first whitespace token in ALL CAPS (CWT wire-format convention), so `"Marshall R"` → `"MARSHALL"` and `"Jay V"` → `"JAY"`. (2) The matcher accepts a `preferredName` override that wins over the membership-list name; `LoggerView` passes `lookupResult.nickname ?? lookupResult.firstName` so QRZ's nickname (`TIM`) replaces the CWops PoLo-list registered name (`TIMOTHY D`) once the lookup resolves. The prefill is re-runnable: a richer source arriving later overwrites the earlier auto-fill while preserving anything the operator has typed by hand. (3) The matcher returns the fields it wrote so `LoggerView` can track auto-filled values and clear them when the callsign input goes empty — name and number no longer linger from the previous QSO.
- **Server — `/v1/callsign-enrichment/{callsign}` and `/dataset` returned 500 ("Pool extension missing") instead of any data.** Both handlers used the `Extension(pool)` extractor while the rest of the v1 router supplies the connection pool via `with_state(pool)`. Switched both to `State(pool)` to match. The CWops dataset has been on disk since 0.4.66 but unreachable through the API; it now actually responds.

### Added
- **Server — Straight Key Century Club (SKCC) callsign enrichment source.** Polled daily from `https://www.ditdit.club/data/skcc_members.txt` (PoLo format, generated upstream by qrqcrew-notes-daemon with QRZ-resolved canonical callsigns). SKCC numbers surface in `GET /v1/callsign-enrichment/{callsign}` and the dataset endpoint alongside CWops and BKG. Migration `039_callsign_enrichment_skcc.sql`; emoji 🔑.
- **Server — Brass Knuckle Gang (BKG) callsign enrichment source.** Membership list at `https://www.bkg.club/members.txt` is now polled daily through the existing enrichment subsystem. BKG memberships surface alongside CWops in `GET /v1/callsign-enrichment/{callsign}` and in the dataset endpoint, so the iOS callsign card and macOS QSO entry popup grow a `🤜 BKG #NN` chip for matching ops with no client-side changes required. Migration `038_callsign_enrichment_bkg.sql`; `BKG` added to the trailing-tag strip list so operator names parse cleanly from PoLo lines like `AA6XV 🤜 Dave W BKG #29`.
- **Server + iOS Field + CW Sweep — Callsign enrichment metadata (CWops first; SKCC and others to follow).** New activities-server subsystem that pulls public per-callsign membership lists daily, normalizes them into a single endpoint, and feeds an offline cache on each client. The first source is CWops (parsed from `https://www.ditdit.club/data/cwops_members.txt`, Ham2K PoLo format); adding new sources is a single row in `callsign_enrichment_sources`. Clients pull the full dataset from `GET /v1/callsign-enrichment/dataset` (ETag-aware) and look up locally — no per-callsign network call during contesting. The iOS callsign card and the macOS QSO entry popup grow a chip per matching membership (e.g. `🎹 CWops #1532`); the same chip surfaces in the session QSO expanded detail view. For CWT specifically (`cwops-cwt`), the contest exchange is auto-prefilled with name + member number from the cache so operators don't have to type them, gated by a new "Auto-fill exchange from member lists" toggle in **Settings → Logger → Contests** (default on, only fills empty fields). Migration `037_callsign_enrichment.sql`, aggregator `aggregators/callsign_enrichment.rs` (24h cycle, ETag-aware refresh, replace-on-success), shared model `CarrierWaveData/Models/CallsignEnrichment.swift`, iOS `CallsignEnrichmentCache`, Sweep `CallsignEnrichmentStore`, contest helper `ContestEnrichmentMatcher` (cwops-cwt → cwops mapping).
- **CW Sweep + iOS Field — Opus codec for remote RX audio (opt-in).** New `OpusEncoder` / `OpusDecoder` pair in `CarrierWaveData/Radio/OpusCodec.swift`, both built on Apple's `AVAudioConverter` + `kAudioFormatOpus` (verified empirically end-to-end on macOS 26: 50 packets in / 50 packets out for 1 s of input, 64-byte average packet at 24 kbps, decoded RMS within 18% of source). Sweep advertises `codec: opus` on `radio.audio` when the new "Use Opus for remote audio" toggle in Remote Settings is on; Field's `RemoteSweepAudioPlayer` dispatches on codec and decodes Opus packets to PCM before scheduling on the player node. Wire format gains `AudioFormatEvent.framesPerPacket: Int?` so the decoder side can size its PCM buffer (320 samples = 20 ms at 16 kHz). Bandwidth drops from ~256 kbps PCM to ~24 kbps Opus per stream — meaningful for cell uplink. The toggle is OFF by default while we shake out interop with older Field clients (an old client can't decode an `AudioFormatEvent` with `codec: "opus"`).
- **iOS Field + CW Sweep — Tap straight key on the iOS Remote pane.** New `RemoteStraightKeyPad` in the Radio sub-tab: tap the pad sends a dit, hold past 180 ms sends a dah. Each gesture fires a single CW element through Sweep's keyer. The remote keyer path is now transport-agnostic — `RemoteOpService.handleSendCW` was bridge-only and silently failed for any USB-CAT or TCP-CAT radio; it now routes through a unified `RadioManager.sendCW(_:fallback:)` that tries CW Bridge → WinKeyer → active radio's CAT handler (CI-V `1A 02`, Kenwood/Elecraft/Yaesu `KY`). New `RadioSession.sendCW(_:)` / `abortCW()` are the third-path entry. True press-and-hold straight keying needs raw key-line firmware on the CW Bridge; tracked at [CAR-251](https://linear.app/carrier-wave/issue/CAR-251/remote-op-true-straight-key-with-raw-key-downkey-up).
- **CW Sweep — SCU-LAN10 RX audio plays through the Mac's default output.** The Yaesu UDP audio channel (port 50002) was being initialized but its packets were dropped on the floor. Each frame is now decrypted, the 24-byte inner header stripped (1B frame_seq + 23B codec/state, with bytes 4-5 = 16000 sample rate, byte 3 = 0x02 channels, bytes 22-23 = 640 audio bytes per packet — verified against a live FTDX101MP capture), and the remaining 640 bytes of *interleaved stereo* Int16 LE are de-interleaved to channel 0 (Ch1 is a near-silent TX-monitor / sub-RX). A long-lived `AVAudioEngine` + `AVAudioPlayerNode` plays the resulting mono PCM at 16 kHz. The SCU-LAN10 connection panel grows a speaker toggle + volume slider; mute/volume persist via `@AppStorage` (default muted at 70%). Diagnostic capture (first 200 frames written to `~/Downloads/cw-sweep-audio-{raw,pcm16-16k-mono}.bin`) made the inner-header / stereo discovery possible.
- **CW Sweep + iOS Field — RX audio forwarded over the Remote LAN.** New `radio.audio` topic on the RemoteOp protocol carries `AudioFormatEvent` (sample rate, channels, codec, source label) once on subscribe and on format change, plus `AudioFrameEvent` (sequence + base64 PCM payload) per packet. New `RadioAudioBroadcaster` on the macOS side multicasts the SCU-LAN10's mono PCM stream to N in-process listeners (the local Mac player + the Remote audio publisher), so adding consumers no longer requires forking the AsyncStream. Field hosts a foreground-only `RemoteSweepAudioPlayer` (AVAudioEngine + AVAudioSession `.playback`) with a speaker toggle + volume slider in the Remote Radio pane; subscription is gated on the toggle so Sweep skips encoding when no client is listening. Wire format is raw PCM16 LE @ 16 kHz mono (~50 KB/s on the wire).
- **iOS Field — Remote pane redesigned as a control surface.** The Form-with-sections layout is gone. The Radio pane now has a hero VFO display (tabular monospaced digits, MHz.kHz at 56pt and a smaller Hz triplet, with a dim placeholder when no radio is reporting), a TX/RX dot-LED indicator next to the connected Sweep name, an audio strip with a chunky speaker button + thick volume slider, and an inline tune entry. The nested `TabView` for Radio/Scope/Waterfall/Spots/CW (which collided with the system tab bar) is replaced by a horizontal capsule chip strip mounted under the nav title, styled with the existing `Color.blue.opacity(0.2)` band/mode-badge convention. Selection persists via `@AppStorage`.

### Fixed
- **iOS Field — Remote waterfall stretched lines to fill the canvas, washing out the time axis.** Each waterfall row now renders at exactly 1 pt tall (newest at top, older lines push down by 1 pt each frame), with the rest of the canvas left empty when the 200-line history hasn't filled it yet. Restores the natural arrival cadence so an operator can see how recent a signal is from how far down the screen it sits.

## [CW Sweep 0.12.0] - 2026-05-05

### Added
- **CW Sweep — Auto-update via Sparkle.** New builds reach users automatically through Sparkle 2 — `SPUStandardUpdaterController` is wired into `CWSweepApp`, "Check for Updates…" lives in the CW Sweep menu, and a daily background check polls `https://carrierwave.app/sweep/appcast.xml`. DMGs are signed with an Ed25519 key (private key in the maintainer's macOS login keychain, public key committed in `Info.plist` as `SUPublicEDKey`); Sparkle refuses to install anything that doesn't verify. Release tooling is `Tools/sweep-release/sign-and-publish.sh`, which signs the notarized DMG, prepends a new `<item>` to `website/sweep/appcast.xml`, and scp's both the DMG (versioned + a `CWSweep-latest.dmg` alias) and the appcast to `activities.carrierwave.app:/var/www/carrierwave.app/sweep/`. The new [Sweep download page](https://carrierwave.app/sweep.html) covers fresh installs; nginx caches versioned DMGs aggressively but revalidates the appcast and `latest` alias on every request. Public key, key-rotation rules, and the full publish flow are documented in the `cw-sweep-release` skill.
- **CW Sweep + iOS — Sessions continue between Field and Sweep automatically (alpha).** Starting a POTA/SOTA/contest activation on either device now propagates to the other without pressing Sync, Connect, or anything else. Three layers cooperate so this works whether the devices are co-located or apart: CloudKit-side active-session normalization in `CloudSyncJournalEngine`, silent LAN auto-reconnect via `RemoteSweepAutoConnect`, and a new `activeSession` RemoteOp topic carrying a `RemoteSessionState` snapshot (id, status, callsign, mode, frequency, programs, parkRef, qsoCount). All three paths converge on the same conflict rule (most-recent-`startedAt` wins) so they're idempotent and self-healing.
- **CW Sweep — Waterfall is now a first-class layout panel.** The previously orphaned `WaterfallView` is exposed as `PanelIdentifier.waterfall` and can be dropped into any custom layout via the layout editor. Source-agnostic: rendering reads from a new `WaterfallStore` (@Observable) that any radio producer can push into. The placeholder state explains which radios produce spectrum data so the panel is useful even when nothing is connected.
- **CW Sweep — FlexRadio (SmartSDR) panadapter / waterfall ingestion.** New `FlexPanadapterService` binds a UDP listener, sends `client udpport` + `display pan create` commands over the existing TCP control session, and decodes incoming VITA-49 frames into normalized 0..1 spectrum lines that feed the same `WaterfallStore`. Defaults to 1024 bins / 100 kHz / 10 fps; geometry follows the active slice frequency.
- **iOS Remote + CW Sweep — Waterfall forwarded to iOS over the LAN.** New `radio.waterfall` topic on the RemoteOp protocol carries 8-bit quantized spectrum lines (`WaterfallLineEvent`) plus a `WaterfallClearedEvent` whenever the active radio source changes. Sweep's `RemoteOpPublishers` observes the store and broadcasts at most 10 fps regardless of producer rate (~22 KB/s on the wire). New iOS `RemoteSweepWaterfallView` joins the Remote tab strip and only subscribes while visible. iOS color ramp matches macOS exactly so the panels feel identical on both ends.
- **CW Sweep + iOS Query Workbench — Distance, bearing, and time SQL functions.** New `cw_*` custom SQL functions registered on every `QueryReader` connection: `cw_distance_km / cw_distance_mi / cw_bearing_deg(lat1, lon1, lat2, lon2)`, `cw_grid_distance_km / cw_grid_distance_mi / cw_grid_bearing_deg(grid1, grid2)`, plus user-relative helpers `cw_user_grid()`, `cw_user_grid_distance_km(grid)`, `cw_user_distance_km(lat, lon)`, `cw_user_bearing_deg(lat, lon)`, and `cw_now()` (Unix epoch seconds REAL). User-relative variants pull the configured grid from `UserDefaults["myGrid"]` on every call so Settings changes take effect without reopening the database. Two new starter queries — "Spots sorted by nearest" and "Spots heard by nearby spotters (≤ 50 km)" — demonstrate the use cases.
- **CW Sweep — `scope.spot_observations` now denormalizes the spotted (DX) station's coordinates.** New `spot_lat REAL` and `spot_lon REAL` columns populated at observation-write time from the DX `dxGrid` (precise grid centre when known) or the DXCC entity centroid for the spotted callsign as a fallback. Distance queries can hit `scope.spot_observations` directly without joining.
- **CW Sweep — Query Workbench results pane redesigned.** Full-width / full-height table that pins to the top-left of its pane, alternating row striping, click-to-sort column headers (three-state: ascending → descending → cleared, NULLs stay last), and a "Copy CSV" button that writes the entire result set to the clipboard as RFC 4180 CSV.
- **CW Sweep — Custom SQL editor with code-editor key behaviors.** New `SQLTextEditor` (NSViewRepresentable wrapping `NSTextView`) replaces SwiftUI's `TextEditor` in the Query Workbench. Tab inserts four spaces; Backspace on a column that's a multiple of 4 removes the four leading spaces in one keystroke; Shift-Tab dedents. Auto-quote / dash / spell substitution disabled. Native NSTextView undo so `⌘Z` reverses an indent in one step.

### Fixed
- **CW Sweep — Vim mode swallowed every keystroke aimed at the Radio Control pane's text fields.** With vim enabled in Normal mode, clicking into the Host / Username / Password fields on the SCU-LAN10 / Icom WiFi / Flex / USB sections gave you a focus ring but no input — `VimKeyInterceptor` consumes every workspace keydown in Normal mode and routes it to the vim command parser, so backspaces and characters never reached the AppKit responder. The interceptor now treats the radio pane as settings-like and passes every key through to native input whenever `selectionState.focusedPane == .radioControl`. Click into another pane (or Tab away) to re-engage vim.
- **CW Sweep — Frequency / PTT / XIT / RIT-offset commands silently no-oped on every non-CW-Bridge transport (Flex TCP, serial CAT, IcomWiFi, SCU-LAN10).** The April set-and-verify refactor routed every `RadioSession` setter through `transport.sendSetVerify(field:value:)`. That call is part of the CW Bridge's CWBP framing protocol — only `BridgeProtocol` implements it. Every other transport inherited the default extension that returns `0x02` (UNSUPPORTED), so `sendVerified` returned `false` and *nothing was ever written to the wire*. RX kept working because Flex pushes status via subscriptions registered with `sendRaw` at connect time; tune commands just dropped on the floor. `RadioSession.sendVerified` now takes a fallback closure that encodes via the protocol handler and `transport.send`s the bytes whenever set-verify reports the field as unsupported.
- **CW Sweep — VFO frequency display jumping by powers of 10 after the bridge auto-detected the radio.** When the CW Bridge finished radio auto-detection, `RadioManager+Bridge.restartSessionAfterDetection` was creating a new `RadioSession` with the right protocol handler but couldn't `stop()` the old one (that would have torn down the shared BLE transport). The orphaned old session's receive task kept consuming `BridgeProtocol.receivedData` — a single-continuation `AsyncStream` — so each chunk went to exactly one of the two sessions and both frame assemblers saw truncated frames. New `RadioSession.cancelTasks()` cancels receive + poll tasks without touching the transport; the bridge swap path now calls it on the old session before installing the new one.
- **CW Sweep — Hunter Log spot rows no longer wrap; memberships moved to their own row.** Tightens the hunter-mode spot list so each spot stays a single line, with club/award memberships rendered in a secondary row underneath instead of pushing the primary fields onto a second line.
- **CW Sweep — Scroll-wheel events in the Query Workbench window were stealing scrolls in the main workspace window.** `ScrollWheelModifier` (used by the band scope's Canvas) installed an app-wide `NSEvent.addLocalMonitorForEvents` monitor and converted `event.locationInWindow` into the modifier-attached view's coordinate space without checking that the event came from the same window. Now gates on `event.window === self.window` before the bounds check.
- **CW Sweep — Query Workbench Schema browser now scrolls.** Replaced the `ScrollView + LazyVStack` with a native `List` (matching the saved-query sidebar) so it scrolls correctly inside `HSplitView` panes, plus an opaque `windowBackgroundColor` background so SwiftUI doesn't leave a hit-test hole.
- **CW Sweep — `scope.spot_observations.received_at` was being written as a TEXT formatted date.** GRDB's default Codable Date encoding produces a `"yyyy-MM-dd HH:mm:ss.SSS"` UTC string, not a number — so SQL like `cw_now() - received_at` would coerce the leading digits (`2026`) and silently return nonsense ages. `SpotObservationRow` now sets `databaseDateEncodingStrategy / databaseDateDecodingStrategy = .timeIntervalSince1970`, matching the column declaration, `cw_now()`, and `scope.spots.last_seen_at`.
- **iOS + CW Sweep — Journal sync no longer roasts the device on large dirty backlogs.** `CloudSyncJournalEngine.schedulePendingChanges()` now bails out early when previously-built journal records are still in flight. Without the guard, every successful 10-record CloudKit batch save fired `ModelContext.didSave` → observer reschedule → a fresh full scan of all dirty QSO + ServicePresence rows (45k+ after a Force Full Sync) and ~454 new JSON-encoded `ChangeJournal` CKRecords. The CKSyncEngine pending list grew unbounded with stale duplicates while the device burned battery.

### Changed
- **iOS + CW Sweep — Sync progress UI actually moves now.** `CloudSyncJournalEngine` gained a `didConfirmOperations(count:)` delegate callback that fires from `handleSentChanges` after each successful CloudKit round trip. `CloudSyncService` advances `uploadedCount` and rewrites the syncing-detail status (`"Uploading... N remaining"`) on every callback, so the Settings progress display reflects real progress during a Force Full Sync instead of staying frozen at the initial dirty count.

## [1.87.0] - 2026-05-04

### Added
- **CW Sweep — Waterfall is now a first-class layout panel.** The previously orphaned `WaterfallView` is exposed as `PanelIdentifier.waterfall` and can be dropped into any custom layout via the layout editor. Source-agnostic: rendering reads from a new `WaterfallStore` (@Observable) that any radio producer can push into. The placeholder state explains which radios produce spectrum data so the panel is useful even when nothing is connected.
- **CW Sweep — FlexRadio (SmartSDR) panadapter / waterfall ingestion.** New `FlexPanadapterService` (Services/Panadapter/) binds a UDP listener, sends `client udpport` + `display pan create` commands over the existing TCP control session, and decodes incoming VITA-49 frames into normalized 0..1 spectrum lines that feed the same `WaterfallStore`. Includes a small `Vita49` parser that extracts stream ID + payload from the VITA-49 header. Defaults to 1024 bins / 100 kHz / 10 fps; geometry follows the active slice frequency. Note: `xcodegen generate` must be run locally before the new `Services/Panadapter/` files appear in the Xcode project.
- **iOS Remote + CW Sweep — Waterfall forwarded to iOS over the LAN.** New `radio.waterfall` topic on the RemoteOp protocol carries 8-bit quantized spectrum lines (`WaterfallLineEvent`) plus a `WaterfallClearedEvent` whenever the active radio source changes. Sweep's `RemoteOpPublishers` observes the store and broadcasts at most 10 fps regardless of producer rate (~22 KB/s on the wire). New iOS `RemoteSweepWaterfallView` joins the Remote tab strip and only subscribes while visible, so background tabs don't pay the bandwidth cost. iOS color ramp matches macOS exactly so the panels feel identical on both ends.

### Fixed
- **Quick entry — UTC time tokens accept the same formats the paper log scanner does.** Typing `W1AW 14:30` in a quick-entry field now sets the timestamp override to 14:30 UTC for today, matching how the scanner's `TimestampExtractor` already interprets handwritten log rows. `QuickEntryParser.parseZuluTime` now accepts `HH:MM`, `HH:MMZ`, and bare `HHMM` (e.g. `0930`, `1430`) in addition to the existing `HHMMZ` / `HMMZ`. Bare 4-digit numbers that are also valid amateur frequencies (e.g. `1804` = 1.804 MHz on 160m) keep their existing frequency interpretation; users can append `Z` to force a time. Bare 3-digit times still require `Z` to avoid colliding with RST values like `599`.
- **iOS FT8 — Overload banners ("Audio is clipping" / "Audio input is too hot") firing under normal operating conditions on both built-in mic and USB-C DAC inputs.** Three compounding issues: (1) the warning RMS threshold of 0.7 (≈ –3 dBFS) flagged any decent-strength signal as "too hot" — WSJT-X targets RMS in the –30 to –10 dBFS range and reserves clipping warnings for true full-scale activity. (2) The tracker had no hysteresis, so banners flapped on/off as the rolling average crossed thresholds. (3) The waterfall used a *fixed* `[+10 dB, +50 dB]` magnitude scale, so a hot-but-unclipped input painted every bin red — the literal "washing out red" symptom in the warning copy. `FT8AudioOverloadTracker` now uses split enter/exit thresholds (enter at RMS ≥ 0.85 / 55% peak fraction with RMS ≥ 0.55, exit at RMS < 0.75 / 30% peak fraction), requires a 1.5s dwell before banner state changes, and treats the clip threshold as 0.98 (essentially full-scale only). `FT8WaterfallData` adds an EMA-smoothed noise-floor estimator (lower 25th percentile across bins per row, smoothed with α = 0.05) and renormalizes magnitude to dB-above-noise over a 30 dB span — matching WSJT-X behaviour so the colormap tracks signal-to-noise rather than absolute level. Banner advice copy updated to reflect that the meter (not the waterfall) is the real reference. `FT8AudioEngine` also now observes `AVAudioSession.routeChangeNotification` and re-installs the input tap when a USB-C DAC is plugged in or removed mid-session, preventing stale-format clipping after route swaps.

- **CW Sweep — Frequency / PTT / XIT / RIT-offset commands silently no-oped on every non-CW-Bridge transport (Flex TCP, serial CAT, IcomWiFi, SCU-LAN10).** The April set-and-verify refactor (`feat(bridge): add set-and-verify with semantic radio commands`) routed every `RadioSession` setter through `transport.sendSetVerify(field:value:)`. That call is part of the CW Bridge's CWBP framing protocol — only `BridgeProtocol` implements it. Every other transport inherited the default extension that returns `0x02` (UNSUPPORTED), so `sendVerified` returned `false` and *nothing was ever written to the wire*. RX kept working because Flex pushes status via subscriptions registered with `sendRaw` at connect time; tune commands just dropped on the floor. `RadioSession.sendVerified` now takes a fallback closure that encodes via the protocol handler and `transport.send`s the bytes whenever set-verify reports the field as unsupported — restoring the pre-refactor behavior for non-bridge transports while leaving the bridge's verified path intact.

## [1.86.0] - 2026-05-04

### Added
- **CW Sweep + iOS Query Workbench — Distance, bearing, and time SQL functions.** New `cw_*` custom SQL functions registered on every `QueryReader` connection: `cw_distance_km / cw_distance_mi / cw_bearing_deg(lat1, lon1, lat2, lon2)`, `cw_grid_distance_km / cw_grid_distance_mi / cw_grid_bearing_deg(grid1, grid2)`, plus user-relative helpers `cw_user_grid()`, `cw_user_grid_distance_km(grid)`, `cw_user_grid_distance_mi(grid)`, `cw_user_grid_bearing_deg(grid)`, `cw_user_distance_km(lat, lon)`, `cw_user_distance_mi(lat, lon)`, `cw_user_bearing_deg(lat, lon)`, and `cw_now()` (Unix epoch seconds REAL, matches `last_seen_at` / `received_at` units). The user-relative variants pull the configured grid from `UserDefaults["myGrid"]` on every call so Settings changes take effect without reopening the database. Returns `NULL` on invalid grids / NULL coords so they compose with `ORDER BY ... NULLS LAST` and `WHERE ... < 50`. Two new starter queries — "Spots sorted by nearest" and "Spots heard by nearby spotters (≤ 50 km)" — demonstrate the use cases against `scope.spots`, `scope.spot_observations`, and `scope.spotters`.
- **CW Sweep — `scope.spot_observations` now denormalizes the spotted (DX) station's coordinates.** New `spot_lat REAL` and `spot_lon REAL` columns populated at observation-write time from the DX `dxGrid` (precise grid centre when known) or the DXCC entity centroid for the spotted callsign as a fallback. Lets distance queries hit `scope.spot_observations` directly without joining through anything to compute the user → DX great-circle distance.
- **CW Sweep — Query Workbench results pane redesigned.** Full-width / full-height table that pins to the top-left of its pane (regardless of how few rows came back), alternating row striping, click-to-sort column headers (three-state: ascending → descending → cleared, with a blue chevron indicator and stable sort that keeps NULLs last), and a "Copy CSV" button in the results header that writes the entire result set to the clipboard as RFC 4180 CSV (`\r\n` line endings, double-quote escaping).
- **CW Sweep — Custom SQL editor with code-editor key behaviors.** New `SQLTextEditor` (NSViewRepresentable wrapping `NSTextView`) replaces SwiftUI's `TextEditor` in the Query Workbench. Tab inserts four spaces; Backspace on a column that's a multiple of 4 removes the four leading spaces in one keystroke when the line is whitespace-only up to the caret; Shift-Tab dedents the current line by up to four spaces. Auto-quote / dash / spell substitution disabled (annoying in SQL). Native NSTextView undo so `⌘Z` reverses an indent in one step.

### Fixed
- **CW Sweep — Scroll-wheel events in the Query Workbench window were stealing scrolls in the main workspace window.** `ScrollWheelModifier` (used by the band scope's Canvas) installs an app-wide `NSEvent.addLocalMonitorForEvents` monitor and converts `event.locationInWindow` into the modifier-attached view's coordinate space without first checking that the event came from the same window. A scroll over the Query Workbench's schema browser would convert workbench-window coordinates as if they were workspace-window coordinates, occasionally land inside the band scope's bounds, fire its action, and consume the event — making the foreground scroll wheel "scroll the window underneath." Now gates on `event.window === self.window` before the bounds check.
- **CW Sweep — Query Workbench Schema browser now scrolls.** Replaced the `ScrollView + LazyVStack` with a native `List` (matching the saved-query sidebar) so it scrolls correctly inside `HSplitView` panes, plus an opaque `windowBackgroundColor` background so SwiftUI doesn't leave a hit-test hole.
- **CW Sweep — `scope.spot_observations.received_at` was being written as a TEXT formatted date.** GRDB's default Codable Date encoding produces a `"yyyy-MM-dd HH:mm:ss.SSS"` UTC string, not a number — so SQL like `cw_now() - received_at` would coerce the leading digits (`2026`) and silently return nonsense ages. `SpotObservationRow` now sets `databaseDateEncodingStrategy / databaseDateDecodingStrategy = .timeIntervalSince1970`, so `received_at` is stored as Unix epoch seconds REAL — matching the column declaration, `cw_now()`, `scope.spots.last_seen_at`, and `strftime('%s', 'now')`.

### Fixed
- **iOS POTA Activations — `EXC_BREAKPOINT` crash when CKSyncEngine merged a CloudKit update mid-render.** `ActivationRow.body` reads `activation.hasQSOsToUpload`, which used to call `pendingQSOs()` and walk each QSO's `servicePresence` SwiftData relationship on every body recompute. If CloudKit returned a `_InvalidFutureBackingData` placeholder (rows the engine knew about but hadn't materialized yet), reading `ServicePresence.serviceTypeRawValue` triggered a Swift runtime assertion and killed the app. `POTAActivation` now precomputes `pendingCount`/`submittedCount`/`uploadedCount`/`isFullyUploaded`/`isRejected`/`parksNeedingUpload`/`uploadStatusSummary`/`parks` at struct init via the new `POTAActivation+UploadSnapshot.swift`, so view-body reads are pure value lookups. `POTAActivationsContentView.activations` moved from a body-computed property to `@State`, refreshed once inside `loadParkQSOs`, and the QSO fetch descriptor now passes `relationshipKeyPathsForPrefetching: [\QSO.servicePresence]` so the relationship is materialized at fetch time rather than lazily during render.
- **iOS FT8 — "Call CQ" menu options (CQ / CQ POTA / CQ DX / CQ SOTA) silently did nothing.** The channel-picker sheet was driven by `.sheet(isPresented:)` plus a separate `pendingCQModifier` state, and the two writes from a `Menu` button action were racing the menu's own dismissal animation on iOS 18+ — the sheet would never present. Refactored to a single `FT8ChannelPickerToken: Identifiable` driving `.sheet(item:)`, and the menu action now defers via `Task { @MainActor }` so the state mutation lands after the menu is gone. Same fix in `FT8SessionView` and `ActivityLogFT8View`.
- **iOS FT8 — "Audio is clipping" banner firing whenever the rig was hooked up regardless of output level.** The overload tracker keyed off RMS thresholds, but iOS AGC keeps mic input at ~0.3–0.5 RMS no matter how low you set the radio, so the critical threshold was effectively always tripped. `FT8AudioOverloadTracker` now reads peak magnitude from the new `FT8AudioLevel` struct and only fires `.critical` when ≥40% of recent buffers had a peak ≥ 0.97 (real digital clipping); RMS is only used for a softer "too hot" warning at 0.7. `FT8AudioEngine` reports both rms + peak via `vDSP_rmsqv`/`vDSP_maxmgv`.

### Changed
- **iOS FT8 — Replaced the No Signal / Low / OK / Hot status pill with an inline EQ-style level meter.** New `FT8AudioLevelBar` shows 8 ascending pips that light up green → yellow → red as the live RMS climbs, with a peak indicator dot above the bar when the buffer hits clipping. The whole row remains tappable to expand the existing audio diagnostics panel. Removes `FT8StatusPillView`.

### Fixed
- **CW Sweep — VFO frequency display jumping by powers of 10 after the bridge auto-detected the radio.** When the CW Bridge finished radio auto-detection, `RadioManager+Bridge.restartSessionAfterDetection` was creating a new `RadioSession` with the right protocol handler but couldn't `stop()` the old one (that would have torn down the shared BLE transport). The orphaned old session's receive task kept consuming `BridgeProtocol.receivedData` — a single-continuation `AsyncStream` — so each chunk went to exactly one of the two sessions and both frame assemblers saw truncated frames. Decoded frequencies were partial-BCD/ASCII garbage flickering between e.g. 0.14066, 14.066, 140.66 MHz. New `RadioSession.cancelTasks()` cancels receive + poll tasks without touching the transport; the bridge swap path now calls it on the old session before installing the new one.
- **iOS Remote — Tune commands silently failing with `DefunctConnection` after CW Sweep restarts.** `NWConnection`'s `stateUpdateHandler` doesn't always fire when the peer dies silently, so the iOS client kept holding a half-open TCP socket and threw a low-level `NWError -65569` on the first send. `RemoteSweepClient.sendFrame` now catches the send error and explicitly cancels the connection so the state handler reports `.cancelled` and the coordinator returns to the disconnected state instead of leaving the user on a zombie session.
- **iOS Remote — Keyboard didn't dismiss after typing a tune frequency.** Added `@FocusState` on the field, a Done button on the keyboard toolbar, `.scrollDismissesKeyboard(.immediately)`, and a tap-outside gesture so the form dismisses the decimal pad when the user taps anywhere else.
- **iOS Remote — `invalid_payload: decode failed` on connect after a CW Sweep update.** Ensures Sweep is restarted with the matching CarrierWaveCore that knows the new CW frame cases; the underlying confusion was a stale Sweep process running pre-CW-frames code. (No code change beyond the build/process discipline.)

### Changed
- **iOS Remote CW pane redesigned for "phone as dashboard accessory" use.** Slot buttons are now an adaptive `LazyVGrid` (2 columns portrait, 3–4 landscape) of ≥84pt tiles — each tile shows the slot label as a bold `.title3` headline and the raw template text as a monospaced footnote so you can see exactly what each button will key. STOP, CUSTOM, and a new PRESETS tile share the same large tile shape. Empty slots render as ghost `+ Slot N` tiles instead of a tiny capsule strip. Replaces the previous horizontally-scrolling capsule row.
- **iOS Remote CW keyer reads its macro context from CW Sweep's Quick Entry box.** Removed the parallel "current QSO" entry strip from the iOS Remote CW pane — Sweep is now the single source of truth for `{CALL}` / `{HISCALL}` / `{RST}` / `{NAME}` / `{HISSTATE}` / `{FREQ}` / `{MYCALL}`. New `SelectionState.parsedQuickEntry` / `entryCallsign` / `entryCallsignName` / `entryCallsignState` mirror the live Quick Entry parser + callsign-info lookup; `RemoteOpService.currentCWMacroContext()` builds the macro dict from those plus the Keychain `currentCallsign` and `RadioManager.frequency`. `handlePlayCWSlot` merges any client-supplied keys on top (Sweep wins for empty values), so iOS just sends the slot id and Sweep expands at play time. `RemoteCWMacros.known` gained `HISSTATE` (resolved from the QRZ/HamDB state lookup of the entry callsign).

### Added
- **iOS Remote CW keyer presets — POTA bundle.** New `CWKeyerPreset` model with built-in POTA preset; the new "PRESETS" tile in the keyer grid opens a menu and the POTA entry programs slot 1 (`CQ CQ POTA DE {MYCALL} K`) and slot 2 (`BK RR TU {HISSTATE} ES 73 EE`) via repeated `cwSetSlot` calls. Macros stay in the slot text — Sweep expands them per QSO from its Quick Entry.

### Fixed
- **iOS + Server — "Friend request not found" error when accepting a request even though the request actually got accepted.** Two fixes: (1) `POST /v1/friends/requests/:id/accept` is now idempotent — if the request is already accepted and the caller is the addressee, the handler returns the existing record at 200 instead of 404. The previous query had `WHERE id=$1 AND status='pending'`, so any second call (double-tap, two devices, retry) saw `status='accepted'` and returned `FRIEND_REQUEST_NOT_FOUND` even though the underlying state was correct — which is why "kill the app and reopen and they're friends." (2) `IncomingRequestRow` now disables its Accept/Decline buttons (and shows a small `ProgressView`) while a request is in flight; `FriendsListView` tracks per-friendship in-flight state in a `Set<UUID>` so accidental double-taps can't spawn two API calls.
- **iOS + CW Sweep — Journal sync no longer roasts the device on large dirty backlogs.** `CloudSyncJournalEngine.schedulePendingChanges()` now bails out early when previously-built journal records are still in flight. Without the guard, every successful 10-record CloudKit batch save fired `ModelContext.didSave` → observer reschedule → a fresh full scan of all dirty QSO + ServicePresence rows (45k+ after a Force Full Sync) and ~454 new JSON-encoded `ChangeJournal` CKRecords. The CKSyncEngine pending list and `pendingJournalRecords` array grew unbounded with stale duplicates while the device burned battery doing thousands of redundant SwiftData scans without making upload progress. The next collection pass now runs only after the prior batch fully drains.

### Changed
- **iOS + CW Sweep — Sync progress UI actually moves now.** `CloudSyncJournalEngine` gained a `didConfirmOperations(count:)` delegate callback that fires from `handleSentChanges` after each successful CloudKit round trip. `CloudSyncService` advances `uploadedCount` and rewrites the syncing-detail status (`"Uploading... N remaining"`) on every callback, so the Settings progress display reflects real progress during a Force Full Sync instead of staying frozen at the initial dirty count until the whole sync finishes.

### Added
- **iOS + CW Sweep — Sessions continue between Field and Sweep automatically (alpha).** Starting a POTA/SOTA/contest activation on either device now propagates to the other without pressing Sync, Connect, or anything else. Three layers cooperate so this works whether the devices are co-located or apart: (1) `CloudSyncJournalEngine` posts a new `cwLoggingSessionRemotelyChanged` notification after applying inbound `LoggingSession` upserts and runs an active-session normalizer in the same transaction (most-recent-`startedAt` stays `.active`, older actives flip to `.paused` with `cloudDirtyFlag=true`); on iOS, `LoggingSessionManager+Continuity` adopts the new winner and re-runs the full session lifecycle (Live Activity, GPS, radio reconnect, auto-spot, UTC-midnight); on macOS, `StatusBarView` / `ActivationHeader` already observe `ModelContext.didSave` so they refresh for free. (2) `RemoteSweepAutoConnect` watches Bonjour and silently re-establishes the LAN link to the previously-paired Sweep on every app foreground / network change — no taps, manual pairing only on first run. (3) New `activeSession` RemoteOp topic carries a `RemoteSessionState` snapshot (id, status, callsign, mode, frequency, programs, parkRef, qsoCount, …) — Sweep broadcasts on every local active-session change via `RemoteOpSessionBroadcaster`, and Field pushes its own active-session over `commandSetActiveSession` whenever `LoggingSessionManager.activeSession` flips (detected via `withObservationTracking`). All three paths converge on the same conflict rule, so they're idempotent and self-healing. New files: `SessionContinuityNotifications.swift`, `RemoteSessionStateBridge.swift`, `RemoteOpSessionFrames.swift`, `LoggingSessionManager+Continuity.swift`, `RemoteSweepAutoConnect.swift`, `RemoteSweepCoordinator+Session.swift`, `RemoteSweepCoordinator+CW.swift`, `RemoteOpService+Session.swift`, `RemoteOpConnection+Session.swift`.
- **iOS + CW Sweep — Phone-to-Mac remote control (alpha).** New experimental feature `Remote Control of CW Sweep`. Pairs Carrier Wave: Field on iPhone with CW Sweep over a Bonjour-discovered TCP link (`_cwsweep-remote._tcp`) and a shared `RemoteOp` Codable wire protocol in `CarrierWaveCore`. iOS browses, picks a Sweep, types the 6-digit code shown in `Settings → Remote` on the Mac, and gets back a long-lived bearer token persisted in the iOS Keychain. Once paired, Field shows live `radio.state` (frequency, mode, transmit indicator) and the Sweep-side curated spot feed (`spots.feed`); tapping a spot or typing a frequency sends a `radio.tune` command back to Sweep, which routes it through `RadioManager.tuneToFrequency` / `setMode`. New macOS pieces: `RemoteOpService` (`@MainActor @Observable` Bonjour-advertising NWListener + paired-device registry), `RemoteOpConnection` actor (per-client receive loop, hello/pair handshake, subscription registry), `RemoteOpPublishers` (`withObservationTracking` bridge from `RadioManager` and `SpotAggregator`), and a `RemoteSettingsTab`. New iOS pieces: `RemoteSweepDiscovery`, `RemoteSweepClient` actor, `RemoteSweepCoordinator` `@Observable` hub, Keychain helper, and the `Remote` tab (root → discovery → pairing → connected radio/spots panes). Hidden by default; enable from Settings → Experiments. v1 is LAN-only, plain TCP with token auth — TLS, push notifications, voice/CW keyer trigger, FT8 monitoring, and audio streaming are follow-ups.

## [CW Sweep 0.10.0] - 2026-05-02

### Added
- **CW Sweep:** Full CW Bridge support over BLE (CWBP). New "CW Bridge" entry in the radio model picker; the Radio Control tab exposes a dedicated section for scanning, pairing, connecting, and monitoring the bridge. Implementation ports the iOS BLE stack to macOS — `BLERadioTransport` actor around CoreBluetooth NUS, `BLEDelegate` for the CB central/peripheral callbacks, `BridgeProtocol` actor providing CWBP framing (handshake, CAT passthrough, set-verify, CW keyer commands) that conforms to `RadioTransport`, and `BridgeFrame` protobuf builders/parsers using the shared `CarrierWaveCore` generated types. New `BridgeDiscoveryService` handles BLE scan / pair / forget with persisted UUID. `RadioManager+Bridge` orchestrates the connect flow: BLE connect → CWBP handshake → bridge-side radio auto-detection → hot-swap RadioSession with the correct protocol handler (`CIV`/`Kenwood`/`Elecraft`) via `BridgeRigDetector`. Live status card shows firmware version, USB presence, detected radio, handshake state, and keyer availability, with a Re-detect button. `NSBluetoothAlwaysUsageDescription` added to Info.plist.
- **CW Sweep:** "What's New" sheet on first launch after an app update. Bundled per-version release notes from `WhatsNewCatalog`, tagged by kind (New / Improved / Fixed) and platform; suppresses notes on a fresh install.
- **CW Sweep:** Integrated server-published contest definitions (format v0.3) shared with iOS — fetches from `GET /v1/contests` with 24h refresh, drives scoring, dupe checking, exchange parsing, and Cabrillo export from a single shared `ContestDefinition` model.
- **CW Sweep:** SKCC (Straight Key Century Club) spot enrichment. SKCC member badges appear in the spot inspector header alongside a longer name / SPC line in the operator section. Roster downloaded once per day from `skccgroup.com` and cached via `SKCCMembershipStore` (shared with iOS).
- **CW Sweep:** Share UI for callsigns, QSOs, parks, and SOTA summits via `NSSharingServicePicker`. Recipients with Carrier Wave installed deeplink straight to the relevant detail view via `https://carrierwave.app/link/<kind>/<id>`. Log data lives entirely in the URL fragment and never reaches a server.
- **macOS:** Band scope redesigned with structured rows, diagonal leader lines from a linear frequency axis, and row displacement for crowded spots. Vim-style keyboard navigation (j/k spots, J/K mults, h/l pan, ? help). Right-click context menu (tune, copy callsign, QRZ lookup, watch marker, show in list). Fit-to-spots zoom (0 key or FIT button). Keyboard shortcut help overlay (? key).

### Changed
- **iOS + macOS — iCloud sync is now journal-only.** Removed the per-record `CKSyncEngine` path (`CloudSyncEngine`, `CKRecordMapper`, `CloudSyncDeduplicationRepair`, `CloudSyncPendingRecord`, `CloudSyncReport` and friends). Both Carrier Wave (iOS) and CW Sweep (macOS) now use only `CloudSyncJournalEngine`: dirty records are batched into `ChangeJournal` CKRecords plus a periodic SQLite snapshot for new-device bootstrap. The "Journal Sync" toggle in Settings is gone (along with the iCloud KVS mirror of `cloudSyncJournalMode`); journal is the only path. CW Sweep's settings dropped the Sync Report / Sync Repair UI for the same reason. Existing per-record CKRecords in users' CloudKit zones are left in place; they're invisible to the journal engine and will be cleaned up in a future zone wipe. CW Sweep also now re-fetches journal entries on `NSApplication.didBecomeActiveNotification`, mirroring the iOS `scenePhase == .active` trigger so QSOs logged on iOS appear on Mac the moment the window comes forward.

### Security
- **Firmware (CW Bridge):** BLE NUS link now requires LE Secure Connections + MITM-protected pairing. The bridge generates a random 6-digit passkey on each first-pair attempt, displays it on the OLED, and macOS prompts the user to enter it. Bonds persist in NVS (max 4) so paired Macs reconnect silently. The NUS RX characteristic requires authenticated encryption; `Ble::send` refuses to notify while the link isn't encrypted, closing the window where an unbonded peer could inject CAT commands or passively snoop USB / jack / radio-info broadcasts.

## [1.85.0] - 2026-05-02

### Added
- **iOS — Brag sheets, redesigned and shareable as images.** Every session brag sheet (TOTA, POTA, contests, casual, periodic stats) now uses a unified purple-gradient look driven from a shared `BragSheetTheme` (gradient, inset background, chip pill style, stat columns). The TOTA brag sheet (`TOTABragSheetView`) is the canonical card: tile name headline, big score with `ESTIMATED`/`OFFICIAL` label, contact map (geodesic arcs from QTH to chasers, themed via `FlatMapRenderer` when the user picked a custom map style), path map (track polyline + dashed tile-boundary outline drawn via Canvas so it snapshots cleanly), bonus chip row, eight-column stat grid (QSOs / Distance / Bands / Duration / DXCC / Farthest / Modes / Q/hr), equipment chips, and a mini timeline. Reachable from the session detail `⋯` menu (Brag Sheet) and from the end-of-session brag step. Sharing is image-based (matches the existing POTA share path): `TOTABragSheetRenderer` pre-renders the contact map to a UIImage and then snapshots the whole card with `BragSheetImageRenderer`/`ImageRenderer`, so the resulting PNG includes maps and lands cleanly in Copy Image / Save Image / AirDrop / Messages. POTA's `ActivationShareCardView` and the periodic `BragSheetShareCardView` were re-skinned with the same theme.
- **iOS — Edit TOTA fields after the session.** `SessionMetadataEditSheet` gains a TOTA section exposing category (Standard/Mobile), distance, elevation gain, ruck weight, winter override, first-activation-of-tile-ever, and all the bonus toggles (pets, kids, Winlink, APRS, VarAC, adaptive). PEF stays read-only because the rules require it to be frozen at session start. The whole section disables and shows a "Locked: submitted to TOTA" notice once `totaOfficialPoints` is set.
- **iOS — Distance-zero banner on TOTA score.** The TOTA section in `SessionDetailView` now shows an orange "Distance is 0 — TOTA Standard requires a non-zero distance. Enter activation distance or record a track to score." banner when the operator has QSOs but no distance recorded — explains why the score reads 0 instead of leaving it as a silent mystery.
- **iOS — TOTA icon on session rows.** `LoggingSession.programsIcon` now returns `square.grid.3x3.fill` for sessions tagged TOTA, alongside the existing tree/leaf/mountain icons for POTA/WWFF/SOTA. Added an `isTOTA` helper.
- **iOS — TOTA sessions go to the detail view, not the recording player.** `SessionsView.sessionNavigationRow` previously routed any session with a WebSDR recording attached to the `RecordingPlayerView`. TOTA sessions now go to the regular `SessionDetailView` (which renders the TOTA section); the recording is still reachable from inside the detail view.
- **iOS — TOTA brag sheet entry in the menu.** The session detail's `⋯` menu has a "Brag Sheet" entry for TOTA sessions that opens `TOTABragSheetSheet` (with the new shareable card + Share button). Non-TOTA sessions still fall back to the existing `onShare` callback.
- **iOS — `WhatsNewItem` link support.** The `WhatsNewSheet` items can now carry an optional URL + label, rendered as a small "Learn more →" link below the detail. Used by the TOTA entry to point at tilesontheair.com.
- **iOS — On-demand "What's New" in Settings.** Settings → About now has a "What's New" row that opens the release-notes sheet on demand instead of only on first launch after an update. The Version row reads from the bundle now (was hardcoded to "1.84.2" in the prior release).
- **iOS — TOTA score & summary log enrichment.** A four-tier client-side scoring engine (`CarrierWaveCore.TOTAScoringEngine`) mirrors the rules' Standard and Mobile formulas (mode weights, T3 boost, QRP ×2, winter/ruck/elev/pets/kids percentages, Winlink/APRS/VarAC flat bonuses, PEF distance scaling, defensive WL/APRS/VARAC QSO exclusion). The session detail view gets a dedicated TOTA section between the hero and QSO list: tile name + total score in the hero line, a path map with track polyline + tile-boundary overlay + GPX export, the four-tier ledger (Confirmed / Estimated / Asserted / Pending), bonus chip row, T3 candidates list, PEF badge, and a refresh-spots button with snapshot timestamp. The end-of-session flow shows a condensed TOTA card (tile + total + last-chance edits for winter override and first-ever-tile assertion). The brag-sheet `ActivityItem` now ships TOTA tiles, score, distance, elevation, bonus flags, and PEF to clubmates so their feed cards reflect the activation; a follow-up post-upload step replaces the in-app estimate with the server-returned `totaOfficialPoints`. T3 candidates are derived from a one-shot TOTA spots feed correlation at session end (6h preceding window, closest-spot-wins). Eight new optional `LoggingSession` fields plus a `TOTACategory` enum and `T3Candidate` value type carry the operator inputs and cached snapshots. Personal Effort Factor lives in TOTA settings as a profile default copied onto each new session at start (frozen after). Full design + worked example: `docs/features/tota-scoring.md`. A four-tier client-side scoring engine (`CarrierWaveCore.TOTAScoringEngine`) mirrors the rules' Standard and Mobile formulas (mode weights, T3 boost, QRP ×2, winter/ruck/elev/pets/kids percentages, Winlink/APRS/VarAC flat bonuses, PEF distance scaling, defensive WL/APRS/VARAC QSO exclusion). The session detail view gets a dedicated TOTA section between the hero and QSO list: tile name + total score in the hero line, a path map with track polyline + tile-boundary overlay + GPX export, the four-tier ledger (Confirmed / Estimated / Asserted / Pending), bonus chip row, T3 candidates list, PEF badge, and a refresh-spots button with snapshot timestamp. The end-of-session flow shows a condensed TOTA card (tile + total + last-chance edits for winter override and first-ever-tile assertion). The brag-sheet `ActivityItem` now ships TOTA tiles, score, distance, elevation, bonus flags, and PEF to clubmates so their feed cards reflect the activation; a follow-up post-upload step replaces the in-app estimate with the server-returned `totaOfficialPoints`. T3 candidates are derived from a one-shot TOTA spots feed correlation at session end (6h preceding window, closest-spot-wins). Eight new optional `LoggingSession` fields plus a `TOTACategory` enum and `T3Candidate` value type carry the operator inputs and cached snapshots. Personal Effort Factor lives in TOTA settings as a profile default copied onto each new session at start (frozen after). Full design + worked example: `docs/features/tota-scoring.md`.
- **iOS:** Foundation for Tiles on the Air (TOTA) integration. New `TOTAClient` (Supabase edge functions at `icneuzxitdqtofutxbla.supabase.co/functions/v1`, `x-api-key` auth via Keychain) covers spots fetch (`GET /spots`, the same feed shown on tilesontheair.com — anonymous reads work but rate-limit at 30 req/min vs 120 with a key, and the cache header asks pollers to stay above 30 s), activation create (`POST /activations` JSON, which is also what self-spots an operator on the public feed — TOTA collapses "log this outing" and "I'm on the air now" into one record), and ADIF upload (`POST /activations` multipart, server-parsed ADIF 3.x with server-side point calculation). Added `ActivationType.tota` to `LoggingSession` so a session can be tagged TOTA and `KeychainHelper.Keys.totaApiKey` for the credential. New **Settings → Sync Services → Tiles on the Air** screen handles API-key entry/removal, a connection test (a small `GET /spots` round-trip carrying the key, since TOTA exposes no dedicated validate endpoint), and manual ADIF upload via `.adi`/`.adif` file picker (security-scoped resource, UTF-8 read, multipart POST, surfaces the server-calculated points + canonical Maidenhead grid back in the UI). Sync-pipeline wiring (`ServiceType.tota`, `SyncService+Upload`) and live `SpotMonitoringService` integration remain TODO — the spots-fetch entry point is callable but isn't yet polled into the unified spots feed.

### Changed
- **iOS + macOS — iCloud sync is now journal-only.** Removed the per-record `CKSyncEngine` path (`CloudSyncEngine`, `CKRecordMapper`, `CloudSyncDeduplicationRepair`, `CloudSyncPendingRecord`, `CloudSyncReport` and friends). Both Carrier Wave (iOS) and CW Sweep (macOS) now use only `CloudSyncJournalEngine`: dirty records are batched into `ChangeJournal` CKRecords plus a periodic SQLite snapshot for new-device bootstrap. The "Journal Sync" toggle in Settings is gone (along with the iCloud KVS mirror of `cloudSyncJournalMode`); journal is the only path. `CloudSyncRecordCounts` no longer carries `syncedRecords` / `totalSynced` — those were per-record concepts. CW Sweep's settings dropped the Sync Report / Sync Repair UI for the same reason. Existing per-record CKRecords in users' CloudKit zones are left in place; they're invisible to the journal engine and will be cleaned up in a future zone wipe. CW Sweep also now re-fetches journal entries on `NSApplication.didBecomeActiveNotification`, mirroring the iOS `scenePhase == .active` trigger so QSOs logged on iOS appear on Mac the moment the window comes forward.

### Fixed
- **iOS:** Frequency entry on the Start Session sheet (and anywhere `FrequencyFormatter.parse` is used — QSO edit sheet, hunt log, command bar) silently dropped values containing thousands separators like `14,060`. `Double("14,060")` returns `nil` regardless of locale, so the session started with no frequency and the operator was left with a "set the frequency" warning plus a backlog of QSOs logged at unknown band. The parser now strips commas before delegating to `Double`, so `14,060`, `14,060 kHz`, and `146,520` all parse to the expected MHz value. Reported by an en-AU TestFlight tester.
- **iOS:** Editing a QSO in the Logs tab no longer requires picking the band manually after entering a frequency. `QSOEditSheet` now auto-derives the band via `BandUtilities.deriveBand` whenever the typed frequency lands in an amateur range, and Save is no longer disabled when the band picker is empty as long as the frequency is parseable. Removes the "I had to choose the band as well, otherwise it wouldn't accept it" workaround.
- **iOS:** The in-session QSO edit sheet (tap a logged contact in the active logger) now exposes Frequency and the resulting Band. Previously the sheet had only callsign, time, RST, name, location, and park — meaning a CW operator who got a frequency wrong mid-session ("the comma issue above") could open the edit sheet, look at the contact, and have no field to fix. Frequency input here also auto-derives the band on change.
- **iOS:** Scrolling all the way down then back up on the Start Session sheet caused noticeable jitter — the form would resist returning to the top until force-scrolled. The bottom warning banner ("Set your callsign in Settings → About Me", "POTA requires park reference", etc.) was implemented as a `.safeAreaInset(edge: .bottom)` whose inner `Text` recomputed `startDisabledReason` on every body re-eval. Combined with the `.contentMargins(.bottom, 60, for: .scrollContent)` reservation already on the form, the safe-area layout kept fighting the scroll geometry. Switched the banner to `.overlay(alignment: .bottom)` so it floats visually but doesn't influence the scroll layout; the existing content margin still reserves enough scroll room for the last fields.
- **iOS (iPad):** Sidebar tabs (Dashboard, Sessions, Logs, etc.) became unresponsive after navigating into Hunter Log from the Dashboard card — taps highlighted the new selection but the detail pane kept showing Hunter Log. Tapping the Settings entry was the only way out, because that branch forces a complete detail rebuild via `if iPadShowsSettings { ... }`. Root cause: `ActivityLogView` is pushed via `.navigationDestination(isPresented:)` inside `SessionsIdleView`, which on iPad runs without an inner `NavigationStack` (intentionally, to avoid the snapshot-time `UINavigationBar` assertion documented in `ContentView+iPadDetail.swift`). The push therefore lives on `NavigationSplitView`'s implicit detail-column stack, which doesn't pop when the sidebar selection changes. Adding `.id(selectedTab)` to the detail pane forces SwiftUI to rebuild the column whenever the sidebar selection changes, popping any stuck push.
- **iOS:** Cleaned up two pre-existing main-actor isolation errors in `QRZClient+Upload.swift` that were blocking device builds: `CallsignAliasService.extractBaseCallsign` is now `nonisolated` (the method is pure String slicing), and `executeQRZUpload` no longer captures `SyncDebugLog.shared` outside its `MainActor.run` blocks.
- **iOS:** Hunter Log "Loading spots..." would sit indefinitely when first opened. `PollingCoordinator.register(...)` documented `fireImmediately: true` as "next tick" — meaning the very first spot fetch waited up to a full 60 s tick interval before running, and if that first fetch returned zero spots (offline, no current activity) the empty `hunterSpots` array left the spinner showing forever, indistinguishable from a real "still loading" state. `register` now actually fires the closure on registration when `fireImmediately: true`, and `SpotMonitoringService` exposes a `hasFetchedHunterSpots` flag so `ActivityLogSpotsList` switches from the loading state to the empty state once the first fetch completes regardless of result. Also corrected the empty-state copy ("every 45 seconds" → "about every 2 minutes") to match the actual polling cadence.
- **iOS:** Severe device heating / battery drain when the WiFi CAT-control transport (Icom RS-BA1, used by IC-705 etc.) was unable to reach the radio. The UDP receive thread used `SO_RCVTIMEO` for pacing, but `recv()` returns immediately with `ECONNREFUSED` when the kernel sees an ICMP "port unreachable" reply — the loop's error path had no backoff and pinned a CPU core for each of the two channels (control + CIV). On top of that, a failed `IcomWiFiTransport.connect()` (auth timeout, bad credentials, wrong IP) left both UDP channels' receive threads and sockets running, so each retry leaked another pair of spinning threads. `UDPChannel.receiveLoop` now backs off 500 ms on unexpected `recv()` errors instead of busy-looping, and `IcomWiFiTransport.connect()` now stops both channels if `authenticate()` throws so failed attempts no longer accumulate threads.

## [1.84.2] - 2026-04-29

### Fixed
- **iOS:** WatchConnectivity activate/deactivate loop draining battery for users with no paired Apple Watch. Apple's recommended pattern is to call `WCSession.activate()` from `sessionDidDeactivate(_:)` so a newly-paired Watch can take over, but with no Watch paired (or the Watch app not installed) the system immediately deactivates again, producing a tight reactivation loop that pinned a CPU core. `PhoneSessionDelegate` now throttles re-activation to once every 30s via an `NSLock`-backed `WCReactivationThrottle`. Companion to the earlier coordinated polling fix in 1.84.0. (CAR-239)

## [1.84.1] - 2026-04-27

### Fixed
- **iOS:** SOTA spot taps in the HUNT panel now prefill the logger form (callsign, frequency, summit ref + name + points in notes). Previously the row tap was wired to an empty closure and silently dropped. FT8 in-session routing also now recognizes SOTA spot taps.
- **iOS:** Split ADIF export now emits one ADIF per park for N-fer POTA sessions. Previously a 5-fer produced a single file with comma-separated `MY_POTA_REF`, and the "Split by Park" toggle didn't even appear when every QSO shared the same multi-park reference. The split engine now fans out each multi-park QSO into one group per park (each file's `MY_POTA_REF` carries only that park) and the sheet's detector treats any session with multi-park refs as splittable. New `ADIFExportServiceSplitTests` covers 5-fer, 3-fer, single-park, and mixed cases.

## [1.84.0] - 2026-04-26

### Changed
- **iOS — no more silent ModelContainer auto-wipe.** Replaces the prior recovery-via-wipe behavior in `ContainerSetup.createModelContainer` with an explicit user-confirmed flow. When `ModelContainer.init` throws on launch, the broken `default.store` is now preserved in place (and copied to `Library/EmergencyBackup/`); the app constructs an in-memory fallback container and the WindowGroup routes to a new full-screen `RecoveryModeView` instead of `ContentView`. The view shows what happened (timestamp + error from `Library/ContainerInitFailure.json`), the QSO count of the most recent backup snapshot, and three explicit actions: **Restore from this backup** (stages a normal `BackupService` restore, exits the app to apply on next launch), **Send diagnostics** (presents the existing `SendDiagnosticsView`), and **Reset to empty database** (typed-confirmation gate — type `RESET` to enable the destructive button). The user is locked into recovery mode across launches until they pick one. Triggered by AC9M's data-loss incident — `docs/investigations/2026-04-26-qso-dataloss-AC9M.md` for the full context. (CAR-246)

### Added
- **iOS data-loss debuggability.** `ContainerSetup.createModelContainer` now persists a `Library/ContainerInitFailure.json` record (timestamp, error description + type, app/build version, store/WAL/SHM file sizes, emergency-backup filename) before falling back. The diagnostic bundle ships this record and every `Library/EmergencyBackup/database-*.sqlite[-wal|-shm]` under an `emergency-backup/` prefix so future incidents arrive with the broken store + structured "why" attached.
- **iOS:** `LSSupportsOpeningDocumentsInPlace` + `UIFileSharingEnabled` in Info.plist. The app now appears under "On My iPhone" → Carrier Wave in Files.app, exposing `Documents/QSOLedger/*.adi` for self-service ADIF recovery without requiring the in-app share UI.

### Security
- **Firmware:** BLE NUS link now requires LE Secure Connections + MITM-protected pairing. The bridge generates a random 6-digit passkey on each first-pair attempt, displays it on the OLED, and iOS/macOS prompt the user to enter it. Bonds persist in NVS (`CONFIG_BT_NIMBLE_NVS_PERSIST=y`, max 4) so paired phones/Macs reconnect silently. The NUS RX characteristic requires authenticated encryption (`BLE_GATT_CHR_F_WRITE_ENC | BLE_GATT_CHR_F_WRITE_AUTHEN`, 16-byte min key); `Ble::send` also refuses to notify while the link isn't encrypted — closes the window where an unbonded peer could previously connect, subscribe, and either inject CAT commands (keying the attached radio without authorization) or passively snoop USB / jack / radio-info broadcasts. A `BLE_GAP_EVENT_REPEAT_PAIRING` handler deletes the stale bond and retries so re-pairing after an app reinstall works.

### Added
- **iOS:** `HUNT <callsign> [freq] [mode]` logger command for one-off QSOs at a different frequency/mode without changing the active session — e.g. `HUNT W6JY 14067 CW` or `HUNT N9HO 14060` (mode falls back to the session's current mode). At least one of `freq` or `mode` must be supplied; missing fields fall back to the active session, so `HUNT N9HO 14060` and `HUNT N9HO CW` both log a QSO using the session's other field. Arguments after `HUNT` are parsed by the same `QuickEntryParser` that powers the callsign input field, so RST, park, grid, state, notes, and Zulu time tokens flow through. Bare `HUNT` keeps its existing behavior (show activator spots panel).
- **CW Sweep:** Full CW Bridge support over BLE (CWBP). New "CW Bridge" entry in the radio model picker; the Radio Control tab exposes a dedicated section for scanning, pairing, connecting, and monitoring the bridge. Implementation ports the iOS BLE stack to macOS — `BLERadioTransport` actor around CoreBluetooth NUS, `BLEDelegate` for the CB central/peripheral callbacks, `BridgeProtocol` actor providing CWBP framing (handshake, CAT passthrough, set-verify, CW keyer commands) that conforms to `RadioTransport`, and `BridgeFrame` protobuf builders/parsers using the shared `CarrierWaveCore` generated types. New `BridgeDiscoveryService` handles BLE scan / pair / forget with persisted UUID. `RadioManager+Bridge` orchestrates the connect flow: BLE connect → CWBP handshake → bridge-side radio auto-detection → hot-swap RadioSession with the correct protocol handler (`CIV`/`Kenwood`/`Elecraft`) via `BridgeRigDetector`. Live status card shows firmware version, USB presence, detected radio, handshake state, and keyer availability, with a Re-detect button. New `NSBluetoothAlwaysUsageDescription` added to Info.plist.
- **Firmware:** QRP Labs QCX and QMX radio support. Auto-detected via `OM;` → `OMQC;` (QCX) or `VN;` → `*QMX` (QMX) after Kenwood ID probe. Shared QRP Labs handling: RU/RD offset without sign character, no XIT (uses emulation). QCX-specific: clear RIT via `RU00000;`+`RT0;`, power/mode skipped (CW-only). QMX-specific: standard RC; for clear RIT, multi-mode support, PC read-only, time-based keyer drain (no TB;). Added STM32 CDC-ACM VID/PID (`0x0483:0x5740`) for QMX USB connection.
- **Firmware:** TRS jack plug detection via switched jacks on GPIO8 (mic) and GPIO9 (phone). Internal pull-ups detect insertion/removal; state is shown on the OLED display and sent to the app via new `JackStatus` protobuf message (tag 26). Status is included in the handshake state dump and sent on every change.
- **Firmware:** FT8 encoding and decoding on the CW Bridge, driven by two new TRS jacks on the Heltec daughterboard (mic OUT via I2S0 → external DAC / PDM+RC on GPIO4/5/6, phone IN via ADC1_CH6 continuous DMA on GPIO7). The same CFT8 C library used by the iOS/macOS app is now compiled into the firmware (`build.rs` + `cc` crate + `src/ft8_shim.c`) so encodes stay bit-identical across platforms. New protobuf messages `Ft8EncodeReq/Rsp`, `Ft8Send`, `Ft8CaptureStart/Stop`, `Ft8Decode`, `Ft8Status` keep only text + small metadata on the BLE wire — 12 kHz audio never leaves the bridge. Added `CAP_FT8_CODEC` capability flag to the handshake response. PSRAM is now required for the decoder (waterfall buffers ~120 kB); enabled by default in `sdkconfig.defaults`. Encoder-only / TX-only use still fits in internal RAM.

### Changed
- **iOS POTA uploads — fully manual via ADIF export.** POTA upload buttons on the session list and activation rows now open the ADIF export sheet instead of uploading directly. Users save the ADIF file, then upload it themselves on pota.app. First-time instruction card walks through the steps (save file → open POTA logs page → landscape/zoom → choose file). Dismissible with "Got It" (permanent) or "Show Next Time"; re-accessible via the `?` toolbar button. POTA upload page URL corrected to `/user/logs`.

## [1.83.0] - 2026-04-22

### Added
- **Firmware + iOS:** Xiegu G90 full CI-V support. Implemented CI-V RIT/XIT offset set (cmd 0x21 sub 0x44, BCD-encoded), clear RIT/XIT (zero offset + disable both), and power level read/set (cmd 0x14 sub 0x0A) for all CI-V radios (G90, IC-705, IC-7300). Added Kenwood/Elecraft power level read/set via `PC` command. New `FIELD_POWER_LEVEL` in the bridge protobuf protocol. `RadioSession` polls and tracks `powerLevel` state for both protocol families.
- **iOS + Firmware:** CW memory keyer over BLE bridge. Eight configurable message slots with template variables (`{MYCALL}`, `{CALL}`, `{NR}`, `{RST}`, `{NAME}`, `{EXCH}`) and prosign support. Keyer button row appears above the command row in the logger when the CW Bridge is connected in CW mode. Settings page at Radio > CW Messages with detail editor featuring tappable macro pills and live preview. Long-press any keyer button for inline editing. Bridge firmware handles CW text chunking, buffer polling, speed control, and per-radio CAT encoding (Kenwood KY/TB/KS, CI-V 0x17/1C/14 0C).
- **iOS + Firmware:** Migrated BLE bridge protocol from custom binary framing (0xCB magic byte) to protobuf serialization. Generated types in CarrierWaveCore, firmware uses prost. Protocol version bumped to 2.
- **iOS:** Horizon Survey (alpha, hidden). New LIDAR-based tool for walking the QTH and building a 360° obstruction profile against DX takeoff angles. `HorizonProfile` in `CarrierWaveCore` stores per-degree max obstruction elevation with O(1) bearing lookup, blocked-angle predicate, coverage fraction, and nearest-gap guidance for panning. `HorizonARCaptureView` wraps `ARView` with `.gravityAndHeading` world alignment so `-Z` is true north, throttles frame processing, and hands each `ARDepthData` to a strided `HorizonSampler` that unprojects depth pixels via the scaled inverse intrinsics, transforms to world space, computes azimuth (`atan2(Δx, −Δz)`) and elevation (`atan2(Δy, √(Δx²+Δz²))`), and keeps the maximum elevation per azimuth bin. The live view overlays a status chip (tracking / initializing / degraded with reason), coverage percent, a mini polar plot, and an instruction line ("Pan toward 120° to fill a gap"). The results sheet renders a full polar plot with an interactive takeoff-angle slider (0–45°), a dashed takeoff ring, a blocked-bearing count, and a worst-5 bearings list with compass points. Gated behind `ExperimentalFeature.horizonSurvey` (alpha, hidden by default); entry point appears in Settings → Experiments once enabled. Requires LIDAR (iPhone Pro).
- **iOS:** "Send Debug Info" action on the session detail `⋯` menu. Opens a sheet that gathers the session's full state into a shareable text bundle — session metadata (equipment, conditions, contest/rove fields, cloud-dirty flag), every QSO with per-service `ServicePresence` rows, session spots, activation metadata, sync debug log entries filtered to the session's time window, device/app/locale/time-zone info, and the generated ADIF — with Share / Save to Files / Copy to Clipboard actions. Meant for reproducing "something is wrong with this session" complaints without having to ask the user to scrape together separate artefacts.
- **iOS:** Contests browser in the Activity tab. New "Contests" row under Community opens a full catalog of server-published contest definitions, grouped into "Live now" + "All contests" with relative next-session times ("Next in 3h", "Live — ends in 45m"). Each entry drills into a detail page with the schedule (start/end/duration UTC), rules summary (modes, bands, dupe scope + key, minimum off-time), categories, overlay categories, and the sent/received exchange. Participation section shows friends who have logged a completed session tagged with this contest — pulled from the activity feed and de-duplicated by callsign, with their QSO count and category when available. Completed sessions now carry `contestId`, `contestCategory`, `contestOverlayCategory`, and `contestScore` on their activity details so friend participation is surfaced automatically.
- **iOS:** Contest picker fixes. Rows were previously inert when the full definition failed to land in the disk cache (only summaries arrived). Tapping now falls through to an on-demand `GET /v1/contests/:id` + cache write, shows a per-row spinner while loading, and surfaces a modal error if the fetch fails. Rows now also display the schedule — "Next Mon 00:00" / "Live — ends in 45m" — pulled from the cached full definition, and the list is empty-state-aware with a Retry button when the server is unreachable. `ContestDefinitionsStore` gained `allDefinitions()` and `upsertDefinition(_:)` so single-id cache writes don't require the full refresh flow.
- **iOS + macOS:** "What's New" sheet shown on first launch after an app update. Bundled per-version release notes live in `WhatsNewCatalog` (CarrierWaveData), tagged by `WhatsNewItemKind` (New / Improved / Fixed) and platform; `WhatsNewService` compares `CFBundleShortVersionString` against a per-platform `UserDefaults` last-seen version, suppresses notes on a fresh install, and presents `WhatsNewSheet` (sectioned cards, kind-tagged item rows). No network — copy ships with the binary.
- **iOS + macOS:** Integrated server-published contest definitions (format v0.3). The app now fetches contest definitions from `GET /v1/contests` with 24h refresh, caches them to Application Support, and drives scoring, dupe checking, exchange parsing, and Cabrillo export from a single shared model (`ContestDefinition`) that mirrors the server schema. New phase-based scoring engine evaluates `per_qso`, `multiplier_count`, and `aggregate` phases against a condition DSL (`their_country`, `my_cq_zone`, `received.<name>`, etc.) and produces per-phase results for UI breakdown. Session start surfaces the definition's categories and overlay categories as native pickers, shows an in-progress/next-session countdown from the schedule (recurring_weekly / annual / fixed_dates), and seeds power-class choices from the selected category. The live logger gains off-time remaining badges and band-change violation counts derived from `operating_constraints`. `ContestEngine` honors `dupe_rules.scope` + `dupe_rules.key` composite keys (e.g. callsign+band+mode_group) and `include_zero_point_qsos` per multiplier phase. Cabrillo output uses the definition's `cabrillo.contest_name` + `version` and formats QSO lines from the sent/received exchange order. Bundled YAML/JSON contest templates and `ContestTemplateLoader` are retired.
- **Server:** Contest visualizer served at `/contests` (was only accessible via `/static/contest-visualizer/`). Visualizer now fetches contest definitions from the API (`GET /v1/contests`) instead of using hardcoded data, with a generic scoring engine that interprets any v0.3 contest definition.
- **Server:** Seed script (`server/scripts/seed-contests.sh`) to load example contest definitions into the database via the admin API.
- **iOS:** QSO editor now exposes the operator's own callsign (`OPERATOR` / `STATION_CALLSIGN` in ADIF terms) — previously `myCallsign` was set at logging time and read-only afterwards. The Edit sheet is reorganised into iOS 17 collapsible sections (My Station, Signal, Their Location, Activity References, Contest, Notes), with Contact kept expanded by default so the sheet stays scannable instead of dumping every field on-screen. New fields surfaced for editing: My Callsign, Station Callsign (club/alternate call), Rig, Station Profile, DXCC entity, license class, WWFF reference, AoA code, and full contest exchange (contest name, serial sent/received, exchange sent/received). Rig, My Park, Their Park, SOTA, WWFF, Contest, DXCC, Band, Mode, and State/Province rows embed the rich pickers used elsewhere in the app (`InventoryPickerSheet`, `ParkPickerSheet`, `SummitPickerSheet`, `WWFFReferencePickerSheet`, `ContestPickerView`, plus new `DXCCPickerSheet`, `ModePickerSheet`, `BandPickerSheet`, `StatePickerSheet`) so editing an existing QSO gets the same nearby-suggestions / searchable-catalog / live-name-resolution experience as the logger. DXCC is backed by `DescriptionLookup.numberLookup`; Mode, Band, and State are backed by a new `ADIFCatalog` module in `CarrierWaveCore` that holds the canonical ADIF 3.1.5 enumerations (55 modes grouped by Phone/CW/Digital/Image, 30 bands from 2190 m down to 1 mm with frequency ranges, and Primary_Administrative_Subdivision codes for USA + Canada with full names). Every picker has a **Custom** entry row for values outside the bundled catalog — e.g. freshly-added DXCC entities, experimental bands, proprietary modes, or subdivisions outside USA/Canada (Mexican states, Australian states, Japanese prefectures) — so nothing is blocked by the curated list being incomplete. The QSO Detail view gains matching **My Station**, **Activity References**, and **Contest** sections that appear only when populated, plus an **Other ADIF Fields** disclosure under Source that parses `rawADIF` and surfaces any ADIF spec fields not already mapped to a dedicated row — so imported logs from other tools don't silently drop unfamiliar tags.
- **iOS:** New **RBN Lookup** dashboard card (Tools section) for checking Reverse Beacon Network spots for any callsign without needing to start a logging session. Includes a one-tap shortcut to look up the operator's own callsign using `loggerDefaultCallsign`, with inline results powered by the existing `RBNPanelView` (spots list + mini-map). Hide it from Dashboard → Customize if you don't want it.
- **iOS + CW Sweep:** SKCC (Straight Key Century Club) spot enrichment. The SKCC roster from `skccgroup.com` is downloaded once per day and cached to disk via a new `SKCCMembershipStore` actor in `CarrierWaveCore` (shared by both apps). Spots whose callsign matches a member are tagged with the member's number and award level (Centurion / Tribune / Tribune ×N / Senator). On iOS, a small orange `SKCC 12345Tx5` pill appears next to the FRIEND badge in the hunter spot row. On CW Sweep, the same badge appears in the spot inspector header alongside a longer name / SPC line in the operator section. Modeled after K7MJG's `skcc_skimmer`.
- **Contest calendar enrichment (Phase 1).** Contests in the On Air sheet now parse the WA7BNM description for mode, bands, exchange, duration, and category, match known-major events against the bundled contest templates, and render a row with live countdown, colored chips (mode, bands, duration, popularity tier, "Log Now" when a template matches), and a progress bar for active contests. Tapping a row opens a `ContestDetailSheet` with exchange preview, actions (Log Now, Remind me 30 min before — schedules a local notification, Add to Calendar — writes an `EKEvent`, Open Rules). New "See full calendar" link from the section header opens `ContestCalendarView` — a month-grid + agenda browser with per-day contest markers and drill-through to the same detail sheet. See `docs/plans/2026-04-15-contest-enrichment.md` for the phased plan covering follow-up work (POTA/SOTA/WWFF agenda blending, server-side aggregation of eham/hamweekly/NG3K/ARRL special events, VOACAP "conditions at start", widget surface).
- **Server:** HF propagation prediction API powered by `dvoacap-python`. New `POST /v1/propagation/p2p` (point-to-point) and `POST /v1/propagation/wheel` (CAP-style polar wheel) endpoints proxy to a Python sidecar that wraps the MIT-licensed DVOACAP port. Responses are cached in Postgres (`propagation_cache`, 24h TTL) keyed by SHA-256 of the normalised request body. Sidecar runs as its own systemd unit (`cw-propagation.service`) alongside `activities-server` in production; docker-compose wires it up for local dev. Opt-in via `activities_server_propagation_enabled: true` in Ansible and `PROPAGATION_ENABLED=true` on the Rust server. Full architecture, endpoint reference, and deployment in [`server/docs/features/propagation.md`](server/docs/features/propagation.md).
- Group QSOs into a session from the Logs tab: select one or more already-logged QSOs and create a new **completed** `LoggingSession` that groups them (this does not start an active logging session). Opens a `GroupIntoSessionSheet` pre-filled from the selection — activation type defaults to POTA when the selected QSOs all share a park reference, operator callsign defaults to the most common `myCallsign`, start/end cover the QSO date range, and the primary mode / representative frequency are derived from the group. QSOs already assigned to a session are skipped (shown as a count in the sheet) so existing session groupings aren't overwritten. The Select button in the Logs toolbar now works regardless of whether a search query is active.
- QSON (QSO Object Notation) export: full log export from Settings > Data & Tools in Ham2K-compatible JSON format
- QSON safety ledger: append-only monthly `.qsonl` files alongside existing ADIF ledger in `Documents/QSOLedger/`
- iMessage / Mail / Notes enriched share links for callsigns, QSOs, parks, and SOTA summits: Share button on the Dashboard callsign lookup card, QSO detail, park detail (sheet, map callout, and picker row), and SOTA summit (map callout and picker row) produces a universal link with a rich `LPLinkMetadata` card preview (cross-platform card renderer in `CarrierWaveCore/Sharing`). Recipients with Carrier Wave installed deeplink straight into the relevant detail view via `https://carrierwave.app/link/<kind>/<id>`. Log data lives entirely in the URL fragment and never reaches a server. CW Sweep gets the same share UI via NSSharingServicePicker.
- CoreSpotlight indexing for QSOs and logging sessions: callsigns, bands, modes, park references, grids, and countries become searchable from the iOS home screen and Siri search. Background reindex runs after CloudSync starts using the standard batched-fetch pattern (fresh `ModelContext` per 1k batch, skips hidden QSOs and `WEATHER`/`SOLAR`/`NOTE` metadata pseudo-modes). Tap-back on search results posts `didOpenSpotlightQSO` / `didOpenSpotlightSession` notifications carrying the entity UUID (view-layer navigation wiring is a follow-up). Schema version constant bumps trigger a full rebuild on upgrade; subsequent launches do incremental passes keyed on `importedAt`.
- **Developer**: Settings → Developer → Spotlight Debug. In-app view that shows the current Spotlight reindex state (phase, running flag, `CSSearchableIndex.isIndexingAvailable()` result, current vs. stored schema version, last-run path/entry/completion/elapsed, QSO and session indexed counts, last error) and exposes a "Force Full Rebuild" button that resets the stored schema version and re-runs the full pass. Requires Debug Mode enabled.

### Changed
- **macOS:** Band scope redesigned with structured rows, diagonal leader lines from linear frequency axis, and row displacement for crowded spots. Vim-style keyboard navigation (j/k spots, J/K mults, h/l pan, ? help). Right-click context menu (tune, copy callsign, QRZ lookup, watch marker, show in list). Fit-to-spots zoom (0 key or FIT button). Keyboard shortcut help overlay (? key).
- **iOS:** Centralized all periodic network polling (spots, comments, solar, auto-sync, frequency activity) behind a single coordinated 60-second timer to reduce battery drain from independent CPU/radio wakes (CAR-239)
- **iOS onboarding — reduced to callsign-only, optional setup moved to dashboard.** The original onboarding flow had five mandatory screens (callsign → profile lookup → LoTW/POTA/QRZ credential forms → community opt-in → confirmation), which presented optional integrations as required steps and made first-run feel like a chore list. Mandatory onboarding is now a single step: enter a callsign, review the looked-up profile inline, tap Get Started. Service credential entry and community registration moved to a new persistent "Getting Started" card on the Dashboard (`DashboardGettingStartedCard`), where each row is framed by the value it unlocks ("Auto-upload confirmations to ARRL", "See DXCC progress and callsign lookups") rather than as a task to check off. The card shows a progress bar, taps deep-link to the relevant Settings destination or the Activity tab, items tick off automatically as services get connected, and the whole card can be dismissed or self-hides once all four items are complete. `TourState` gains `hasDismissedGettingStarted` persistence; `DashboardCardID` gains a `.gettingStarted` case (not in a customize-sheet section so it stays outside the normal card-toggle UX). The region-confirmation step added in the international work is kept off-screen — `UserRegionProfile.primaryIARURegion` is persisted silently on first callsign entry when no override exists, and can still be changed from Settings.
- **iOS dashboard — merged "Callsign Lookup" and "RBN Lookup" cards.** The two cards duplicated a search field, stacked three different "clear" affordances (header Clear button, field ⓧ, panel ⓧ), repeated the callsign in the panel header after the user had already typed it, and left "Check my callsign" visible even after results appeared. Enriched profile info also didn't carry across — the RBN card only knew the callsign string, not the QRZ/HamDB record. The cards are now a single **Callsign Lookup** card in the Tools section: one search field, one Clear button, the `LoggerCallsignCard` (name/emoji/flag/grid/QTH/last-contact enrichment) on top, and the `RBNPanelView` spots list below with the now-redundant callsign removed from its header. The "Check my callsign" shortcut only renders before a submission, and the `RBNPanelView` panel init gains a `showsCallsignInHeader` flag so embedded uses can hide the duplicate label.
- **iOS QSO detail — visual-hierarchy redesign.** The old label/value table was tedious to scan, with key facts like band/mode/freq/RST buried in a flat Contact section and no coherent flow. The new layout leads with a hero card (big monospaced callsign, name, location, license/contest badges), then a Contact panel that surfaces band/mode/frequency as colored pills and RST as a "sent ↔ received" exchange with large digits, then a single stats strip for distance (km + mi), bearing with compass point, and watts-per-km / watts-per-mi efficiency. Station context is rendered as two side-by-side "THEY" vs "ME" cards that list each side's grid, location, DXCC, POTA, rig, power, antenna, key, and mic (antenna/key/mic come from the matching local `StationProfile`). Activity references (POTA/SOTA/WWFF/AoA) and club affiliations become colored chips that flow to multiple lines. Notes render as an italic quote card with an accent bar rather than a plain row. Import/source metadata is collapsed into a single disclosure at the bottom instead of occupying its own prominent section.
- **iOS Edit QSO — guaranteed-tappable section headers.** `Section(_:isExpanded:)` in `Form` was rendering section groups (My Station / Signal / Their Location / Activity References / Contest / Notes) as inert labels with no disclosure chevron — users had no way to tell they were supposed to expand, and on some builds they didn't expand at all. Replaced with a `collapsibleSection` helper that uses an explicit `Button` header with a rotating chevron and gates the body on the `isExpanded` binding.
- **iOS Group into Session — explain and override blocked QSOs.** The sheet previously reported "Already in a session: N" without saying which session, so a user who believed their QSOs were ungrouped had no way to diagnose why grouping was blocked. Now the sheet renders a "Blocked by existing sessions" section listing each referenced `LoggingSession` by title (custom title, park ref, SOTA/WWFF ref, or activation-type + date) with the count of selected QSOs in it, and an "Unlink these QSOs and regroup" toggle that forces the blocked QSOs into the new session. QSOs whose `loggingSessionId` points to a deleted session (orphans) are detected separately and included as eligible automatically, with an inline explanation line. `buildGroupingSummary` and `createSessionFromSelection` both go through a real `LoggingSession` fetch rather than just the presence of `loggingSessionId`.
- **iOS:** Safety Ledger improvements in Settings → Backups. Each ledger row now shows an inline colored **ADIF** / **QSON** pill so the two parallel formats (`.adi` and `.qsonl`) are distinguishable at a glance instead of both reading as "2026-04". Ledger files are also now mirrored to iCloud Drive next to the SQLite backups (`Documents/QSOLedger/` inside the ubiquity container), so the append-only recovery log survives device loss the same way the database snapshots do. Sync piggybacks on the existing `BackupService.syncToICloud()` pass, re-copies files whose size changed since the last mirror, and prunes iCloud ledger files that no longer exist locally.
- Hunter Log → Daily Activity: added a day-at-a-glance map of all QSOs with resolvable grid squares (reuses `SessionQSOMap`, disabled hit testing inside the scroll view); merged the floating date header into the stats card so it no longer renders through the translucent navigation bar; replaced the compact single-line QSO rows with the full-fidelity `QSORow` used by the main log so per-QSO enrichment (callsign nicknames and emoji, callsign notes, contact-count badge, park names, frequency, service sync badges) now appears alongside the existing band/mode pill and RST.
- Brag sheet share card map: antimeridian-aware viewport tightly frames wide-span contact sets (an operator with contacts in both Europe and New Zealand now gets a Pacific-centered view instead of a near-full-world frame); day/night terminator ("gray line") overlaid on the standard Apple tile background; trace lines rendered in saturated magenta at higher contrast; pin markers replaced with dot + halo style on the standard map for a cleaner look against dense clusters. Custom flat themes (midnight, warm, ember, etc.) keep their designed pin aesthetic.

### Fixed
- **iOS POTA upload ADIF validation.** POTA uploads could fail with "PHONE is not a valid mode" or "UNKNOWN is not a recognized ADIF band value" because we validated bands before upload but never validated modes. Added a comprehensive ADIF 3.1.7 field validator (`ADIFFieldValidator` in CarrierWaveCore) that checks mode, band, submode→parent consistency, band/freq range, date, time, and grid square before any upload. Generic modes (PHONE, DATA) are normalized to ADIF-compliant equivalents (SSB, RTTY). Invalid QSOs are rejected pre-upload with version-gated retry — they automatically retry when a new app build ships with fixes. Also fixed a telemetry blind spot where POTA `success=false` responses were treated as success, clearing diagnostics instead of recording them. Updated all POTA error guidance to direct users to Carrier Wave Discord first.
- **iOS QRZ upload count mismatch with POTA.** QSOs logged live in the app could be missing QRZ service presences if QRZ credentials were configured after the logging session started, because the logger cached credential state at session start and never refreshed it. This caused the "Upload N to QRZ" button to show fewer QSOs than "Upload N to POTA". Fixed by: (1) aligning the logger's credential checks with `ServiceConfiguration` (the same path used by ADIF import), so POTA OAuth tokens are recognized consistently; (2) backfilling missing QRZ presences when loading sessions for display; (3) adding an explanatory caption when upload counts differ between services.
- **iOS RBN spotter-grid enrichment for skimmer callsigns.** `SpotsService.enrichSpotsWithGrids` was passing the raw spotter callsign (`AK6RI-1-#`, `KM3T-2-#`, `W3OA-@`) straight to HamDB, which returned nothing — the hyphen suffix identifies the skimmer instance and software (CW Skimmer `-#`, Aggregator `-@`, numbered rigs `-1`/`-2`), not a licensed operator. Every spot kept `spotterGrid = nil`, so the mini-map toggle never appeared on the RBN panel even when a station had live spots. Added `baseSkimmerCallsign` that strips from the first `-` onward (ham callsigns never contain `-`; portable suffixes use `/`), normalises before lookup, and caches under the base callsign so multiple skimmers run by the same operator share one grid entry.
- **iOS:** iCloud sync creating ~3x duplicate QSOs for phone-mode contacts (USB, LSB, AM, FM, DV) — dedup key mismatch between local model and CKRecord fields used different mode normalization functions
- **iOS:** iCloud sync unnecessary re-uploads after conflict resolution — dirty flags are now only set when the merge produced data the server doesn't already have
- **iOS:** Crash on launch in ClubsSyncService when duplicate club serverIds exist in SwiftData — replaced `Dictionary(uniqueKeysWithValues:)` with `uniquingKeysWith`
- **iOS:** Crash on Activity feed refresh when duplicate ActivityItem IDs exist
- **iOS:** Potential crash in FriendsSyncService from duplicate callsigns or friendUserIds
- **iOS:** Defensive fix for all remaining `Dictionary(uniqueKeysWithValues:)` sites (SessionDetailView, QSO+POTAPresence, CallsignNotesSource)
- Session brag sheet card map rendering horizontal stripes across the viewport for sessions centered on North America (and any non-wrapping viewport). The antimeridian longitude-wrap logic added to `FlatMapRenderer.Viewport.project` / `BragSheetShareRenderer.MapViewport.project` was unconditionally flipping out-of-range longitudes by ±360°, which for a North America viewport turned Aleutians polygon points like lon=-175 into lon=185 — projecting them far off the right edge instead of just past the left edge. The resulting zigzagging polygon was then filled by Core Graphics with scanlines crossing the whole map, producing the stripe pattern. Fixed by picking the longitude representation closest to the viewport center, which is a no-op for normal viewports and correctly shifts points for antimeridian-spanning viewports.
- Spotlight: tap-back from Spotlight search results now deep-links into the matching QSO or session. The notification path was already firing from `CarrierWaveApp.handleSpotlightActivity`, but no view was subscribed to `didOpenSpotlightQSO` / `didOpenSpotlightSession`, so tapping a result just opened the app at the dashboard. `ContentView` now switches to the Logs / Sessions tab, fetches the entity from SwiftData by UUID, and pushes `QSODetailView` / `SessionDetailView` via `navigationDestination(item:)`.
- Spotlight: existing logs showing no results on first launch after upgrade. Bumped `SpotlightConstants.currentSchemaVersion` to 2 so every user gets a forced full rebuild on next launch — no reinstall required.
- Spotlight: locally edited QSOs were not picked up by incremental reindex passes. The predicate keyed only on `importedAt`, so edits (which update `modifiedAt`) left stale entries in CoreSpotlight until the next schema bump. Predicate now matches either `importedAt >= since` or `modifiedAt >= since`.
- Spotlight: items were built with `UTType.content`, which is an abstract base UTI and can be silently dropped by CoreSpotlight. Switched to the concrete `UTType.text`.
- Spotlight: reindex was scheduled at `.utility` priority, allowing iOS to defer it aggressively under background pressure. Bumped to `.userInitiated` and added diagnostic logging (unconditional entry, `isAvailable` result, schema version comparison, fetch errors surfaced instead of swallowed, elapsed-time summary) under the `app.carrierwave`/`SpotlightReindex` logger to make startup failures observable in Console.

## [1.82.1] - 2026-04-06

## [1.82.0] - 2026-04-06

### Added
- QSO safety ledger: append-only ADIF file (`Documents/qso-ledger.adi`) records every QSO outside SwiftData — survives database destruction and can be imported to recover logged contacts
- Location-based call sign prefix picker: suggests the correct portable prefix (e.g., F/ for France) based on GPS location, with searchable country list and custom prefix entry

### Fixed
- **Critical:** ModelContainer init failure silently deleting entire database with no backup or logging — now creates emergency backup to Library/EmergencyBackup before reset
- **Critical:** iCloud snapshot restore replacing local database without validating snapshot contents — now verifies QSO rows exist before replacing and creates pre-restore backup
- Prevent uploading empty database snapshots to iCloud that could poison bootstrap on other devices
- Auto-backup no longer overwrites good backups with an empty database after data loss
- Backup pruning no longer deletes backups containing data in favor of empty ones
- iCloud Drive backup sync prefers backups with data over empty ones

## [1.81.0] - 2026-04-02

### Fixed
- IC-705 WiFi sessions disconnecting after ~60 seconds (missing periodic reauth)
- Frequency/mode changes from logger not reaching radio over WiFi (stale session blocking reconnect)
- WiFi reconnect leaving connectionStatus stuck at .connecting permanently

### Added
- CW Sweep: Icom WiFi (RS-BA1) radio connection support for IC-705 and IC-7610

## [1.80.0] - 2026-04-02

### Changed
- Redesigned session detail view with three-tier layout: hero summary, QSO list, insights carousel
- Unified POTA activation and regular session hero card (consolidated stats, band/mode pills, key details)
- QSO list moved to position 2 (immediately after hero) for faster access to primary content
- Map, States Worked, and Park Cards consolidated into swipeable insights carousel with tap-to-expand
- Removed redundant POTA info section and legacy session summary section (replaced by unified hero)
- Full equipment display in hero card (radio, antenna, key, mic)
- Band and mode badges show QSO counts
- Shift windows only shown when QSOs exist during them, with count per shift
- Club connections collapsed by default with disclosure expand showing callsign badges
- SDR recording moved below Session Replay

### Added
- Grid square display in session summary shows all unique grids for rove sessions
- Instagram album-style park card carousel in session detail with GIS boundaries and grid square overlay (requires Park Boundaries experiment)
- RST sent/received displayed on QSO rows in compact format
- Percentile rankings (Top X%) for QSO count, duration, and rate vs all sessions
- Section headers for Insights and Club Connections

### Fixed
- iCloud sync duplicate QSOs appearing as triplicates in session detail (dedup by content key)

## [1.79.0] - 2026-04-02

### Added
- Per-service sync mode (Bidirectional / Upload Only / Download Only) for QRZ, POTA, and eQSL — replaces the global read-only debug toggle
- DONKI API `note` field decoded and displayed for solar flares and CMEs in space weather detail views
- Journal-based iCloud sync engine as alternative to per-record CKSyncEngine sync
- SQLite snapshot bootstrap for instant initial device setup (replaces syncing 200K+ individual records)
- CloudSyncSnapshotService for CKAsset-based database snapshots (upload every 6 hours)
- CloudSyncJournalEngine with batched JSON journal entries (100 ops per CKRecord)
- Snapshot bootstrap check on first sync — new devices download one file instead of thousands of records
- Journal sync mode toggle in iCloud sync settings (Settings > iCloud > Sync Engine)
- Journal sync mode setting syncs across devices via iCloud KVS — toggling on iOS switches CW Sweep too
- Journal sync telemetry: duration, file size, and journal tail count on all upload/download/bootstrap events
- Snapshot upload/download now tracks file size in bytes and elapsed time
- Activity summary shows file size badges and journal entry counts alongside duration and record counts

### Changed
- Renamed "Sync Sources" to "Sync Services" throughout the app
- Removed download-only button from the dashboard sync card (replaced by per-service sync mode)
- Enriched spots widgets with activity type icons (POTA/SOTA/RBN), band, mode, park/summit references, and signal info
- Added SOTA spot source to spots widget (fetches from SOTAwatch API)
- Redesigned widget rows: small shows activity icon + band + mode, medium adds park/summit ref, large uses two-line layout with detail text
- Consolidated duplicated filter badge code across widget sizes

### Fixed
- Space weather events now expire based on type (flares: endTime + 1h or 3h, geostorms: 24h after last Kp, CMEs: 48h) instead of showing for a fixed 3-day window
- Icom WiFi transport: reduce CI-V poll rate from 200ms/5-cmd to 1s/1-cmd to prevent radio firmware overload
- Icom WiFi transport: fix unbounded txBuffer growth (memory leak) with 64-entry cap
- Icom WiFi transport: fix CIV pkt7 reply using SID=0 during handshake (use control SID as fallback)

## CW Sweep [0.7.0] - 2026-04-02

### Added
- Full journal sync engine support (matches iOS routing, snapshot uploads, delegate callbacks)

## CW Sweep [0.6.0] - 2026-04-01

### Added
- Visual WYSIWYG layout editor with draggable dividers and drag-and-drop pane arrangement
- Spot Detail pane with map, callsign parsing, and condensed UI
- Compressible log and spot panes with progressive column hiding
- FlexRadio SmartSDR CAT control with SmartLink remote access
- Band scope waterfall overlay and spot overlay on waterfall
- Adaptive waterfall playback with jitter-smoothing buffer

### Changed
- Renamed app: CW Sweep → Carrier Wave: Sweep
- Migrated to shared radio types from CarrierWaveData
- Prepared for Swift 6 strict concurrency

### Fixed
- Activation map QSOs not rendering, added geodesic arcs
- Icom WiFi transport reliability (shared CarrierWaveData fixes from 1.78.2/1.78.3)

## [1.78.3] - 2026-04-01

### Fixed
- Icom WiFi keepalive: reset liveness timer at connection start and after iOS app suspension to prevent false disconnect on resume
- Detect transport disconnect (keepalive timeout) and propagate to UI via RadioSession state polling
- Diag tool: filter pkt7 pings during CIV pkt4 wait — was consuming pkt7 as pkt4, setting wrong civRemoteSID, breaking all CI-V commands

## [1.78.2] - 2026-04-01

### Fixed
- Icom WiFi transport: derive session ID from local IP + port matching kappanhang convention (was random), replace 20ms polling receive with continuation-based instant wakeup, add retransmit packet size guard — aligns app protocol implementation with the working diagnostic tool

## [1.78.1] - 2026-04-01

### Fixed
- Force re-download from QRZ/LoTW/POTA/LoFi creates duplicate QSOs for users with >1,000 QSOs — `reprocessQSOs` only fetched the first 1,000 existing records for dedup matching, missing all others (CAR-179)
- Added deterministic sort order to batched QSO key fetches to prevent offset-based pagination skipping rows across fresh ModelContexts
- BLE protocol picker unable to switch back to Kenwood — `rigProtocol` was a computed property bypassing `@Observable` tracking

## [1.78.0] - 2026-04-01

### Added
- QRZ multi-callsign API key mapping: associate separate API keys with each callsign for users who changed callsigns or operate under multiple calls. QSOs are routed to the correct QRZ logbook during sync based on their myCallsign field. Previous callsigns without API keys are shown as unlinked in QRZ settings.
- FlexRadio SmartSDR CAT control: connect to Flex radios (FLEX-6400/6600/6700) via LAN TCP/IP or SmartLink remote access for frequency, mode, and PTT control with push-based status updates
- Log Scanning (alpha): scan handwritten paper logs with the camera and import QSOs using on-device Vision OCR and the existing quick entry parser
- SDR Replay: instant replay button in WebSDR panel to re-hear the last 15 seconds of captured audio during a live session; also available via REPLAY, AGN, or HUH logger commands
- Activation Recommendations (alpha): pre-session screen suggesting gear, park, and band based on propagation, equipment history, award progress, and proximity
- Equipment catalog model with structured specs (bands, modes, portability, power) replacing string-based equipment lists
- Fuzzy equipment name matching ("did you mean") via CatalogMatcher with Levenshtein distance and alias support
- Recommendation scoring engine with 7 weighted dimensions: propagation fit, proximity, award progress, gear freshness, park novelty, combo novelty, community interest
- Serendipity slider balancing practical vs adventurous recommendations
- Milestone gravity: strong scoring pull when near award targets (e.g., Kilo at 998/1000)
- Equipment pinning: lock specific gear, band, or mode and get recommendations for the rest
- Activation Suggestion widget (small/medium) showing today's recommended activation
- Equipment inventory migration from legacy string lists to structured SwiftData model
- Activities server equipment catalog API spec (docs/features/equipment-catalog-api.md)
- Local equipment catalog cache with ETag-based refresh (24h interval), shown in External Data settings
- iCloud KVS equipment inventory sync with structured EquipmentRef format (backward-compat write-through for CWSweep)
- Unified InventoryPickerSheet replacing RadioPickerSheet and EquipmentPickerSheet across all session surfaces
- Interactive equipment migration sheet with catalog fuzzy matching, confidence indicators, manual search, and "Keep as Custom" override
- Custom equipment enrichment: editable specs, "Is this a...?" catalog suggestion banner, "Similar in Catalog" linking
- Custom equipment auto-submission to activities server for catalog review (anonymous, fire-and-forget)
- Server endpoint for equipment submissions with admin review workflow (POST /v1/equipment/submissions)
- Anonymous equipment usage telemetry at session end — records catalog IDs, mode/band/program context, paired equipment, and full specs for custom items (POST /v1/telemetry/equipment-usage)

### Changed
- Keychain primary save now uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for stricter credential protection (CAR-142)
- Keychain migration debug prints are now `#if DEBUG` only to prevent credential key names leaking in release logs (CAR-146)
- All DateFormatter/RelativeDateTimeFormatter allocations cached as `static let` across 9 view files, eliminating ~15 per-render allocations (CAR-147)

### Fixed
- POTA and ADIF imports now use operator callsign instead of station callsign for myCallsign, preventing other operators' callsigns from being erroneously detected as previous callsigns
- Duplicate friend activities within the same detection batch are now deduplicated
- RBN spots now appear on the session replay map — spotter grid squares are looked up from HamDB during spot monitoring and persisted to SessionSpot
- POTA download now populates theirParkReference from SIG_INFO, fixing missing P2P data for all POTA-sourced QSOs including those under previous callsigns (CAR-225)
- POTA audit now queries user stats for all callsigns found in activations, fixing false discrepancies for users with vanity call upgrades (CAR-225)
- QRZ upload no longer uses OPTION=REPLACE for QSOs not originally downloaded from QRZ, preventing frequency/grid data loss when POTA-sourced QSOs overwrite richer QRZ records (CAR-226)
- POTA-imported QSOs now normalize band to lowercase and mode to canonical form (PHONE→SSB), improving deduplication with QRZ records (CAR-226)
- Crash on launch in ClubsSyncService when duplicate club serverIds exist in SwiftData — replaced `Dictionary(uniqueKeysWithValues:)` with `uniquingKeysWith` (#2569, #2147)
- Crash on Activity feed refresh when duplicate ActivityItem IDs exist (#2250)
- Potential crash in FriendsSyncService from duplicate callsigns or friendUserIds
- Defensive fix for all remaining `Dictionary(uniqueKeysWithValues:)` sites (SessionDetailView, QSO+POTAPresence, CallsignNotesSource)

## [1.77.0] - 2026-03-29

### Added
- Persistent hunt filters in Settings: activity (POTA/SOTA), band, mode, club (per-club selection), and friend toggles
- Persistent P2P filters in Settings: band and mode multi-select
- Clear filter indicators on HUNT and P2P commands: filled icon when filters active, descriptive summary text
- Hunt Filter and P2P Filter pages in Settings > Appearance
- Import ADIF into existing session: long-press a session to import an ADIF file directly into it, with metadata validation warnings for callsign/park mismatches (CAR-216)

### Changed
- Enabled strict concurrency checking (warnings) on CarrierWaveCore and CarrierWaveData SPM packages (CAR-162)
- Added `@MainActor` to `EventLocationManager` for Swift 6 readiness
- Replaced `@unchecked Sendable` with proper `Sendable` on ~29 pure-value Codable types
- Added `[weak self]` to `Task { @MainActor in }` patterns in nonisolated delegate methods

### Fixed
- IC-705 WiFi connection timeout: radio sends 16-byte login confirmation in AP mode but code required 64+ bytes, causing all post-login packets to be skipped
- Club Log sync disabled: app was attempting to download from and upload to Club Log despite it being a "Coming Soon" feature — removed from sync flow until fully configurable

## [1.76.0] - 2026-03-28

### Added
- Experimental features system: central `ExperimentalFeature` enum, `ExperimentalBadge` component, and Experiments hub in Settings
- Consistent experimental badges on: iCloud sync, radio control, video export, FT8, Tune In, eQSL, awards, needs, park boundaries
- Events and CW Transcription tabs now hidden by default, opt-in from Settings > Experiments
- RST parse order setting: option to parse sent RST first instead of received (applies to logger and hunter log)
- Icom WiFi CAT control — connect to IC-705 and other WiFi-capable Icom radios via Access Point or Station mode
- Shared RadioSession, protocol handlers, and FrameAssembler between iOS and macOS via CarrierWaveData
- SMS spotting: spot POTA/SOTA activations via text message when off-grid with no data connection
- Save session configuration as a named template for quick reuse (alongside existing "Save as Defaults")
- Session QSO comment: a comment set on the session that is prepended to every QSO's notes when logged
- Edit session callsign from session detail menu (updates all QSOs in the session)

### Fixed
- P2P spot enrichment no longer overwrites QSO mode and frequency with the spotted station's values — only applies when explicitly tuning to a spot (CAR-213)
- Battery drain: added timer tolerance to all 10 timers, enabling iOS timer coalescing (est. 18-40% improvement)
- Battery drain: removed redundant 30s iCloud polling — push notifications already handle sync
- Battery drain: reduced spot monitoring frequency from 45s to 90s and frequency activity from 30s to 60s

### Removed
- Server challenges: removed challenge definitions, participation, progress tracking, leaderboards, and challenge sources from the app
- Challenge-related UI: browse challenges, challenge detail views, progress cards, leaderboard view, and challenge invite handling
- Challenge sections from Activity tab, onboarding, and settings

### Changed
- Callsign changes now sync to the activities server, updating the callsign across all community data (friends, activity history)
- "BLE Radio" settings renamed to "Radio" with transport picker (BLE / WiFi)
- Radio protocol handlers (CI-V, Kenwood) moved to shared CarrierWaveData package
- Spot comments on QSOs now show `[spot]` instead of `[Spot: CALLSIGN]`

## [CW Sweep 0.5.1] - 2026-03-26

### Fixed
- Scope data parsing now uses only actual spectrum bins instead of full buffer
- Waterfall rendering smoothed with proper bin detection and radio query span

## [CW Sweep 0.5.0] - 2026-03-26

### Added
- Spot markers on activation map for DX/POTA/cluster spots with known grids, with Spots toggle
- `:spot` and `:respot` vim commands wired to POTA API for self-spotting
- HamDB fallback for QSO name/QTH/state enrichment when QRZ is unavailable
- Spot geolocation enrichment from QRZ/HamDB operator grid lookups
- Click past session rows to open session summary detail sheet

### Fixed
- Auxiliary windows (Band Map, Add QSO, Spot Cluster) now float above main window
- Session frequency/mode now propagates to QSOs when no physical radio is connected
- Activation map no longer redraws on every keystroke in the quick entry box

## [1.74.3] - 2026-03-25

### Added
- `SPOT <message> REPEAT <minutes>` command to set custom auto-spot message and interval
- `SPOT STOP` command to cancel repeating spot timer

## [1.74.2] - 2026-03-25

### Fixed
- Crash in QRZ log ID dedup repair caused by SwiftData key path cache assertion failure on background threads (TestFlight #2046)

### Changed
- Merged Friends on Air into On Air Now card with always-visible friend count
- On Air Now card and sheet show friends section even when no friends are on air
- On Air Now moved above Friend Activity in dashboard layout

## [CW Sweep 0.4.0] - 2026-03-25

### Fixed
- 62-second main-thread hang from SwiftData full-table scans in DashboardView and DXCCNeededChecker — moved to background threads
- Frequency suggestions now round to nearest 100 Hz (no more sub-kHz precision like 14.05575)
- Vim mode no longer intercepts keystrokes in activation setup wizard
- Park search dropdown no longer hidden behind session setup content
- Hunter layout no longer shows duplicate spot windows

### Changed
- Unified activator view replaces separate setup wizard and sessions list
- Propagation panel shows real-time band conditions, solar indices, and space weather
- Frequency suggestion engine recommends clear General+ frequencies based on 30-min spot activity
- Park change dropdown for mid-session rove park switching
- Session history available via toolbar popover during operation
- QSO log table shows park reference column for rove sessions

### Removed
- Sessions sidebar item (merged into activator view)
- Full-screen POTA setup wizard (replaced by inline setup row)

### Added
- Prominent connected cluster node display with description
- Quick command buttons (Recent DX, Solar, Geomag, Skimmer Mode, Show Filters) when connected
- Newest spot age indicator in status bar
- Smart view now shows enriched spots from all sources (RBN, cluster, DX web) via SpotAggregator
- Source column with colored badges showing spot origin
- Distance and bearing column in smart spot table
- Clickable spots open detail inspector with frequency, mode, distance, bearing, DXCC status, spot count
- DXCC needed indicators (star for new entity, outline star for new band slot)
- Strikethrough for spots already worked today (same callsign + band + mode family)
- Worked-before checking in All Spots view

## [1.74.1] - 2026-03-24

### Fixed
- Crash in mergeDuplicateQRZLogIds due to computed keypath in relationshipKeyPathsForPrefetching

## [CW Sweep 0.3.0] - 2026-03-24

### Added
- QSO log search with full query language (call:, band:, mode:, park:, after:, bare text, wildcards, AND/OR/NOT)
- Auto-show inspector on QSO selection, removed manual toolbar button
- Press '/' to focus search box

### Fixed
- QSO log scroll performance — cap at 500 rows instead of unbounded fetch
- Empty/duplicate sessions showing in session list (CAR-194)
- QSO count not decreasing after delete in dashboard and session list (CAR-192)
- Dashboard stats double-counting CloudKit duplicate QSOs
- Spots table content clipping with narrow columns (CAR-190)

## [1.74.0] - 2026-03-24

### Added
- CW Sweep: POTA session setup wizard with inline band map, park search, and rove planner
- CW Sweep: Regulated band map showing operator class privilege boundaries with click-to-tune
- CW Sweep: Map-based rove stop planner with distance calculation and drag-to-reorder
- CW Sweep: POTA spotting commands (SPOT text command, Edit Comment ⌘⇧C, Return to My Frequency ⌘⇧R)
- CW Sweep: P2P spot highlighting with double-click-to-tune
- CW Sweep: POTA settings tab (license class, auto-spot, re-spot timer, comment template)
- CarrierWaveCore: US operator class band privilege data in BandPlan
- Pending iCloud view (Settings → iCloud → Pending upload) showing dirty records by type

### Changed
- CW Sweep: Moved BandPlan data from iOS app to CarrierWaveCore shared package
- CW Sweep: Changed Connect Radio shortcut from ⌘⇧R to ⌘⌥R (freed for Return to My Frequency)

### Fixed
- Fix inflated QRZ sync and QSL confirmed counts caused by duplicate QSOs (CAR-179)
- Align FetchedQSO dedup key to trim callsign whitespace (matches existing QSO dedup key)
- One-time migration merges duplicate QSOs sharing the same QRZ log ID
- Periodic full QRZ download (every 20 syncs) for reconciliation of stale presence flags
- Fix iCloud sync stuck records: clear dirty flags on metadata pseudo-mode QSOs and orphaned ActivationMetadata with empty park references
- Guard new CloudKit fields (wwffRef, stationCallsign) to prevent schema errors on production
- Re-schedule orphaned dirty records after fetch/send cycles instead of only on account sign-in
- Hide phantom Club Log pending uploads when service is not configured

## [1.73.0] - 2026-03-23

### Fixed
- Exclude duplicate QSOs from POTA activation counts (deduplicate by callsign+band+mode+park)
- Persist frequency from quick entry box when logging QSOs
- Prevent equipment list loss from iCloud KVS sync (union-merge instead of replacement)
- Recover equipment lists from session history when lists are empty after sync

### Added
- Auto-populate frequency and mode from POTA spot list when callsign matches a spotted station
- Show spot-sourced frequency/mode in quick entry preview with antenna icon indicator
- Mode recognition in quick entry parser (CW, SSB, FT8, etc.)
- Include mode in quick entry recall text for session and hunter logs
- P2P badge on QSO rows in session detail and activation detail views

### Fixed
- Export FT4 as MFSK+FT4 submode per ADIF 3.1.7 spec
- Swap eQSL inbox RST fields (were inverted from other station's perspective)
- Use standard QRZCOM_QSO_UPLOAD_STATUS field name in ADIF exports
- Standardize ADIF_VER to 3.1.7 across all export paths
- Split MODE/SUBMODE in ClubLog and eQSL uploads (USB→SSB+USB, FT4→MFSK+FT4)
- Lowercase BAND from ClubLog/eQSL downloads to match ADIF enumeration
- Use UTF-8 byte count for ADIF field LENGTH per spec
- Delegate LoTW field extraction to core ADIFParser (length-based)

### Added
- Park-to-park enrichment: during POTA activations, callsign lookup card shows P2P badge with their park(s) when the station is spotted as an activator
- Auto-populate their park reference from active POTA spots during P2P QSOs
- Set theirParkReference when selecting POTA spots or P2P opportunities from sidebar
- Include contest fields (CONTEST_ID, STX, SRX, STX_STRING, SRX_STRING) in ADIF exports
- Include NAME, QTH, STATE, COUNTRY, DXCC, TX_PWR in QRZ uploads

## [1.72.0] - 2026-03-23

### Added
- Stats accuracy reporting — long-press any dashboard stat card or drilldown item to report an inaccuracy; generates a structured diagnostic bundle with filter trace, matching/excluded QSOs, entity resolution detail, and environment context, exportable as JSON via share sheet
- "Explain this number" data — stat counts now carry metadata breakdown (counted, hidden excluded, metadata excluded, deduplicated) for future inline explanation popovers
- "What's This?" explanations upgraded from simple alerts to rich sheets showing what's included, what's excluded, edge cases, and calculation methodology for all dashboard stats and POTA award categories; sheets include a "Your Numbers" section showing the actual filter pipeline with counts at each stage (e.g., 4,521 total → 4,503 after metadata exclusion → 42 unique DXCC entities)
- Report Inaccuracy context menu on all Awards & Certificates rows (POTA awards and WAS 250)
- Kilo award shows progress bar toward 1,000 QSOs with best single-park total when not yet earned

### Changed
- Rename "POTA Awards" to "Awards & Certificates" across dashboard card, navigation title, and customize sheet

## [1.71.0] - 2026-03-22

### Fixed
- Move POTA Awards computation to background actor — prevents main thread stall and potential watchdog crash when navigating to awards screen with many park QSOs

### Added
- QSO recall (N3FJP-style) — long press a QSO in the session log or a spot in the hunter log to recall it into the quick entry form for re-logging (useful for 2-fers and 3-fers); session log context menu provides Recall, Edit, and Delete; hunter log context menu adds Recall alongside Tune In
- Hunter log callsign lookup — quick log section now shows callsign info cards (name, location, grid, QSO count) with the same lookup display as the session logger, including concurrent lookups for multi-callsign quick entry; lookup data enriches logged QSOs and fills form field placeholders
- Split ADIF export — export multiple ADIF files from a single session, automatically splitting by UTC day boundary, park reference (n-fers), and/or operator (multi-op) with toggles for each dimension
- Multi-callsign quick entry — type multiple callsigns in one line (e.g., "AC4NK N9HO W1AW 59") to create a separate QSO for each, sharing the same RST, park, grid, and other metadata (CAR-176)
- POTA shift information — shows Early Shift and Late Shift windows calculated from park longitude in the session header (logger and session detail), with inline boundary markers in QSO lists when shifts start/end
- UTC day boundary markers in QSO lists — visual separator rows appear when QSOs cross a UTC midnight boundary within a session

## [1.70.0] - 2026-03-21

### Added
- UTC day boundary detection for POTA activations — automatically splits the session at UTC midnight, shows a toast notification, and displays both days' QSO counts (Yesterday/Today) in the logger header and FT8 control bar
- Multi-operator session support (Ham2K PoLo style) — add additional operators to sessions, export per-operator ADIF files, filter multi-op imports to your callsign
- Import ADIF files from the Logs tab toolbar — pick any .adi/.adif file via the system file picker
- iCloud sync activity dashboard showing last fetch/upload timing, today's conflicts/errors
- Sync activity log with timeline of recent sync events (persisted across app restarts)
- Sync events instrumented for fetch, upload, conflict, error, and account changes
- Pending uploads visibility — see which QSOs are waiting to upload and why (missing fields, callsign mismatch, invalid park reference, etc.) with per-service filtering and CSV/Markdown/ADIF export

### Removed
- iCloud Drive folder monitoring for ADIF import (replaced by direct file picker)
- ICloudMonitor service and ICloudSettingsView

## [1.69.0] - 2026-03-21

### Added
- Nearby park and summit suggestions in session start — shows closest 5 POTA parks and SOTA summits inline so you can tap to select without opening the full picker (CAR-168)
- Small square spots widget showing up to 4 live spots with callsign, frequency, and freshness indicator

### Fixed
- Spots widget family routing — large widget was incorrectly rendering the medium layout

## [1.68.0] - 2026-03-20

### Added
- Club callsign support — operate under a club call as the station while recording your personal callsign as operator (CAR-169)
- ADIF exports now emit separate STATION_CALLSIGN and OPERATOR fields for club sessions
- Auto-uploads are disabled for club station sessions

### Changed
- Allow logging duplicate QSOs (same callsign + band + UTC day) instead of blocking — show warning banner but let user proceed
- Extend duplicate and new band detection to all session types, not just POTA
- POTA sessions still scope dupes by park; banner notes POTA will reject the dupe

## [1.67.0] - 2026-03-20

### Added
- Continuous GPS-based grid tracking during logging sessions (Logger and Activity Log)
- Auto-fill grid square from GPS when starting a session
- Inline fallback message when GPS is unavailable in session setup

### Changed
- Activity Log grid updates are now silent (no confirmation sheet)
- Both Logger and Activity Log share a single location service instance
- Skip accordion for single space weather events in On Air sheet

### Fixed
- Fix watchdog crash (0x8BADF00D) caused by concurrent full-table scans at startup — serialize CKSyncEngine start after stats pipeline, defer ClubsSyncService cache rebuild off main thread, add batched fetching with fetchLimit to ClubMember queries

### Removed
- LocationChangeSheet (grid change confirmation modal)

## [1.66.1] - 2026-03-20

### Added
- Add NASA DONKI space weather notifications — geomagnetic storms, solar flares, and CMEs with toast alerts, local notifications, and in-app banner when HF propagation is degraded
- Add space weather alerts section to Solar Panel showing active events with severity badges
- Add "Space weather alerts" toggle to Logger settings

### Fixed
- Fix watchdog crash (0x8BADF00D) on high-QSO-count devices caused by POTA Awards dashboard card fetching all park QSOs on the main thread — move computation to background actor with batched fetches

## [1.66.0] - 2026-03-20

### Added
- Export session replay as YouTube-ready 1080p MP4 video with map, WebSDR audio, and event toast cards
- `BoundedDescriptor<T>` and `BatchedFetch<T>` query abstraction layer in CarrierWaveData — makes it structurally impossible to fetch more than 1,000 QSO/ServicePresence objects at a time
- CW Sweep: add DX Summit, DXHeat, and DXWatch as aggregated spot sources with mode/grid/continent/LoTW/split enrichment

### Fixed
- Fix OOM crashes on high-QSO-count devices by serializing dashboard stats pipeline and batching all unbounded QSO/ServicePresence fetches — peak startup memory drops from ~185 MB to ~35 MB above baseline; import, sync, and clear operations capped at ~5 MB per batch regardless of QSO count
- Fix dashboard UI freezing during stats computation by isolating observation tracking — asyncStats property changes now only re-evaluate their specific card views, not the entire DashboardView with its 300+ cell ActivityGrid (CAR-127)
- Move stat detail and streak detail computation off main thread to background actors, eliminating 10k QSO main-thread fetches on navigation (CAR-127)
- Fix QRZ sync infinite loop where dead-state repair and non-primary callsign filter fought over 241 QSOs every sync cycle (CAR-170)
- Fix crash in PerfUploader when encoding telemetry data off the main thread (MainActor isolation violation on DeviceMetadata, PendingPayload, and PerfEvent Codable witnesses)
- Fix Activator WAS showing wrong state count for parks spanning multiple states (e.g., "US-WY,US-MT" parsed as garbage "WY,US" instead of separate states)
- Fix NeedsEngine not splitting 2-fer park references — each park in a 2-fer is now counted independently for activation QSO thresholds, states, and entities

### Improved
- Enable treat-warnings-as-errors (`SWIFT_TREAT_WARNINGS_AS_ERRORS` + `GCC_TREAT_WARNINGS_AS_ERRORS`) for all targets (CAR-165)
- Migrate geocoding from deprecated CLGeocoder to MKGeocodingRequest (iOS 26)
- Migrate deprecated AVAsset sync APIs (`tracks(withMediaType:)`, `naturalTimeScale`, `duration`) to async `load()` equivalents
- Remove dead video audio segment-writing code (writeSegmentBasedAudio, writeSourceSegment, readAndWriteSamples, SegmentWriteContext)
- Video export: water-droplet spot pings with splash center and expanding ripple (replaces dual-ring animation)
- Video export: segment-based audio time-alignment for highlight reel mode (pre-builds entire audio track with crossfades)
- Video export: two-row enriched HUD showing park name, equipment, QSO count, and rate per hour
- Video export: rich callsign cards with operator name, club emoji, special refs, and prior QSO count

## [CW Sweep 0.2.1] - 2026-03-18

### Fixed
- Fix states not showing in hunted states map and WAS250 mosaic — normalize LoFi "VA // Virginia" format to bare abbreviation
- Clear upload flags when soft-deleting QSOs in CW Sweep log tables — prevents phantom sync attempts

## [1.65.0] - 2026-03-17

### Added
- QSO log UX improvements: date section headers with relative labels (Today, Yesterday, day names), band-colored badges using spectral gradient, and horizontal quick filter chips for one-tap filtering
- Session Replay: time slider map view showing QSOs and RBN spots appearing chronologically with playback controls and speed adjustment
- Repair missing grid data when generating activation share cards — batch-lookups callsigns via QRZ/HamDB to populate theirGrid for QSOs logged offline
- Optional park location fallback for myGrid on share card map (Settings → POTA Activations → Share Card)
- RST suffix parsing in quick entry: append R (received) or S (sent) to RST values (e.g., "559S 579R") for explicit assignment
- Configurable RST order in quick entry: `receivedFirst` (default) or `sentFirst` for two unsuffixed RST values
- RST conflict detection: warns when duplicate R or S suffixes are entered

## [1.64.0] - 2026-03-16

### Added
- MetricKit performance monitoring: collect daily metric and diagnostic payloads, upload to server with device metadata, offline queue with 50-file cap and 7-day expiry
- Route view appear/disappear, tab switch, lazy tab load, and orientation change events through MetricKit uploader for server-side telemetry
- Replace custom MainThreadHangDetector with MetricKit native hang diagnostics (MXDiagnosticPayload)
- Sync error diagnostics: classify, group, and surface upload and download failures with actionable guidance (e.g., "QRZ API key invalid — update in Settings → QRZ")
- Sync issue banner on dashboard sync card links to detailed diagnostics view with "needs attention" vs "will retry" grouping
- Anonymous sync error telemetry to activities server for identifying systemic service issues (opt-in, community features only)
- Copy Hang Summary button in startup profile viewer — exports plain-text hang report with environment context, correlated milestones, phase durations, and scaling projections
- Phase duration analysis in hang summary — automatically pairs start/done milestones, shows per-record rates and memory deltas
- Scaling projection in hang summary — linear extrapolation of O(n) phases to 5K/10K/25K QSOs

### Changed
- Consolidate logger callsign info card — inline name with callsign, merge detail chips into wrapping flow layout, combine footer elements into single row

### Fixed
- Fix startup crash caused by MainActor isolation violation in PerfUploader — DeviceMetadata, PerfEvent, and PendingPayload had `@preconcurrency Codable` whose synthesized `encode(to:)` inherited MainActor isolation, crashing when encoded on the PerfUploader actor's background executor
- Clear upload flags when soft-deleting QSOs — prevents hidden QSOs from being re-flagged for upload by reconciliation, stopping phantom sync attempts to services
- Add isHidden guard to QRZ reconciliation paths — prevents deleted QSOs from being re-flagged for upload during sync
- Eliminate tab-switch hangs: guard GridTrackerCard, NeedsCard, FriendActivityCard, and ActivityLogCard against redundant work on tab re-appear (21 hangs → 1 hang)
- Fix FriendsOnAirCard firing redundant POTA API calls — add debounce to sync notification handler, reduce from 5+ to 2 loads per launch
- Reduce SCP callsign query memory from +184 MB to -10 MB — autoreleasepool wrapper forces SwiftData object release between batches
- Optimize SCPDatabase.merging to avoid 4 simultaneous copies of 80K callsigns — uses in-place Set insertion and merge-sort
- Defer startup backup by 2s to avoid overlapping with peak startup memory (eliminates +329 MB concurrent spike)
- Fix duplicate ModeEquivalence.family() call in NeedsEngine — was computed twice per QSO
- Add autoreleasepool to NeedsEngine QSO batch loop to reduce memory accumulation

## [1.63.0] - 2026-03-15

### Added
- Multi-day event support: add multiple days with individual time ranges when submitting events; event detail view displays per-day schedules
- Timezone picker: change event timezone via searchable picker with UTC offsets instead of auto-detect only

### Fixed
- Fix missing return statements in event submit request builders

## [1.62.2] - 2026-03-15

### Changed
- Extend profiler to continue recording past startup — tracks view renders, tab switches, and lazy content loads; add `.viewProfiled()` modifier for custom view instrumentation; profile view shows startup vs runtime sections with live refresh

## [1.62.1] - 2026-03-15

### Added
- Create LoggingSessions from POTA activation metadata during sync — preserves activation context (park, date, callsign, timestamps) through the download pipeline instead of re-deriving groups from QSO data; one-time forced POTA resync creates sessions for existing activations

### Fixed
- Fix redundant stats recomputation on every tab switch

## [1.62.0] - 2026-03-14

### Added
- Add user-submitted events: discover nearby ham radio events (club meetings, hamfests, field days, swap meets) on a map + list view with radius and type filters; submit events with address autocomplete and map pin confirmation; track submitted events with approval status in My Events; push notifications on event approval/rejection

## [1.61.1] - 2026-03-14

### Added
- Add startup profiler for diagnosing launch performance — records timestamped milestones across all threads, persists JSON trace to disk, shareable from Settings → Developer → Startup Profile (off by default, toggle in dev mode)

## [1.61.0] - 2026-03-14

### Changed
- Combine conditions, band openings, DXpeditions, and contests dashboard cards into unified "On Air Now" card with expanded sheet — progressive disclosure replaces four separate cards with a single glanceable summary
- Move Swift build, unit test, and performance test CI jobs from GitHub Actions (macOS runners) to Xcode Cloud — eliminates ~$84/month in CI costs using the free 25-hour tier

### Fixed
- Fix notification spam: filter award spot notifications by modes the operator actually works, require 25+ states before WAS notifications activate, and add adaptive daily budget (starts at 25, shrinks when user doesn't log notified callsigns, grows when they do)
- Fix QSL confirmations not syncing from LoTW and QRZ: LoTW incremental sync only fetched new QSOs by upload date (`qso_qsorxsince`), missing confirmations that arrived later — now also queries `qso_qslsince` to catch newly confirmed QSOs; QRZ `MODSINCE` doesn't reflect confirmation changes, now fetches `STATUS:CONFIRMED` alongside incremental sync to catch new confirmations; `lotwConfirmed` flag was hardcoded to `false` for QRZ-sourced QSOs and the merge logic never propagated it
- Fix iPhone 11 memory crashes: batch all unbounded QSO fetches (brag sheet, dedup, two-fer, PHONE/SSB, service presence repair services) from ~1.3 GB worst-case to ~56 MB; eliminate NeedsEngine callsignBands array; release cached brag sheet snapshots after computation

## [1.60.0] - 2026-03-13

### Added
- Add QRZ callbook lookups to CW Sweep loggers (popup and quick entry) — displays operator name, location, license class, previous callsign, and callsign change notes alongside existing HamDB and Polo notes data
- Add optional auto-sync: periodically syncs with all configured services while the app is in the foreground (off by default, configurable interval in Sync Sources settings)
- Add mobile contesting: contest session setup with template picker, dynamic exchange fields, dupe checking, live scoring, and Cabrillo 3.0 export
- Move ContestEngine, ContestExchangeParser, CabrilloExportService, ContestTemplateLoader to shared CarrierWaveData package (8 bundled contest templates: Field Day, CQ WW CW/SSB, ARRL DX, NAQP CW, Sweepstakes, State QSO Party)

### Fixed
- Fix band case mismatch: QRZ import stored bands as uppercase ("20M") while ADIF import used lowercase ("20m") — normalize QRZ import to lowercase and add one-time data repair for existing QSOs
- Fix POTA mode deduplication: USB/LSB/AM/FM/DV contacts now match SSB in dedup keys — prevents duplicate QSOs when POTA returns "SSB" for phone contacts logged as USB/LSB
- Fix startup crash resilience: ModelContainer init now retries after deleting corrupt store instead of calling fatalError
- Fix activity row dead touch zones: add contentShape to ActivityItemRow and ConsolidatedActivityRow so Spacer areas register taps
- Fix session QSO count not updating live: SessionsIdleView now refreshes on .didLogQSO notification
- Fix FT8 audio engine crash when resuming after audio interruption (alarm, phone call) — re-activate audio session before restarting engine to prevent NSException from stale audio graph

## [1.59.0] - 2026-03-12

### Changed
- Consolidate `metadataModes` constant into shared `QSOMode` in CarrierWaveData — removes 25+ duplicate definitions across iOS and macOS
- Move `SDRTranscriptModels` to CarrierWaveData for cross-app sharing
- Move `UnitFormatter` to CarrierWaveCore for cross-app sharing
- Add `.badgePill()` view modifier to replace repeated capsule badge styling pattern
- Add `ADIFParser.extractFields()` and `ADIFParser.parseTimestamp()` public methods — removes duplicated parsing from QRZ, Club Log, eQSL clients
- Add `TextProtocolParser` for shared `;`-terminated response extraction (Kenwood/Yaesu)
- Add `SpotColorScheme` utility consolidating spot source/needed colors (CW Sweep)
- Add `RadioManager.tuneToSpot()` consolidating XIT-aware tune logic (CW Sweep)
- Move `SOTASpot`, `WWFFSpot`, `WWFFAgendaItem`, `POTASpot`, `RBNSpot` to CarrierWaveCore for cross-app sharing
- Move `SOTAClient`, `WWFFClient`, `Ham365Client` to CarrierWaveCore for cross-app sharing
- Move `FullADIFExportActor` to CarrierWaveData with `ADIFExportConfig` for app-specific branding

### Removed
- Remove deprecated `LicenseWarningBanner`, `LicenseWarningModifier`, `.licenseWarning()` (replaced by `FrequencyWarningBanner`)
- Remove unused `MorseDecoderDelegate` protocol (zero conformers)
- Remove dead `LoggerSettingsView` (replaced by `LoggerDetailSettingsView`)

### Fixed (CW Sweep)
- Fix status bar not updating when active session is stopped from iOS — add `.didSyncQSOs` observation for reliable iCloud sync change detection

### Added (CW Sweep)
- Add Grid Tracker sidebar item — HSplitView with Maidenhead field heatmap (click-to-filter), stats cards, and searchable/sortable worked grid list with CloudKit dedup
- Add native FT8/FT4 decode and transmit — macOS audio engine with CoreAudio device selection, waterfall spectrogram, decode list with DXCC enrichment, QSO logging (C1)
- Add FlexRadio panadapter — VITA-49 UDP receiver, wideband waterfall display with spot overlay, spectrum line, click-to-tune (C2)
- Add iOS↔macOS Handoff — NSUserActivity-based session continuity for logging and FT8 sessions via shared CarrierWaveData constants (C3)
- Add AI-assisted features — smart callsign completion from QSO history, propagation prediction by entity/band/hour, natural language log search (C4)
- Add multi-operator networked logging — Bonjour-discovered TCP server/client, shared dupe log, band locks, multiplier alerts, aggregate scoring (C5)
- Add SDR receiver integration — RTL-SDR/SDRplay/Airspy via rtl_tcp protocol, wideband waterfall, CW skimmer pipeline placeholder (C6)
- Add ADIF import with file picker, progress tracking, deduplication, and import report (File > Import ADIF or Cmd+Shift+I)
- Add ADIF export for full QSO log with streaming large-file support (File > Export ADIF or Cmd+Shift+E)
- Add LoTW sync — download confirmed QSOs, match against local log, update DXCC entity and confirmation status
- Add DXCC tracking view — entity count, band-slot matrix, Challenge score, and confirmed entity list, all driven by LoTW data
- Add DXCC sidebar item under Data section
- Add LoTW credential test and sync status to Accounts settings
- Add DXCC entity lookup via CTY.dat — callsign-to-entity resolution with auto-download and caching
- Add needed indicators on spots — color-coded status (NEW DXCC, NEW BAND, WORKED, CONFIRMED) in spot list, band map markers, inspector, and entry field summary
- Add DXCC entity column to spot list table
- Add FT8 digital mode to CW Sweep — waterfall spectrogram, decode table with sortable columns, session management with CQ/S&P/Listen modes, macOS CoreAudio device selection
- Fix ADIF export — port FullADIFExportActor to CWSweep (was referencing iOS-only code)

### Added
- Add Grid Tracker — native GridTracker-style visualizations with Maidenhead grid square heatmap on dashboard, full detail view with stats/search/sort, and toggleable colored grid polygon overlay on QSO map
- Add grid field region descriptions — approximate geographic labels (e.g., "Northeastern US / SE Canada") for Maidenhead fields in grid stats and detail views
- Add Maidenhead grid square overlay to QSO map — toggle to display 4-char grid boundaries and labels on the map
- Add grid square search — type a grid locator (e.g. FN31) to navigate the map directly to that grid
- Add current grid square indicator — shows the Maidenhead locator at the map center as you pan

### Fixed
- Fix memory crashes on iPhone 11 (4 GB) during startup — serialize cache loading (POTA/SOTA/WWFF/Notes) to cap peak memory, stream CSV parsing with enumerateLines, batch SCP repeat-callsign queries
- Fix memory crashes on iPhone 11 during POTA sync — scope intermediate arrays so raw and converted QSO lists don't coexist, release remote QSO map after reconciliation
- Fix memory crashes with large QSO databases (100k+) — batch StatsComputationActor fetch+convert with context.reset(), rewrite NeedsEngine as single-pass batched iteration replacing 5 separate unbounded fetches

### Changed
- Move DescriptionLookup and shared FT8 types (models, waterfall data, decode enricher) from iOS app to CarrierWaveCore for cross-platform sharing
- Move FT8QSOLogger protocol to CarrierWaveData
- Rename DXCCEntity to DXCCEntityRef to avoid naming conflict with CTYParser
- Bump CarrierWaveCore macOS minimum to 14 for @Observable support

## [1.58.0] - 2026-03-10

### Added
- Add callsign history page — unified view for any callsign showing identity, QSO timeline with inline recording clips, band/mode chart, map pin, tune-in recordings, friend activity, and notes; replaces FriendProfileView
- Add SOTA summit pins to park map — summits displayed as orange mountain pins with altitude, points, and activation count in callout; unified search across parks and summits
- Add kilo progress tracking to park map callout — show total QSO count and progress bar toward 1,000-QSO kilo award when tapping a park
- Add near-kilo parks to POTA awards — list parks within 100 QSOs of kilo with orange progress bars
- Add ARRL America 250 WAS award tracking — states worked in 2026 with overall progress, Triple Play (CW/Phone/Digital) breakdown, and color-coded state grid

### Improved
- Add accessibility labels to all icon-only buttons in logger panels, spots, solar, and mini player
- Ensure 44pt minimum touch targets on all interactive controls (HIG compliance)
- Replace hardcoded Color.black with adaptive alternatives for dark mode support
- Use Dynamic Type-scaling font sizes in end session flow, tour, and onboarding views

### Fixed
- Fix non-US park boundaries not rendering on map — add GeometryCollection support to GeoJSON decoder and make feature array decoding resilient so one malformed feature no longer breaks the entire response
- Fix sync crashes on memory-constrained devices (e.g. iPhone 11) — use fresh ModelContext per batch across entire sync flow so model objects are released between batches instead of accumulating in a single context

## [1.57.1] - 2026-03-09

### Added
- Add National Historic Trail rendering on park map — trails displayed as brown polylines fetched from /v1/trails API with caching and zoom-based simplification

### Fixed
- Fix park map polygon rendering performance — move geometry processing (CGPath union, Douglas-Peucker, skirt buffer) off main thread to eliminate UI hangs
- Fix sharp spikes extending from polygon boundaries — add miter-limit clamping to skirt buffer, fix ring-aware Douglas-Peucker to avoid seam artifacts, use latitude-corrected distance thresholds for spike removal
- Fix thick/random borders on park polygons — remove duplicate stroke from skirt overlay (fill only), eliminate overlapping ForEach passes
- Fix CGPath boolean union distortion at higher latitudes — project to equirectangular space before union operations
- Fix GeoJSON decoder discarding interior rings (holes) from Polygon and MultiPolygon geometry
- Improve park map viewport culling — only render boundaries that intersect the visible region, use bbox filtering for tap hit-testing
- Precompute skirt rings at boundary creation time instead of recalculating per render frame

## [1.57.0] - 2026-03-09

### Added
- Add Smart Spot Recommendations — automatically detect DXCC, WAS, POTA Hunter, WWFF Hunter, and Challenge needs from QSO history and highlight matching spots with priority badges
- Add CTY.dat parser and download service for DXCC entity lookup from callsign prefixes
- Add NeedsEngine background actor computing operator needs from QSO data
- Add needs-only filter toggle and needs-based sort order in Activity Log spots list
- Add needs summary card showing on-air matches in Activity Log
- Add Smart Spots dashboard card with DXCC/WAS progress and on-air needs count — tapping the card now opens a detail sheet showing full needs breakdown, custom needs, and HamAlert export
- Add toast and local notifications for spots matching operator needs (configurable priority threshold)
- Add custom needs (callsign patterns, US states, park references) with management UI
- Add HamAlert export — generate trigger configurations from current needs (text or direct API push)
- Add Smart Spots settings with notification controls, tracking toggles, and HamAlert credential management

### Changed
- DXCC progress now shows tiered milestones (100 for DXCC award, then 150/200/250/300/325 Honor Roll/340 Top of Honor Roll) instead of raw entity count vs total known entities
- DXCC tracking filters QSOs by operator's primary grid square for accurate award tracking
- HamAlert integration now uses session-based auth (username/password) matching the hamalert.org web API instead of bearer token auth
- Add Needs widget showing spots matching operator needs on the home screen
- Add FlexRadio SmartSDR support to CW Sweep — connect to FLEX-6400/6600/6700 via TCP/IP network, with automatic LAN discovery and manual IP entry
- Add collapsible sections to dashboard (My Station, Social, Stats & Awards, Tools, Services)
- Add "Customize Dashboard" sheet to toggle individual card visibility (accessible via toolbar icon)
- Hidden cards and collapsed sections persist across sessions
- Add DXpeditions dashboard card with Ham365.net calendar integration showing on-air and active DXpeditions, with full list view via "See All" (iOS); add DXpeditions sidebar item in CW Sweep
- Add Park Map view accessible from Map tab toolbar — browse POTA parks with boundary polygon overlays, search by name or reference, and view park details including acreage and designation

## [1.56.0] - 2026-03-07

### Added
- Add POTA activator awards tracking with progress toward 8 award categories (unique parks, DX entities, rover, repeat offender, park-to-park, kilo, LaPorta N1CC, six pack)
- Add multi-step end session flow with session summary, POTA upload, and brag sheet in a single guided sheet
- Add visible red "End" button in session header for quick session ending
- Add session "More" menu with pause, spot mismatch review, and delete options
- Consolidate activity feed entries from same operator/time window into expandable groups (DX contacts, friends, milestones)
- Enrich DX contact and friend activity entries with operator name and DXCC entity

### Changed
- Auto-sync club member lists on app launch and foreground resume (no longer requires tapping into each club)

### Fixed
- Combine downloaded POTA QSOs into logging sessions automatically during sync
- Fix club memberships not appearing in logger until each club was manually refreshed
- Add automatic retry with exponential backoff for LoTW sync transient errors (SSL certificate failures, connection resets, timeouts)
- Fix Tune In silently failing when KiwiSDR connection fails; now retries multiple candidates
- Add 500 km distance cap to nearby SDR search (regional only, not global)
- Show error alert when no receivers are available instead of failing silently
- Sort club member spots deterministically by callsign in all spot views

## [1.55.0] - 2026-03-06

### Added
- Add Yaesu CAT protocol support in CW Sweep — FTDX10, FT-991A, FT-710, FTDX101D with frequency, mode, PTT, RIT/XIT, clarifier offset, and CW keying via keyer memory
- Azimuthal equidistant projection map with live spot density heatmap and antenna radiation pattern overlay
- Antenna type selector with compass-based or manual orientation for pattern visualization
- Band, mode, and distance range filters for the azimuthal view with current-value labels
- QSO visibility toggle and loading indicators on the azimuthal map
- Degree annotations and tick marks around azimuthal circle edge
- All-source spot fetching (RBN, POTA, SOTA, WWFF) with HamDB grid enrichment for map projection
- Resolve operator grid from session/settings before falling back to GPS
- World rotation (heading-up) instead of antenna rotation on the azimuthal map
- Prominent 36pt bearing display with HIG-compliant 44pt touch targets
- Accessible from Map tab toolbar and iPad logger sidebar
- Apple Maps tile underlay for azimuthal map with per-pixel Mercator-to-azimuthal reprojection
- Inverse azimuthal equidistant projection (`inverseProject`) for geographic coordinate recovery
- Pinch-to-zoom on azimuthal map with visual tile scaling during gesture
- Red heading indicator triangle at top of compass circle
- Centered loading overlay on azimuthal map while spots load
- Add radio command palette (Cmd+Shift+P) for CW Sweep — parse-and-confirm pattern for frequency, mode, band shortcuts, and split directives with real-time token feedback (CAR-123)
- Add named commands to radio palette: QRZ/? lookup, SPOT to cluster, PARK/SUMMIT session references, PWR/QRP power setting (CAR-123)
- Add Phase 3 commands to radio palette: CQ macro, WPM/SPEED, RUN/S&P contest mode, FIND callsign, LAST N QSOs, COUNT session stats (CAR-123)
- Add fuzzy command suggestions, `>` bridge between app and radio palettes, and custom command aliases to radio palette (CAR-123)
- Add radio status footer with live frequency, mode, RIT/XIT state, and TX indicator to radio palette
- Worked All States (WAS) dashboard card — shows QTH-only state progress mosaic with tap-to-inspect callsigns (CAR-126)
- HamDB fallback for callsign lookup when QRZ is unavailable — grid, name, QTH, and license class now populate without QRZ credentials (CAR-125)
- Re-enrich callsign data when QRZ credentials are added — logger re-triggers lookup automatically

### Changed
- Azimuthal map defaults: show map tiles, hide QSOs and antenna pattern on first load
- Redesign azimuthal header: compact Compass/Manual segmented picker, full-width manual slider
- Move antenna pattern picker from header to scrollable filter pills row
- Implement `qsy://` URI scheme for inter-app ham radio interoperability (spot, tune, lookup, import, log actions)
- Network health monitor: detect and warn when web requests consistently fail (QRZ lookups, syncing, etc.)
- Show lookup error banner while callsign field is focused (previously only visible after dismissing keyboard)
- Show warning when starting a POTA activation within one hour of UTC midnight

### Fixed
- Fix dashboard freezing during stats computation — isolate progress indicator to prevent activity grid re-renders, precompute grid layout values once per frame instead of per-cell (CAR-127)
- QRZ callsign lookups using 30-second timeout (now 10s) causing long hangs on degraded networks
- Lookup errors invisible during active logging when keyboard was visible
- Hunter Log spots not reloading after navigating away and back (required app restart)
- Hunter Log layout unusable in landscape orientation (now uses two-pane layout)
- Fix iCloud sync not pushing data since Feb 20 — `forceFullSync()` now marks all records dirty before scheduling
- Fix missing `cloudDirtyFlag` on LoggingSession creation, end, and pause
- Fix missing `cloudDirtyFlag` on ServicePresence creation and upload status updates
- Fix missing `cloudDirtyFlag` on ActivationMetadata creation and updates

## [1.54.1] - 2026-03-05

### Added
- FT8 channel picker for CQ calling — recommends least-occupied channels based on recent decodes
- Waterfall tap-to-select mode for manual TX channel placement
- TX frequency badge in band/status row (tappable to re-open picker)

## [1.54.0] - 2026-03-04

### Changed
- Redesign FT8 comms interface with conversation-centered layout
- Replace active QSO step indicator with full TX/RX conversation transcript
- Add inline message override picker for manual sequence control
- Add CQ modifier menu (POTA, DX, SOTA) to control bar

### Fixed
- Fix S&P mode sending wrong TX message (missing R-prefix on roger+report)
- Fix CQ QSOs never completing (now logs when RR73 sent, not waiting for 73)
- Fix TX slot parity (transmit on opposite slot from decoded station)
- Fix TX frequency hardcoded to 1500 Hz (now auto-set from decoded station)

### Added
- TX status line showing armed/transmitting/halted state
- Focus mode filtering decode list to directed + CQ only
- Freshness aging on decode rows (opacity fade, stale removal)
- Cycle age tracking on enriched decodes
- RX/TX frequency markers on waterfall
- Tap-to-call inline confirmation with double-tap shortcut
- Halt/resume TX without aborting active QSO
- Compound callsign matching in state machine

## [1.53.0] - 2026-03-04

### Added
- States Worked signal mosaic in session detail — 10×5 grid showing US states with green intensity by QSO count, tap for callsign details
- Auto-detect callsign owner changes by cross-referencing QRZ and HamDB names during lookup
- Show "HamDB is still updating" note in logger callsign card and CW info card when names differ
- Callsign change detection in About Me profile refresh with QRZ cross-check
- Persist callsign change notes on QSOs — detected changes now survive across sessions and appear in QSO detail, edit sheets, logger rows, and hunter recent QSOs
- Add WWFF agenda fetching from Spotline service (spots.wwff.co/agenda.json) for scheduled activations
- Add WWFF award tier model based on Global Rules V5.10 (activator references, points, DXCC, continents; hunter references, DXCC, continents; park-to-park)
- Add WWFF activation progress tracking with per-reference QSO counts (44-QSO threshold), multi-visit aggregation, and activator point calculation
- Add WWFF representative directory with lookup by reference, program code, or DXCC entity
- Add WWFF representative email compose for log submissions with pre-filled subject/body
- Add WWFF activation progress view showing award tier progression and per-reference status
- Enable `.locationLookup` and `.progressTracking` capabilities for WWFF program
- Add "Tune In" feature — listen to any spotted activation via KiwiSDR directly from spot rows
- Smart receiver auto-selection based on activator proximity
- Persistent mini player bar (Apple Music-style) above tab bar with live status, mute, and close
- Expanded player sheet with receiver details, audio level meter, and change receiver
- Live CW transcription from WebSDR audio in expanded player (chat bubble view with detected callsigns)
- Clip bookmarking during live Tune In listening with badge count on expanded player
- Spot metadata (callsign, park/summit, band) attached to Tune In recordings
- Enhanced recordings list with callsign header, park/summit badges, clip count
- Standalone tune-in sessions from hunter log (not tied to active logging session)
- Context menu "Tune In to [callsign]" on all spot rows (hunter log, logger POTA spots, sidebar)
- Cellular data warning on first use (~5 MB/hour)
- Auto-disconnect when app backgrounds
- Auto-retune on QSY detection — monitors RBN for activator frequency changes with retune/dismiss banner
- Receiver quality monitoring — suggests switching to a better KiwiSDR when SNR degrades
- Follow activator — bell toggle to track callsigns across sessions (persisted to UserDefaults)
- Design document for full Tune In feature roadmap (docs/features/tune-in.md)
- Add recommended club notes section to Callsign Notes settings — shows clubs with notes files the user hasn't added yet, with one-tap add
- Add listening strategy picker for Tune In — choose "Best signal" (near strong RBN), "Near the activator", or "Near my location" before connecting

## [1.52.0] - 2026-03-03

### Added
- Group club members first in hunter log, POTA/SOTA spots, and session spots with section headers
- Show club name badges on spot rows for club members (replaces plain icon)
- Add "Club Members Only" filter toggle in hunter log spot filters with removable chip
- Add club members summary card to session detail view showing which contacts were club members
- Add club hub with member list, activity feed, map, and stats dashboard (CAR-108)
- Show club member badges in logger callsign input, QSO detail, spot rows, and activity feed
- Add club member map with clustered pins, QRZ coordinate lookup (HamDB fallback), and 30-day location cache
- Show progress bar during member location lookups with resolved/total count
- Add club member online status indicators (on-air via RBN spots, recently active, inactive)
- Add ClubSyncService with offline caching and in-memory callsign set for fast lookups
- Add cross-reference suggestions in session start wizard — selecting a POTA park suggests matching WWFF/SOTA references (and vice versa) via number and name matching
- Add SDR auto-start option — saves last-used KiwiSDR receiver and offers a toggle to auto-connect when starting a new session
- Add WWFF (World Wide Flora & Fauna) as a selectable activation program with spot browsing from WWFF Spotline, reference directory autocomplete with search/nearby picker, and External Data cache management
- Add Kenwood/Elecraft K3 text command protocol for BLE radio control (`;`-terminated ASCII commands)
- Auto-detect radio protocol from rig name in Logger and Hunter Log (Icom/Xiegu → CI-V, Kenwood/Elecraft → Kenwood)
- Add manual protocol override picker in BLE Radio settings
- Add Super Check Partial (SCP) callsign database integration with real-time suggestions, confidence indicator, and did-you-mean typo detection in the logger
- Add callsign autocomplete suggestions to Hunter Log quick log section
- Weight callsign suggestions by contact history (most-contacted stations first)
- Show contact count badges and spot indicators on suggestion pills
- Add SCP database status section to External Data settings
- Add expandable QTH, Grid, Park, and Notes fields to Hunter Log quick log (hidden by default, toggle in settings)
- Add callsign suggestions and expanded fields description to Hunter Log tour
- Tune connected BLE radio to spot frequency and mode when tapping a spot in Hunter Log

### Fixed
- Fix OOM crash during sync on memory-constrained devices (iPhone 11, etc.) — callsign whitespace repair loaded all QSOs into memory; now uses targeted predicate and batched processing
- Replace `fatalError` in `mergeFetchedGroup` with thrown error to prevent process kill on invariant violation
- Fix POTA sync permanently skipping failed activations — non-timeout errors incorrectly marked activations as processed, preventing their QSOs from ever being downloaded on future syncs (caused streak gaps when QSOs existed on POTA.app but not in Carrier Wave)
- Fix callsign notes clipping markdown links — URLs with special characters (like @) caused `AttributedString(markdown:)` to strip brackets, breaking link rendering
- Fix hunter log setup button on dashboard not presenting setup sheet due to miniTour sheet modifier conflict
- Fix missing default profile during hunter log setup — pre-fill radio and power from existing session defaults
- Fix equipment not shared between hunter log profiles and sessions — replace antenna text field with shared equipment picker, add key and mic fields to station profiles
- Fix club activity tab not loading — response format mismatch between server and client
- Fix club map not zooming to show member locations — now auto-fits to all member pins

### Changed
- Consolidate My Profile, Friends, and Clubs into a community section on the Activity tab
- Sort club member list by on-air status first, then recently active, then inactive (alphabetical within each group)
- Show relative age on club member spots and last-seen time for inactive members
- Show richer activity descriptions in club activity feed (QSO details, park names, session summaries)
- Unify all map views to match Activity feed style: pin markers (circle+stem), realistic elevation, and white trace lines
- Redesign callsign suggestion pills with larger touch targets, tinted backgrounds, and magnifying glass icon
- Move SCP detail rows (last checked, callsign count, update now) from Logging settings to External Data
- Extract shared callsign suggestion logic into CallsignSuggestionProvider
- Show spots immediately before HamDB state enrichment for faster perceived loading

### Fixed
- Fix crash during back-swipe navigation on iOS 26 caused by UICollectionView feedback loop in session timeline (replace GeometryReader with Canvas)
- Fix Hunter Log spots stuck on loading spinner (remove blocking await in view task, make cache loads fire-and-forget)
- Fix BLE radio first connection attempt always failing (defer connect until Bluetooth is powered on)
- Add 15-second timeout to POTA spot fetch (was using URLSession.shared default of 60s)
- Remove propertiesToFetch from contact count query to avoid SwiftData hang

## [1.51.0] - 2026-03-01

### Fixed
- Fix false DUPE labels in Hunter Log by filtering to only activity-log QSOs (excludes activator sessions, synced QSOs, imports)
- Fix Hunter Log dupe detection to respect mode families (20m CW no longer marks 20m SSB as dupe)
- Sort dupe spots to bottom of Hunter Log spot list with strikethrough on callsign
- Refresh Hunter Log worked-before cache when QSOs arrive via sync or iCloud
- Re-fire Hunter Log cache at UTC midnight so day boundary doesn't show stale dupes
- Handle CloudKit atomic batch failure without error spam (collateral-damage records retry silently)

### Changed
- Merge sync progress card and service list into unified SyncCard at bottom of dashboard
- Move sync trigger from toolbar button into SyncCard header
- Show "Synced X ago" in SyncCard header instead of statistics card
- Remove duplicate "Synced X ago" from statistics and combined streaks cards
- Show delta context during sync (e.g., "3 new · 312 synced") to clarify incremental fetches
- Skip re-fetching already-synced POTA activations during incremental sync (only fetch new)

### Added
- Add POTA hunter respots: auto-post respot when logging from a POTA spot, with optional custom message
- Add contest calendar dashboard card showing active and upcoming contests from WA7BNM Contest Calendar
- Add BLE radio control via CI-V over Nordic UART Service (experimental — requires external BLE CAT proxy hardware)
- Add BLE radio settings with device scanning, selection, and CI-V address configuration
- Add radio control panel in logger showing frequency, mode, and connection status
- Add RADIO/CAT command to open radio control panel from logger command bar
- Add inline radio connection badge in session header (green=connected, orange=configured)
- Add bidirectional frequency/mode sync between app and radio with 2s polling
- Add "Set My Grid" batch action in session detail menu to retroactively set grid square on all QSOs
- Support per-park grid editing in rove sessions — each park stop gets its own grid field
- Show per-QSO grid badges in session detail when session-level grid is missing

## [1.50.2] - 2026-02-28

### Fixed
- Fix Watch app crash from MainActor.assumeIsolated in Timer callback
- Add direct network fetching to Watch app for solar conditions and POTA spots (no longer requires iPhone app data)
- Enable watchOS Simulator platform for Watch app testing

## [1.50.1] - 2026-02-28

### Fixed
- Fix crash in POTA activation grouping when split key has unexpected format (index out of range)
- Fix double-nesting navigation in More tab by capping visible tabs and isolating Settings deep-link machinery

## [1.50.0] - 2026-02-28

### Added
- Add logger tour pages explaining quick entry and per-field entry settings
- Add visual ARRL-style band chart to Band Plan sheet with license class and mode zone display modes
- Add segmented picker to toggle between By Class and By Mode chart views
- Add color-coded legend for chart display modes
- Add tap-to-select frequency from chart zones
- Add 60m channel dot rendering in band chart
- Add FT8, RTTY, AM, and FM frequency dicts to BandPlan (single source of truth)
- Add time display and tap-to-hunt to Friends On Air card
- Add shared keychain group for cross-app credential sync with QSO Ledger
- Add logger tour pages explaining quick entry and per-field entry settings

### Changed
- Rename "State" field to "QTH" for better DX compatibility
- Re-order compact fields from State | Sent | Rcvd to Sent | Rcvd | QTH (matches QSO exchange order)
- Suppress QRZ lookup card while compact fields are focused to prevent layout shift
- Consolidate duplicate frequency tables from LoggingSession into BandPlan
- Collapse prefix/suffix behind disclosure group in session start wizard

### Fixed
- Fix QRZ credentials entered during intro tour not appearing in onboarding flow
- Fix 160m band plan to include SSB/PHONE modes (was CW/DATA only)
- Fix 80m Extra-only phone segment to correct range 3.600-3.800 MHz (was duplicating General range)
- Fix 20m Extra phone segments merged into single 14.150-14.225 MHz (was two leftover Advanced splits)
- Fix 15m Extra phone segments merged into single 21.200-21.275 MHz (same Advanced split issue)
- Fix 10m Technician notes from "Tech CW only" to "Tech CW/Data" (DATA was already in modes)
- Add missing 10m upper segment 28.500-29.700 MHz for Phone/AM/FM
- Split 6m into CW-only (50.0-50.1) and all-modes (50.1-54.0) sub-bands
- Split 2m into CW-only (144.0-144.1) and all-modes (144.1-148.0) sub-bands
- Add missing 60m usage zones for ARRL band plan
- Fix 80m CW suggested frequency from 3.530 to 3.560 MHz (QRP calling freq)
- Improve band chart touch targets and Friends On Air VoiceOver accessibility

## [1.49.0] - 2026-02-27

### Added
- Export full QSO log as ADIF file from Settings > Data & Tools, with batched background export, determinate progress bar, and share/save/clipboard actions

### Fixed
- Fix app freeze on cold start from spots widget tap by deferring synchronous Keychain reads and SwiftData queries off the view construction path: lazy POTAAuthService token load, deferred ActivityLogManager service config and stats queries, replaced @Query with @State + .task in ContentView and ActivityLogView, batched state updates, and deferred navigation push

## [1.48.1] - 2026-02-27

### Fixed
- Fix focus not returning to callsign text field after editing compact fields (RST, notes, etc.) and tapping LOG
- Fix QRQ Crew spot detection using notes cache with nickname fallback
- Fix QRQ Crew spot bugs and dashboard brag sheet badge display

## [1.48.0] - 2026-02-27

### Added
- QRQ Crew spot: auto-seed QRQ Crew members list as a callsign notes source
- QRQ Crew spot: detect when both operators are QRQ Crew members after logging a POTA QSO
- QRQ Crew spot: prompt for CW speed and post a spot message with member names/numbers
- QRQ Crew spot: auto-post setting to skip confirmation and use last entered WPM
- SDR recording clip selector: draggable range handles for precise clip boundary selection
- SDR recording clip selector: QSO markers and segment boundaries on clip waveform
- SDR recording clip selector: playback preview to hear selected range before exporting
- SDR recording clip selector: CW transcript snippet preview for selected range
- SDR recording share card: branded image with waveform, receiver info, frequency/mode, QSOs, and transcript excerpt
- SDR recording share card: save to Photos and share as image
- SDR recording clip export: embedded M4A metadata (title, artist, description, date)
- SDR recording clip share: transcript text included alongside audio
- Comment park action setting: choose how park references in ADIF COMMENT fields are handled — ignore, set as "their park" (default), or set as "my park"
- Sync import confirmation: prompt user before importing when more than 50 QSOs are downloaded
- Sync export confirmation: prompt user before uploading when more than 50 QSOs are queued for upload
- Strip park references from COMMENT field on ADIF export to prevent downstream re-parsing by POTA/QRZ/Club Log
- Cross-device iCloud sync: fetch changes on foreground re-entry (scenePhase), network recovery (NWPathMonitor), and 30s polling during active logging sessions
- SOTA spots from SOTAwatch API in unified HUNT spots panel
- Multi-program sessions: activate POTA and SOTA simultaneously
- HUNT logger command replacing POTA (POTA kept as alias)
- Program toggle chips in session start sheet
- Source filter (All/POTA/SOTA/RBN) in activity log spot filter
- SOTA spot rows with summit reference, name, and points display
- SOTA source badges in activity log spot rows
- P2P fields (SIG, SIG_INFO, POTA_REF) in POTA upload ADIF
- MODE/SUBMODE splitting in ADIF generation (USB→SSB+USB, LSB→SSB+LSB, PSK31→PSK+PSK31)
- One-time data repair to fix hunting QSOs misidentified as activations
- Add Agents on Air (AoA) as an activity program with eye icon, mission reference field, and hunter/data entry capabilities
- Add AoA mission reference field in session start (required to begin AoA session)
- Add AoA per-QSO code exchange field in logger expanded fields
- Display AoA mission reference in session title and session list
- Add AoA code exchange editing in QSO edit sheet

### Changed
- POTA spots command renamed to HUNT with binoculars icon
- Session start uses toggle chips instead of segmented picker
- Spots panel header changed to "Activator Spots" with binoculars icon
- iPad sidebar tab renamed from POTA to Hunt
- Session display uses programsDisplayName and programsIcon for multi-program support
- Standardize FREQ precision to 6 decimal places in POTA and QRZ ADIF uploads

### Fixed
- Fix comment-extracted park references incorrectly assigned to parkReference (activator field) instead of theirParkReference, causing hunting QSOs to be uploaded as bogus single-QSO activations
- Add MY_POTA_REF as fallback for mySigInfo in ADIF parser

## [1.47.0] - 2026-02-26

### Fixed
- Fix crash in Phone/SSB duplicate repair when ServicePresence records are concurrently deleted by presence dedup service (race condition between repair services)
- Add isDeleted guards to QSO service presence helpers to prevent accessing invalidated SwiftData backing data
- Fix SOTA QSOs not inheriting summit reference from session (fixes activity detection and ADIF export)

### Changed
- Theme brag sheet share card with dark purple gradient matching session brag sheet cards
- Add map with clustered QSO markers to brag sheet share card (known issue: map background misaligns at wide geographic spans)
- Add Professional Statistician Mode section to brag sheet share card (box plots, distributions)
- Pre-render brag sheet share image with full-size preview and ShareLink
- Change weekly share card headline to "Last 7 Days in Radio"
- Derive FT8 dial frequency from band selection (no manual frequency entry)
- Update FT8 waterfall to scroll downward with newest data at top
- Add Hz frequency labels below FT8 waterfall (500-2500 Hz axis)
- Stream audio continuously to FT8 waterfall instead of every 15 seconds
- Redesign FT8 decode list with three sections: Directed at You, Calling CQ, and All Activity (collapsed)
- Redesign FT8 active QSO card with step indicator (Call → Rpt → 73) and abort button
- Collapse FT8 debug panel behind tappable status pill showing audio health and decode count
- Add landscape two-column layout for FT8 session view (waterfall/controls left, decodes right)

### Added
- Add SOTA summit database: download summitslist.csv with 30-day auto-refresh
- Add summit picker with GPS nearby search and name/code search
- Add summit entry field in session start replacing plain text input
- Add shareable brag sheet cards via share button in brag sheet toolbar
- Add brag sheet dashboard card with drill-down to full stat view (weekly/monthly/all-time periods)
- Add brag sheet customization sheet with preset chips and per-stat enable/hero toggles
- Add always-visible FT8 debug panel with audio level meter, decode stats, and input picker
- Add audio input selection for FT8 sessions
- Add FT8DecodeEnricher service for enriching raw decodes with DXCC entity, distance, bearing, and worked-before flags
- Add enriched FT8 decode rows with DXCC entity, distance, grid, and achievement badges (New DXCC/State/Grid/Band/Dupe)
- Add compact mode toggle for FT8 CQ section via context menu on section header
- Add haptic feedback for directed-at-you decodes, CQ row taps, QSO completion, and POTA 10-QSO milestone
- Add session summary toast showing band, duration, and QSO count when stopping FT8
- Add haversine distance and bearing calculation to MaidenheadConverter
- Add FT8 status pill view with color-coded audio health and decode count
- Add SNR color badge with strong/medium/weak tiers
- Add period brag sheet stats infrastructure: model layer (stat types, categories, presets, configuration) and background computation actor for weekly/monthly/all-time stats

## [1.46.0] - 2026-02-25

### Added
- Add FT8 digital mode with full TX/RX capability via ft8_lib C library
- Add FT8 session view with compact waterfall, decode list, and auto-sequencing
- Add QSO state machine for automatic FT8 message exchange (CQ and Search & Pounce modes)
- Add FT8 encoder with GFSK tone synthesis for transmission
- Add first-time FT8 setup wizard for audio connection and radio configuration
- Add auto-logging of completed FT8 QSOs with dB signal reports
- Add FT8 integration with existing POTA/QRZ/LoFi sync pipeline
- Add expandable spots summary row to sessions list showing region pills, distance range, and spot detail (matches logger aggregation pattern)
- Link spots and QSOs in session detail view: QSO rows show antenna icon when matching human spot exists, human spot rows show checkmark/dashed-circle for logged/unlogged status

### Changed
- Improve session detail view flow: move QSO list up to primary position (after header and map), collapse equipment/notes/photos into a "Details" disclosure group, move POTA upload button inline with activation info
- Add stat strip (QSO count, duration, rate) to session and activation headers replacing flat LabeledContent rows; unify metadata grid pattern between POTA and non-POTA sessions
- Show inline map preview in session detail view (tap to open full-screen map); remove "View Map" from overflow menu
- Move spots section to bottom of session detail view, make collapsible (collapsed by default)
- Show spot comment text below each spot row in session detail
- Fix spot row text wrapping with lineLimit, fixedSize on region badges, and layoutPriority on callsign
- Drop trailing `.0` from whole-number frequencies in spot rows
- Remove debug text from spots summary row and spots section
- Merge Sessions and Logger into a single Sessions tab with state-driven view switching (idle shows session history, active shows logger)
- Remove segmented picker from Logs tab (now QSOs-only; sessions moved to Sessions tab)
- Rename Logger tab to Sessions with new icon; unhide by default for new and existing users
- Session manager lifecycle owned by SessionsTabView, shared down to logger

### Fixed
- Fix crash in SpotSummaryView and SessionSpotsSummaryRow when ViewThatFits evaluates region pill ForEach on background rendering thread (extract to standalone structs to avoid inheriting @MainActor isolation)
- Fix duplicate POTA QSO uploads caused by remote map overwrite when same park activated twice in one day (use formUnion instead of assignment)
- Add pre-upload dedup filter checking QSOs against POTA remote map as defense-in-depth
- Fix fetchQSOsNeedingUpload loading all QSOs into memory; query from ServicePresence side instead
- Add diagnostic logging to POTA gap repair to surface dedup key mismatches
- Reject QSOs with invalid/unknown band before POTA upload and alert user to fix data
- Fix POTA duplicate upload loop caused by gap repair re-flagging confirmed QSOs due to dedup key mismatch
- Fix reconciliation orphan reset re-uploading QSOs whose job aged out of POTA log
- Normalize callsigns across all POTA dedup key comparisons (strip /P, /M, /QRP suffixes)
- Normalize modes in POTA dedup keys (USB/LSB/FM/AM → SSB to match POTA's convention)

## [1.45.0] - 2026-02-24

### Added
- Add rich per-service sync progress card on dashboard during sync (shows waiting/downloading/downloaded/uploading/complete state for each service)
- Add POTA activation progress bar and LoFi QSO progress bar in sync card

### Changed
- Show descriptive phase text during transcription (uploading, analyzing, decoding, finalizing) with byte-level upload progress
- Simplify toolbar during sync to just a spinner (detail now lives in sync progress card)

### Fixed
- Fix transcript not loading from disk when reopening a recording (compact player pre-loaded the engine, causing full player to skip transcript load)
- Fix two-fer QSOs silently dropped from POTA upload batches (needsUpload checked wrong ServicePresence record)
- Fix confirmed POTA QSOs perpetually reset to needsUpload when old jobs purged from POTA job log
- Fix POTA remote map incomplete on incremental syncs (now fetches all activations for gap repair)
- Add activation-level progress reporting during POTA sync (shows fetch/map phase and activation count)

## [1.44.1] - 2026-02-24

### Added
- Add toggle to disable auto-sharing session summary to activity feed (Logger Settings > Sessions)
- Add local network usage description for connecting to personal radio servers
- Add UIFontMetrics scaling to keyboard accessory and callsign text field fonts
- Add Reduce Motion support to spot summary expansion animation

### Changed
- Replace print() logging with structured os.Logger in activities client and sync service

### Fixed
- Fix ADIF files shared via email appearing as inline text instead of file attachments

## [1.44.0] - 2026-02-24

### Added
- Add "Use a different callsign" toggle to LoTW, Club Log, and LoFi service setup for accounts registered under a previous or different callsign
- Add activity program registry model and API client for server-driven activation types
- Add ActivityProgramStore with local caching and bundled fallback programs
- Add UTC timestamps to recording transcript lines (shown on each operator change)
- Add chat-style conversation layout for 2-operator transcripts (OP 1 left, OP 2 right)
- Add State field to logger QSO edit sheet (shown when tapping right of callsign)
- Add "Share activity to feed" toggle in Activities settings (default on)
- Add per-item hide option via ••• menu on activity feed items
- Add server-side activity deletion when hiding own activities from feed
- Store server ID on ActivityItem for own reported and feed-synced activities

### Fixed
- Fix scroll position not returning to top when tapping callsign to edit in logger
- Fix quick entry (space + state) creating new QSO instead of updating during edit mode
- Fix form field changes (state, grid, park, RST, notes) not saved when editing QSO inline
- Fix state override not persisting when editing QSO (e.g., FL instead of home QTH PA)
- Fix potential crash from UICollectionView re-render when starting inline QSO edit
- Mark edited QSOs as cloud-dirty so iCloud sync picks up changes

## [1.43.1] - 2026-02-22

### Fixed
- Fix stale friend requests persisting after server-side deletion (retry with fresh token on INVALID_TOKEN, re-sync on action failure)

## [1.43.0] - 2026-02-22

### Fixed
- Fix spot comments appended repeatedly to QSO notes on every app restart
- One-time repair to deduplicate existing QSOs with repeated spot notes
- Fix duplicate service badges in QSO rows (collapse to one badge per service type)
- Fix duplicate QSO records from iCloud sync (UUID collision repair on startup)
- Fix duplicate ServicePresence records from iCloud sync (dedup repair on startup)
- Prevent future ServicePresence duplicates in iCloud inbound sync
- Fix crash in DeduplicationService when QSOs have duplicate UUIDs
- Fix callsign truncation in QSO list rows (never abbreviated with ellipsis)
- Fix contact count badge text wrapping (e.g., "x29" splitting across lines)
- Fix dedup key whitespace trimming mismatch between QSO model and processing actor
- Fix session controls bar pills wrapping to multiple lines (horizontal scroll safety net)
- Fix recording pill taking up an entire row (moved inline into session controls bar)
- Fix RBN spot command defaulting to list view instead of map
- Fix RBN spot map showing straight lines instead of geodesic arcs
- Fix false frequency warning when hunting activator with quick-entry RST
- Fix frequency picker sheet dismissing immediately on tap (added Done button)
- Fix spot comments button scrolled off-screen (moved before trailing Spacer)
- Fix last QSO row state text clipped at bottom of session log card (44→54pt row height)

### Added
- Add tap-to-edit QSOs in session detail view (opens full edit sheet with callsign lookup)
- Add interactive recording player with QSO span regions on waveform
- Add karaoke-style CW transcript panel with per-word highlighting and auto-scroll
- Add cw-swl server integration for recording transcription (upload, poll, cache)
- Add CW-SWL Server URL setting in Developer section
- Add collapsible QSO summary with inline active QSO indicator
- Add segment boundary markers on waveform for frequency/mode changes
- Add "Hide field entry form" toggle in Logger Settings for quick-entry users
- Add frequency picker hint about typing frequency in the command box

### Changed
- Unify POTAActivationDetailView into SessionDetailView (single detail view for all session types)
- Remove all ~50 inline swiftlint:disable comments across ~35 files by fixing underlying violations
- Disable `redundant_discardable_let` rule globally (required @AppStorage pattern)
- Add `scripts/` to SwiftLint excluded paths
- Add short algorithm variable names (`n`, `m`, `dp`, `e`) to identifier_name exclusions
- Extract `CategorySearch` struct to replace large tuple in CWSuggestionEngine
- Replace `try!` with `do/catch/fatalError` in AntennaDescriptionParser regex init
- Replace `buildStates()` function with dictionary literal in USStates
- Split long functions in BandPlanService, LoggerView+Modifiers, LoFiClient+Sync, SyncService+Download
- Move helper methods to extensions in RBNPanelView, SidebarRBNSpotsView, CloudSyncConflictResolver
- Rename `count` parameter to `commentCount` in SpotCommentsSheet
- Rename short variables and add CodingKeys in HAMRSModels, QueryAST, BandPlanService
- Extract dictionary to static property in USStates
- Reduce cyclomatic complexity in LoggerCallsignCard, QueryLexer, QueryCompiler
- Split LoggerView into twelve extension files by responsibility
- Split LoggingSessionManager into six files by responsibility
- Split SyncService+Process into three files by operation type
- Split CWTranscriptionService into two files (service state/API, decoder/audio processing)
- Split CallsignLookupService into two files (core lookup/cache, QRZ XML API)
- Split QueryCompiler into four extension files by compilation phase
- Split DescriptionLookup+DXCC into five extension files by region
- Split ChallengeTypes into three files (base types, progress/config, DTOs)
- Split QueryParser into three files (core parsing, field terms, condition building)
- Split OnboardingView into three files (main layout, step views, actions/helpers)
- Split LoggingSessionManagerTests into three files by test area
- Split LoggingSessionTests into two files by test area

### Fixed
- Fix nested ObservableObject in CW transcription: convert CWTranscriptionService, CWConversationTracker, and CWSuggestionEngine to @Observable so nested property changes propagate to views

## [1.42.0] - 2026-02-20

### Added
- Add persistent command strip on iPad logger: commands (RBN, POTA, SOLAR, etc.) are always visible at the bottom of the logger pane, independent of keyboard state
- Add resizable sidebar panes on iPad: drag the divider between logger and spots sidebar to resize, with width persisted across sessions
- Add Map tab to iPad sidebar: shows current session QSOs with geodesic arcs and rove stop markers
- Add session photo persistence in backups: `.cwbackup` bundle format includes `SessionPhotos/` alongside database, with backward-compatible restore for legacy `.sqlite` backups
- Extend iCloud sync to SessionSpot and ActivityLog entities (LWW conflict resolution)

### Fixed
- Guard against accessing deleted QSO models in orphan repair, preventing InvalidFutureBackingData crashes
- Fix photo restore safety: use copy-to-temp-then-move to prevent data loss if copy fails during backup restore
- Fix SessionSpot conflict resolution setting dirty flag after accepting server version, preventing sync ping-pong
- Fix ActivityLog inbound merge using immutable createdAt as modification date (now uses dirty-flag semantics)
- Fix inbound ActivityLog deletion not clearing UserDefaults active log ID
- Fix createLog not setting cloudDirtyFlag on deactivated existing log
- Fix iCloud backup list showing near-zero size for .cwbackup bundles
- Add QSO editing from the Logs tab: tap a QSO to view details, then tap Edit to modify fields (callsign, band, mode, frequency, RST, location, notes)
- Add automatic database backup system with rolling snapshots on app launch, pre-sync, and pre-import
- Add manual backup and restore UI in Settings > Data & Tools > Backups
- Add iCloud Drive backup sync (2 most recent snapshots) for cross-device recovery
- Add restore mechanism with integrity validation, pre-restore safety snapshot, and post-restore iCloud sync pause
- Add iCloud QSO sync via CKSyncEngine: bidirectional sync of QSOs, sessions, service presence, and activation metadata across devices
- Add CloudSyncSettingsView with sync toggle, status display, last sync time, and iCloud account info
- Add iCloud sync status indicator on dashboard service list
- Add FRIEND badge on POTA spot rows, RBN spot rows, and hunter log spot rows for accepted friends
- Add "Friends On Air" dashboard card showing friends active in POTA spots
- Add "Friend Activity" dashboard card showing recent friend feed items
- Add friend spot notifications (toast + local notification) when friends appear in spots during monitoring
- Add friend spot notification toggle in Activities settings

### Changed
- Re-fetch callsign info from QRZ/HamDB when callsign is changed in the QSO edit sheet
- Mark iCloud QSO sync as experimental with confirmation dialog and auto-backup before enabling

### Fixed
- Fix iCloud sync conflict resolution using creation date instead of last-edit date, causing remote changes to silently overwrite local edits
- Fix iCloud sync notes merge growing unboundedly on repeated conflicts
- Fix new QSOs from logger and activity log not syncing to iCloud until edited
- Fix backup restore using wrong UserDefaults key to disable iCloud sync, leaving sync active after restore
- Fix backup QSO count showing 0 when SwiftData table name differs from CoreData convention
- Fix activity grid using local timezone for date grouping instead of UTC, causing QSO counts to disagree with Sessions view for users west of UTC
- Convert all user-facing QSO deletions to soft-delete (swipe-delete, clear QRZ/LoFi data, delete callsign alias QSOs) to prevent data loss
- Hide orphaned QSOs when CloudKit inbound sync deletes a logging session
- Replace full table scan in CloudKit dedup merge with targeted callsign+band+timestamp window fetch
- Fix clearQRZData and clearLoFiData performing full table scan instead of predicated fetch
- Fix doubled QSO/QSL counts on dashboard caused by SwiftData returning duplicate records when CloudKit metadata tables exist in store
- Disable SwiftData's built-in CloudKit sync (cloudKitDatabase: .none) since app uses CKSyncEngine directly
- Fix doubled QSO counts on dashboard service cards for POTA two-fer activations (count unique QSOs, not ServicePresence records)
- Fix dashboard stats excluding wrong metadata modes (WEATHER/SOLAR were not filtered, causing inflated QSO counts)
- Add one-time data repair to clear stale POTA sync state after schema rename, forcing full re-download
- Fix ModelContainer crash on launch caused by nonisolated CloudKit methods inside @Model class body under -default-isolation=MainActor
- Fix social pipeline dead state: auto-recover auth tokens across all community services (friends, clubs, activity feed, challenges) when token is missing or stale after reinstall/device change
- Fix POTA dead-state blind spot: reconciliation now handles records stuck with all flags false (not present, not submitted, not needing upload) by checking job log and recovering them
- Fix nil-date POTA error jobs being silently dropped from reconciliation tracking, leaving submitted QSOs permanently stuck
- Add POTA dead-state repair (matching existing QRZ pattern) to recover stuck upload records during sync
- Fix Live Activity showing stale QSO count after deleting QSOs from active session
- Fix QSO deletion not decrementing session QSO count or updating widget
- Fix QSY spot prompt not appearing when changing frequency via band or mode edit sheets (SwiftUI alert swallowed by simultaneous sheet dismissal)
- Fix mode edit sheet never prompting for QSY spot (return value was discarded)
- Gate first-frequency-set auto-spot on potaAutoSpotEnabled setting (previously spotted unconditionally)

### Changed
- Rename "Activity Log" to "Hunter Log" across all user-facing strings
- Refactor CloudSyncEngine into extension files (Inbound, Outbound, ConflictResolution, Helpers, ZoneAndState) for maintainability
- Extract CKRecordMapper Sendable field structs and session mapping into separate files
- Replace distance-based proximity radius spot filter with region-based multiselect (US, Canada, Europe, Asia, etc.)
- Link hunter log upload services (QRZ, LoFi) to their settings views instead of showing hardcoded status

## [1.41.0] - 2026-02-19

### Added
- Add city, distance, and bearing to logger callsign lookup card (distance uses configured units, bearing shown with compass arrow)
- Apple Watch companion app with idle mode (solar conditions, spots, stats) and active session view (QSO count, activation progress ring, callsign display)
- WatchConnectivity for real-time session updates between iPhone and Watch
- Quick session start from Watch using last-used defaults
- Solar and spots data sharing to App Group for Watch consumption
- Landscape two-pane layout for logger: form on left, scrollable QSO list on right, compact single-line session header
- Landscape two-column dashboard layout: activity/conditions on left, favorites/equipment/services on right
- Auto-hide tab bar when logger has active session in landscape (reclaims ~49pt vertical space)
- Landscape-adaptive sheet detents: sheets expand in landscape to avoid clipping at unusable heights
- Compact single-line QSO rows in landscape (callsign + freq + band + mode + RST + grid + timestamp)
- Compact session rows in landscape (hide timeline, conditions, upload section)

### Fixed
- Fix crash on launch when PencilKit initializes on a background thread and triggers UserDefaults notification into @MainActor-isolated SettingsSyncService (switch to queue-based notification observers)
- Fix session photos saving the last photo multiple times when adding more than one photo at once (filename collision from timestamp-based naming)
- Fix slow orientation changes by locking LoggerContainerView size class to prevent full view hierarchy rebuild on iPhone Pro Max rotation
- Improve map view rotation performance: pre-compute geodesic paths at creation time instead of in view body, remove per-marker animation contexts, switch to flat elevation rendering, cache DateFormatter in filter overlay
- Fix duplicate WidgetSpot type from Watch app merge causing widget build failure (rename shared Codable type to SharedSpot)
- Fix Swift 6 concurrency errors in WatchConnectivity delegates (WatchSessionDelegate, PhoneSessionDelegate)

## [1.40.1] - 2026-02-19

### Added
- Add "Keep lookup info after logging" setting (default: on) to control whether callsign card persists after logging a QSO

### Changed
- Add inline friend search to Friends list — search bar is always visible, no extra navigation needed
- Hide clubs/groups feature from Activity tab (not ready yet)
- Replace separate "Add Friend" screen with integrated search in Friends list

## [1.40.0] - 2026-02-19

### Added
- Sync user settings across devices via iCloud Key-Value Store — identity, logger defaults, POTA settings, appearance, tab config, equipment lists, station profiles, activity log settings, keyboard config, and dashboard metrics automatically propagate between iPhone and iPad

### Changed
- Remove strikethrough from hunted spots in activity log — faded opacity only
- Show state abbreviation on activity log spots (from POTA location or HamDB lookup)
- Show duplicate QSO confirmation alert when tapping a worked spot in activity log
- Default "Hide Already Worked" spot filter to off

### Fixed
- Worked-before badges now update immediately after logging a QSO from a spot
- Add VoiceOver accessibility labels to state pills (full state name) and hide decorative separators

## [1.39.0] - 2026-02-18

### Added
- Add configurable rove QRT spot message in POTA Activation settings — mid-rove park transitions use the custom message (default "QRT moving to next park") while final session QRT remains "QRT"
- Report session completed activity to server when ending a logging session
- Full brag sheet cards in activity feed for completed sessions (map, timeline, stats, equipment)
- Lock screen circular widget now supports A-index and SFI metrics (configurable via "Lock Screen Metric" parameter)
- Add search to settings: type to filter all ~55 settings by title and keywords, tap to navigate directly to the containing view

### Fixed
- Fix QRZ only syncing last QSO per activation — QRZ INSERT processes one ADIF record per request, but Carrier Wave sent all QSOs in a single payload; now uploads one QSO per request with per-QSO success tracking, and a one-time forced full download repairs QSOs stuck from the batch upload bug

### Changed
- Restructure settings with progressive disclosure: top-level shows 5 category links (Appearance, Logger, POTA Activations, Sync Sources, Data & Tools) instead of ~48 inline rows
- Remove all icons from settings views for a cleaner, scannable layout
- Spots widget deduplicates by callsign, averaging SNR and WPM across multiple spots for the same station
- Spots widget band/mode filter pills collapse to "N bands" / "N modes" summary when more than 2 are selected
- Solar metric gauge circles now fill counterclockwise from the top

## [1.38.0] - 2026-02-17

### Added
- Add equipment usage stats card to dashboard showing top 3 favorites, QSO magnet, best combo, and gathering dust
- Equipment detail drilldown with sortable ranked list and category filtering
- Enrich WebSDR receiver selection with live SNR, antenna details, and band coverage from /status endpoint
- Add WebSDR favorites that sync across devices via iCloud
- Parse antenna descriptions showing type, bands, and directionality as badges
- Highlight band match during activations ("Good for 40m" badge)
- Add manual receiver entry for private KiwiSDRs (advanced mode in Settings)
- Show available WebSDR receivers in favorites settings with search and proximity sorting
- Add tap-to-expand detail sheet for receivers with full info and favorite toggle
- Add statistics section to session detail view (band/mode charts, distance/timing CDFs, RST, entities) gated on Professional Statistician Mode, matching POTA activation detail
- Add swipe-to-delete for QSOs in session detail view (both flat and rove-grouped)
- Add tap-to-expand on QSO rows in session detail to show all stored fields
- Add privacy manifest (PrivacyInfo.xcprivacy) for main app and widget targets declaring UserDefaults usage
- Add privacy policy link in Settings > About section
- Add community account deletion in Settings > Activities with server-side cascade delete
- Add export compliance declaration (ITSAppUsesNonExemptEncryption) to Info.plist
- Add app review notes document with ATS justification, background audio explanation, and demo instructions

### Fixed
- Fix rove session detail map showing only one park instead of the whole operation with all parks and route
- Fix rove session detail showing duplicate stops when same park appears multiple times in stored data
- Fix Live Activity not clearing when ending or deleting a paused session
- Fix rove upload prompt showing all QSOs against last park instead of per-park counts
- Fix callsign/command input field growing wider than screen with long text
- Fix Sessions tab only showing last park and its QSOs for rove sessions
- Fix brag sheet only including last park's QSOs for rove sessions
- Fix rove brag sheet showing parks in reverse date order instead of chronological visit order
- Split POTA sessions at UTC day boundary so each session covers one activation date (fixes duplicate park entries when session spans midnight UTC)
- Remove empty CFBundleURLTypes entry from Info.plist

### Changed
- Sync activity feed immediately on Activity tab appearance instead of waiting 60 seconds
- Add club sync to Activity tab refresh action

## [1.37.0] - 2026-02-17

### Changed
- Redesign Solar widget with circular arc gauges for K, A, and SFI (arc fill + color = propagation quality)
- Show all 4 band conditions in Solar widget as a 2x2 color-coded grid instead of single configured band
- Color-code propagation rating and band condition text in Solar widget for at-a-glance readability
- Fix band name wrapping in Solar widget by using shorter display labels (e.g. "30-20m" instead of "30m-20m")
- Show 5 spots instead of 4 in medium Spots widget to reduce empty space
- Increase minimum font size in Spots widget from 9pt to caption2 for readability and Dynamic Type scaling
- Move source label next to mode in Spots widget rows, eliminating the large gap between data columns
- Abbreviate source filter in Spots widget header ("All" instead of "POTA + RBN") to reduce truncation

### Added
- Add swipe-to-delete on QSOs in logger session log
- Add Live Activity for logging sessions: shows QSO count, frequency, mode, park reference, and last callsign on lock screen and Dynamic Island
- Live Activity updates in real time as QSOs are logged, frequency/mode changes, or session is paused/resumed
- Live Activity reconnects automatically after app relaunch during active session
- Add widget deep link navigation: tapping Spots widget opens Activity Log, other widgets navigate to Dashboard or Logger
- Add multi-select band and mode filters to Spots widget via long-press configuration (160m–2m, CW/SSB/FT8/FT4/Digital)
- Show "+N more" indicator on Spots widget when more spots are available than fit on screen
- Add iOS widgets: Solar Conditions, Stats & Streaks, Radio Spots (POTA + RBN), and Active Session
- Solar widget shows K-index, SFI, A-index with propagation rating (small + Lock Screen)
- Stats widget is configurable via long-press to show any streak or count metric (small + Lock Screen)
- Spots widget shows live POTA/RBN spots with configurable source filter; taps open Activity Log (medium + large)
- Active Session widget shows current logging session with QSO count, park ref, and elapsed time (small + medium + Lock Screen)
- Add App Group (`group.com.jsvana.FullDuplex`) for widget data sharing
- Add hourly solar conditions polling in background, filling in conditions history continuously without requiring an active session (toggle in Settings > POTA Activations)
- Add haptic feedback (success) when logging a QSO
- Add accessibility labels to filter button (Map), settings menu (CW Transcription), and refresh button (POTA Activations)
- Share sync debug log as text from Sync Debug view toolbar menu

### Changed
- Redesign Solar widget home screen view: K/A side-by-side with gauges, SFI and band side-by-side with 10-segment and 3-segment stoplight gauges, right-aligned values, no text coloring or condition labels
- Add configurable band selection to Solar widget (80m-40m, 30m-20m, 17m-15m, 12m-10m) with day/night propagation conditions from HamQSL
- Parse band-specific conditions from HamQSL XML `<calculatedconditions>` section
- Switch Solar widget from StaticConfiguration to AppIntentConfiguration for band selection
- Add per-metric descriptions to Solar widget (K: Quiet/Unsettled/Active/Storm, SFI: Poor/Low/Good/Very Good/Excellent, A: Quiet/Unsettled/Active/Storm/Severe)
- Fix Solar widget lock screen circular view readability with heavier rounded font weight
- Fix Solar widget lock screen rectangular view with K and A together, band conditions on line 3
- Add Solar widget inline (lock screen top) showing K value and band condition
- Fix Solar widget family dispatch to use @Environment(\.widgetFamily) instead of broken preview extension
- Redesign Spots widget with aligned table layout: fixed-width columns for callsign, frequency, mode, source, and age
- Reduce Spots widget refresh interval from 15 minutes to 5 minutes for more current data
- Show active band/mode filter badges in Spots widget header
- Add sync debug logging for QRZ uploads: HTTP response, ADIF size, PARTIAL result details (CAR-92)
- Log error when fetchQSOsNeedingUpload fails instead of silently returning nil (CAR-92)
- Log when QRZ upload batch is empty (no QSOs need upload) (CAR-92)

### Fixed
- Fix delete confirmation in QSO edit sheet to anchor near the delete button instead of screen center
- Respect Reduce Motion setting for cursor blink animation and sync spinner
- Ensure full tap area on activity grid cells via contentShape
- Show NavigationSplitView sidebar toggle button on Logger tab on iPad (CAR-91)
- Fix conditions card metric pills wrapping/overlapping on narrow displays

## [1.36.0] - 2026-02-16

### Added
- iPad two-pane layout with persistent spots sidebar showing POTA spots, RBN/My Spots, and P2P tabs (CAR-85)
- Worked-before indicator on POTA spots showing dupe, today, and previous badges (CAR-89)

### Changed
- Merge POTA and RBN spots into single unified list sorted by band with human spots first (CAR-90)
- Scale QSO row fonts for iPad: larger text and better space usage in logger, logs tab, and activity log (CAR-84)

### Fixed
- Fix POTA auto-spot posting on hunted station's frequency when hunting before setting run frequency (CAR-88)
- Fix QRZ info card inconsistently disappearing after logging — card now persists until next callsign is entered (CAR-87)
- Prevent sidebar spot taps from attempting to load data when no logging session is active (CAR-85)

## [1.35.0] - 2026-02-16

### Added
- POTA rove mode: activate multiple parks in a single session with "Next Stop" transitions, rove progress bar, per-stop QSO tracking, and automatic QRT/spot posting on park changes

### Changed
- Optimize rove mode vertical space: hide empty spot summary, remove hunting banner (freq capsule already shows "Set Freq"), merge rove header into pills row with inline "Next Stop" button, tighten rove header padding

### Fixed
- Fix duplicate detection during POTA roves incorrectly flagging callsigns worked at previous parks
- "Part of rove" badge on POTA activations that belong to a rove session
- GPS grid auto-update when transitioning to next rove stop
- Rove route display on MAP command showing numbered stop markers and dashed route line between parks

## [1.34.0] - 2026-02-16

### Added
- Add A-index display to conditions dashboard card and history chart
- Add real HF band conditions (day/night) from HamQSL to solar panel, replacing estimated values
- Store A-index and band conditions from HamQSL on sessions and activation metadata

### Fixed
- Fix PHONE/SSB mode mismatch causing duplicate QSOs: POTA imports as "PHONE" while QRZ imports as "SSB", producing different deduplication keys; now normalizes via `ModeEquivalence.canonicalName()` so voice QSOs merge correctly
- One-time repair merges existing PHONE/SSB duplicate pairs, preserving all sync status and service presence data
- Service presence pills now only show for configured services or services with actual sync data, reducing visual noise
- Fix service presence pill text overflow with `lineLimit(1)` and `fixedSize()`
- Fix activity log (hunter) QSOs incorrectly treated as POTA activations: add `isActivityLogQSO` flag to prevent park reference extraction, orphan activation display, and incorrect ADIF export with `MY_SIG=POTA`; one-time repair migrates existing data
- Fix AirDrop sharing of ADIF files renaming .adi to .txt by registering UTType export declaration for `org.adif.adi`
- Fix corrupted K-index data: one-time repair clears K-index=0 values from before the HamQSL XML whitespace parsing fix (Feb 14, 2026), preserving valid SFI and sunspot data
- Fix `hasSolarData` to check all three solar fields (K-index, SFI, sunspots) instead of only K-index, preventing data loss when K-index is cleared
- Average same-day solar/weather data points in conditions charts to reduce clutter from multiple sessions

## [1.33.4] - 2026-02-15

### Fixed
- Fix crash-on-launch in CommentParkRefRepairService: replace `(parkReference ?? "").isEmpty` with direct `== ""` comparison in SwiftData predicate to avoid CoreData NSPredicate translation assertion

## [1.33.3] - 2026-02-15

### Fixed
- Fix crash-on-launch in CommentParkRefRepairService: remove propertiesToFetch that omitted predicate-referenced isHidden field, causing CoreData assertion; add batched fetching with fetchLimit

## [1.33.2] - 2026-02-15

### Added
- Add one-time background repair to extract park references from ADIF comment fields on existing QSOs imported before the extraction logic was added
- Add active sessions list to logger tab: paused sessions appear with Continue/Finish actions when no session is active
- Starting a new session now pauses (instead of ending) the previous session, allowing it to be resumed later
- Add data repair for callsign whitespace: trims leading/trailing spaces and merges resulting duplicates
- Add data repair for QRZ isSubmitted state: promotes stuck records to isPresent

### Fixed
- Fix QRZ upload marking QSOs as isSubmitted instead of isPresent, leaving them invisible to reconciliation
- Fix logger saving callsigns with trailing whitespace, causing duplicate QSOs that fail deduplication
- Add defense-in-depth trimming to deduplication key and QSOSnapshot normalizedCallsign
- Clear isSubmitted flag in markPresent to prevent stale submitted state

## [1.33.1] - 2026-02-15

### Changed
- Redesign dashboard metrics settings with navigation-push pattern for clearer UX
- Add metric subtitles, selection haptic, and VoiceOver selected trait to metric picker
- Prevent selecting the same metric in both primary and secondary slots

## [1.33.0] - 2026-02-15

### Added
- Add swipe-to-delete on sessions list with confirmation dialog (hides QSOs, cleans up spots and photos)
- Add POTA QSO-level gap repair: during sync, compare local QSOs against POTA's per-activation remote data and flag missing QSOs for re-upload
- Add RIG logger command to edit equipment (radio, antenna, key, mic) during an active session
- Add tappable equipment capsule to logger session header row 2
- Add park detail sheet showing POTA stats, top activators/hunters leaderboard, and recent activations
- Park chips and park picker rows now open park detail sheet on tap/info button

### Fixed
- Extract park references from ADIF comment fields when MY_SIG_INFO is missing (affects QRZ sync, LoFi sync, and all service downloads)

### Changed
- Enlarge touch targets in park picker and park chips to meet HIG 44x44pt minimum
- Move session duration from row 2 capsule to row 1 (next to QSO count) to free horizontal space
- Merge frequency and band into a single capsule (e.g., "14.060 20m") instead of separate text + chip
- CHECKLIST logger command now passes the session's radio to CW Field Guide, pre-selecting radio-specific checklist items

## [1.32.3] - 2026-02-15

### Changed
- Bare search text in log search is now treated as callsign prefix search (uppercased, implicit `callsign:<text>*`) instead of multi-field contains
- Add info note to log search when using implicit callsign search

## [1.32.2] - 2026-02-15

### Added
- Persist RBN and POTA spots during active sessions and display them in session detail view with POTA spots highlighted and RBN spots collapsed by region
- Add CHECKLIST logger command to deep link to CW Field Guide outing checklists (aliases: CL)

## [1.32.1] - 2026-02-14

### Added
- Extract park references from ADIF comment field when MY_SIG_INFO is missing (WSJT-X compatibility)
- Add Club Log as an optional sync service — bidirectional ADIF sync with batch upload (putlogs.php), download (getadif.php), incremental date-based sync, and real-time single-QSO upload support
- Club Log settings view with email, app password, callsign, and API key configuration
- Club Log service row on dashboard with sync status, pending counts, and detail sheet
- Club Log integration in query language (filter QSOs by `source:clublog`)
- Add QSOs/hr rate to brag sheet stats row (always shown when rate available)
- Add Professional Statistician Mode toggle in POTA settings
- Statistician mode: charts on activation detail (band distribution, QSO rate over time, cumulative distance CDF, cumulative timing CDF)
- Statistician mode: two-column stats summary on activation detail (distance, timing, RST bucketed by R/S/T, entities)
- Statistician mode: brag sheet section with distance and timing box plots, peak rate badges, band/mode distributions, entity counts
- Statistician mode: modes used shown on brag sheet

### Changed
- Replace distance histogram chart with cumulative distribution (CDF) chart for readability
- Add cumulative timing CDF chart alongside QSO rate chart
- RST statistics now bucketed by R (readability), S (signal), T (tone) instead of averaging the whole number
- Clarify brag sheet badge labels: "best 15-min" for peak window, "dist. CV" for coefficient of variation

### Removed
- Remove DXCC from statistician views (unreliable data)

### Fixed
- Fix crash when opening map view — computed property in SwiftData `#Predicate` caused runtime assertion failure
- Fix K-index always showing as 0 — HamQSL XML returns values with leading whitespace that Swift's numeric initializers reject

## [1.32.0] - 2026-02-14

### Added
- Configurable dashboard metrics card — choose 1-2 metrics from streaks (On-Air, Activation, Hunter, CW, Phone, Digital) and counts (QSOs/activations/hunts per week/month/year, new DXCC)
- Hunter streak tracking — consecutive days working POTA activators
- Dashboard Metrics settings screen for metric selection
- Rename "Share Card" to "Brag Sheet" across all activation share actions
- Add equipment to brag sheet — antenna, key, mic, and extra equipment shown as badges when enabled
- Add "Include equipment on brag sheet" toggle in POTA settings (on by default)

### Fixed
- Hide sessions with zero QSOs from the Sessions list
- Fix build errors: static stored property in generic type, duplicate FlowLayout definition, ActivationShareRenderer instantiation
- Fix HAMRS incorrectly marked as supporting uploads, creating permanent phantom pending upload records that inflate sync counts
- Fix QRZ upload clearing needsUpload without confirmation, causing QSOs to get stuck in dead state (never uploaded, no recovery path)
- Add data repair steps to clean up existing bogus HAMRS upload flags and QRZ dead-state QSOs

## [1.31.0] - 2026-02-14

### Added
- Merge POTA Activations and Sessions into a single unified Sessions list — every session (POTA, SOTA, casual) now shows rich content including QSO timeline, upload status, conditions, and equipment badges
- Record solar/weather conditions at the start of every session type, not just POTA — conditions display on session cards when available
- Add multi-park (n-fer) support for POTA activations — park entry is now multi-select with removable chips, search picker supports adding multiple parks, and self-spots are posted to all parks simultaneously
- Add hunt-first session flow for POTA/SOTA — frequency is no longer required at session start, allowing activators to hunt first and set their run frequency later via BAND command or band picker
- Add BAND command to logger — opens band picker with live POTA/RBN spot data and recommended clear frequencies per band
- Add QSOs/hour rate to session detail and POTA activation detail views
- Add equipment (radio, antenna, key, mic) to map QSO callout popups
- Add swipe-to-delete on individual QSOs in POTA activation detail view with confirmation dialog
- Add expanded session metadata: antenna, CW key, microphone, attendees, photos, and extra equipment fields on logging sessions
- Add generic equipment picker with user-managed lists for antenna, key, and microphone
- Add unified session edit sheet replacing activation-only edit — works for all session types with equipment, photos, and notes editing
- Add photo attachment and viewing for sessions with full-screen pinch-to-zoom viewer
- Add equipment badges (antenna, key, mic) to POTA activation detail metadata row
- Add photo count badge to sessions list rows

### Fixed
- Fix hidden/deleted QSOs being uploaded during sync — `fetchQSOsNeedingUpload` now filters hidden QSOs, hiding a QSO clears its upload flags, POTA reconciliation skips hidden QSOs, and a data repair step cleans up pre-existing dirty state
- Fix social activity not appearing for live-logged QSOs — activity detection now triggers immediately when logging a QSO, not only during sync downloads
- Fix activity feed not auto-refreshing — feed now polls every 60 seconds while Activity tab is visible
- Fix third-party callsigns being sent to server for DX contact activities — workedCallsign is now only uploaded for worked-friend events where both parties are app users
- Fix unbounded QSO fetch in activity detection that could freeze UI for large datasets — capped at 10k most-recent QSOs
- Fix friend requests not appearing in Friends list — list now syncs from server on appear instead of only showing cached data

### Changed
- Remove "POTA Activations" segment from Logs tab — all activations now appear in the unified "Sessions" list
- Rename "Edit Metadata" to "Edit Info" in POTA activation detail toolbar menu
- Add imperial/metric unit system picker in Settings — affects distances, temperatures, wind speed, and watts-per-distance across all views
- Auto-populate grid square from GPS when station profile has "Use Current Location" enabled — works in profile setup, editing, and live activity log with location indicator icon
- Enhance park selector with GPS-based nearby parks, activation/QSO counts per park, and unified search by number or name
- Track SDR parameter changes (frequency/mode) during WebSDR recordings with timestamps and offsets, enabling accurate segment reconstruction for playback rendering
- Stitch WebSDR recordings across pause/resume and disconnect/reconnect — silence fills gaps to maintain accurate timeline, dormant state keeps recording alive for up to 30 minutes between connections
- Show station profile name and grid square dividers in Activity Log QSO lists — visual sections appear when station profile or grid changes between QSOs, stored per-QSO for historical accuracy

## [1.30.0] - 2026-02-13

### Added
- Add tap-to-edit and swipe-to-delete on QSO rows in Activity Log (Recent QSOs and Daily Summary) — tap opens QSOEditSheet, swipe left reveals Delete action, row height meets 44pt HIG minimum
- Add frequency and band pill display in Activity Log quick entry — typed frequencies (e.g., "W1AW 14.060") show as "14.060 MHz" and "20m" pills, and propagate to logged QSO
- Add band/mode indicator to Activity Log quick entry fields row — shows current band and mode so the user knows what the next QSO will be logged as
- Add number row keyboard accessory to Activity Log quick entry — shows digits 1-0, configurable symbols, and dismiss button above keyboard (shares settings with Logger)
- Add rich share card preview sheet with ShareLink (proper thumbnail in share sheet) and Save to Photos button
- Add sync report UI — structured per-service reports with visual funnel (fetched → validated → changes applied → uploaded), status badges, and reconciliation details; persisted across app launches via UserDefaults; populated by both normal sync and force re-download
- Add WebSDR tuning info display — show current frequency, mode, and filter bandwidth in WebSDR panel
- Add WebSDR browser link — open the connected KiwiSDR in Safari with current tuning settings
- Add WebSDR recording playback — play back recordings with seeking, speed control (0.5x-2x), and amplitude waveform visualization
- Add QSO-synced audio navigation — dynamically highlight the active QSO based on playback position with bidirectional sync (scrub highlights QSOs, tap QSO seeks audio)
- Add compact recording player in POTA activation detail — inline card with mini waveform that expands to full-screen player
- Add full-screen recording player — waveform scrubber with QSO markers, transport controls, speed picker, and scrollable QSO list with auto-scroll
- Add share clip feature — export time-range clips from recordings as M4A with adjustable range handles defaulting to active QSO window
- Add Sessions tab in Logs — browse all completed logging sessions grouped by month with recording indicators and navigation to player or session detail

### Fixed
- Fix Activity Log quick entry RST handling — single RST in quick entry (e.g., "W1AW 579") now applies to both sent and received instead of only received
- Fix Activity Log band/frequency not carrying over from spot logs — logging a spot now sets the frequency and mode for subsequent quick log entries
- Fix Activity Log quick entry not passing notes to QSO — parsed notes from multi-token input were silently dropped
- Fix POTA job matching showing jobs from unrelated activations on activation detail cards — nil-date jobs (from all-duplicate uploads) now match to the closest activation by submitted date instead of all activations for the same park
- Fix KiwiSDR redirect handling — follow server redirects during handshake (up to 3 hops) instead of showing an error; detect redirects during streaming to trigger immediate reconnect; cache effective host/port so reconnects go directly to the correct server
- Fix WebSDR CW tuning — apply CW pitch offset so the signal lands in the center of the audio passband instead of at 0 Hz (inaudible)
- Fix KiwiSDR false disconnect on `too_busy=0` — server sends `MSG too_busy=0` as an informational status (not busy), but string matching treated it as a disconnect causing 10-second reconnect cycles
- Fix WebSDR reconnect drops recording — keep recording timer running and write silence during reconnect gaps instead of pausing recorder
- Change CW filter passband from 200-1000 Hz to 300-800 Hz for tighter 500 Hz bandwidth
- Fix recording player amplitude waveform not displaying — use file's native audio format instead of mismatched custom format
- Fix recording player showing no QSOs when opened from Sessions tab — auto-load QSOs by session ID when none provided
- Add WebSDR session recording — record audio from a nearby KiwiSDR during logging sessions with WEBSDR command, auto-retune on frequency/mode changes, level meter, and lifecycle integration
- Add WebSDR live audio playback — hear the stream through speakers/headphones via jitter-buffered ring buffer with adaptive rate, mute toggle, and buffer health indicator
- Add WebSDR resilient reconnects — connection loss preserves the recording file, duration timer, and audio engine instead of resetting; exponential backoff with up to 5 retries
- Add persistent WebSDR recording badge — tappable mini badge in logger header shows duration when panel is closed, tap to reopen
- Add WebSDR recording file sharing — share button on active recording and in recordings list
- Add WebSDR Recordings settings screen — browse, share, and delete past recordings
- Add background audio mode — WebSDR recording and playback continue when app is backgrounded
- Add appearance mode picker in Settings (System/Light/Dark/Sunlight) to override system color scheme
- Add Sunlight appearance mode for outdoor visibility — forces light theme with boosted contrast for direct sunlight use
- Add tiered contact count badges (bronze/silver/gold at 10/25/50 QSOs) in log rows and logger card
- Extract LoFi client into CarrierWaveCore package for sharing between iOS app and CLI tool
- Add `lofi-cli` executable target for standalone LoFi download testing without iOS Simulator
- Add `LoFiCredentialStore` and `LoFiLogger` protocols to abstract app-specific dependencies
- Add visual condition gauges for POTA activations — compact solar gauge (3-segment red/yellow/green) and weather badge (icon + temperature) replace plain text labels
- Add tappable conditions detail sheet showing full solar metrics (K-index, SFI, sunspots) and weather details (temperature, wind, humidity)
- Add structured solar/weather fields to ActivationMetadata with one-time backfill from existing text data

### Fixed
- Fix WebSDR audio crash on device — render callback inherited @MainActor isolation, crashing on the audio I/O thread; extract as nonisolated static factory and mark AudioRingBuffer methods nonisolated
- Fix WebSDR buffer underrun — add 1-second pre-buffering phase before starting audio engine to absorb network jitter; increase ring buffer from 3s to 5s capacity
- Fix WebSDR audio silence — write audio frames to playback ring buffer before recorder file I/O, remove unnecessary actor hops and suspension points that starved the buffer
- Fix WebSDR directory fetch — correct URL from `/public/` to `/.public/`, rewrite parser to extract receiver data from HTML comments, add ATS exception for HTTP/WS connections
- Fix KiwiSDR connection — remove incorrect `/kiwi/` URL prefix, use seconds not milliseconds for timestamp, fix identity command (`SET ident_user=`), add `SET compression=1`, parse server error messages (auth failures, busy, down), use negotiated sample rate, and restore correct frequency/mode on reconnect
- Fix KiwiSDR binary frame handling — KiwiSDR sends MSG text as binary WebSocket frames; decode binary data as UTF-8 during handshake and in the receive loop to properly detect sample_rate and other server messages
- Fix POTA upload prompt sheet: buttons hidden below visible area on medium detent — pin buttons at bottom with scrollable content and allow expansion to large detent
- Fix POTA upload prompt falsely reporting "upload failed" when POTA returns empty adif_files on HTTP 200 (file queued for async processing, not rejected)
- Fix POTA upload prompt using wrong QSO marking method — use markSubmittedToPark (matches SyncService behavior) instead of markUploadedToPark
- Fix LoFi sync fetching every QSO twice (server ignores `deleted` param on QSO endpoint, causing 2x bandwidth)
- Fix two-fer park references lost during QSO merge — combine park references instead of "first wins" so both parks are preserved
- Add Step 4 (dedup key grouping) to CLI pipeline breakdown so QSO counts match the app

### Changed
- Display contact nickname (if available) instead of full name in logger session log and QSO log
- Show callsign notes emoji in QSO log rows
- Show total contact count in logger session log and QSO log rows
- Move LoFi models, client, and helpers from app to CarrierWaveCore package
- Replace `LoFiClient()` with `LoFiClient.appDefault()` at all call sites

## [1.29.0] - 2026-02-10

### Added
- Add dual-color activity grid on dashboard — green for activations, blue for activity log, diagonal split for days with both
- Add deep link to CW Field Guide radio manuals — book icon in radio picker and MANUAL command in logger open the matching manual

## [1.28.0] - 2026-02-10

### Added
- Add spot age filter — only spots ≤12 minutes old shown by default, configurable 5–30 min in Activity Log settings
- Add spot sort order — toggle between Recent (newest first) and Frequency (low to high)
- Add proximity filter — "Heard Nearby" toggle in filter sheet with configurable radius (100–2000 mi) in settings
- Wire up SpotFilters.apply() — spot list now applies source, band, mode, worked, age, and proximity filters
- Default spot filters: POTA source, 20m band, CW mode, Heard Nearby, and Hide Already Worked enabled out of the box
- Deduplicate spot list by callsign+band — combines POTA and RBN reports for same station into single row, preferring POTA source
- Add Activity Log feature for persistent hunter workflow — always-open daily QSO tracking without session start/stop (CAR-47, Phase 1)
- Add ActivityLog SwiftData model and ActivityLogManager service for log lifecycle and QSO creation
- Add StationProfile model with UserDefaults-backed storage for reusable station configurations
- Add Dashboard card showing activity log setup prompt or today's QSO stats
- Add main ActivityLogView with daily counter header, quick log section, and recent QSOs
- Add station profile picker and add/edit sheets for managing equipment profiles
- Add Activity Log settings section with profile management, upload service info, and daily goal
- Activity log QSOs upload to QRZ and LoFi only (never POTA — no operator park reference)
- Add mini tour for Activity Log (4 pages: overview, quick entry, daily tracking, uploads)
- Add hunter spot list showing POTA and RBN spots with worked-before badges (CAR-47, Phase 2)
- Add tap-to-log half-sheet pre-filled from spot data (callsign, frequency, mode, park)
- Add spot filtering by source (POTA/RBN), band, mode, and hide-worked toggle
- Add worked-before cache with dupe detection, today/historical band tracking
- Add hunter monitoring mode to SpotMonitoringService for all-spots polling
- Add daily summary view with band timeline visualization and day navigation (CAR-47, Phase 3)
- Add location change detection sheet with grid distance display and profile switching
- Add daily QSO goal tracking with alert notification on goal reached
- Add daily activity share card for sharing day's QSO stats (CAR-47, Phase 4)
- Add share button to daily summary view
- Add activity feed integration — activity log QSOs now trigger activity detection (new DXCC, new band, DX contacts, streaks)

### Fixed
- Add accessibility labels to all icon-only buttons across Activity Log views (VoiceOver compliance)
- Mark decorative images as accessibilityHidden (empty state icons, age dots)
- Increase touch targets to 44×44pt minimum on filter chips, RST fields, and icon buttons
- Use @ScaledMetric for fixed-width columns (time, frequency, RST) to scale with Dynamic Type
- Replace hardcoded .white with Color(.systemBackground) for dark mode adaptability (band timeline, DXCC badge)
- Use static DateFormatter instances instead of computed properties (DailySummaryView, RecentQSOsSection)
- Add haptic feedback on QSO logging actions (quick log, spot log)
- Wrap LocationChangeSheet in NavigationStack with title and dismiss button
- Add HIG compliance rules and expanded accessibility checklist to design language docs

## [1.27.2] - 2026-02-09

### Changed
- Move Log QSO button inline next to callsign input field, always visible regardless of keyboard state (CAR-59)
- Replace full-width Log QSO / Run Command buttons with compact LOG/RUN/SAVE button that stays fixed-width to prevent layout shifts
- Anchor End Session confirmation dialog to the END button instead of bottom of screen
- Move Delete Session sheet buttons above spacer so they remain visible when keyboard is open

### Fixed
- Fix callsign input field width shifting when clear button appears by always reserving space for it
- Fix command mode purple border causing layout width changes by using strokeBorder
- Fix End Session confirmation dialog hidden behind keyboard by dismissing keyboard first

## [1.27.1] - 2026-02-09

### Added
- Add QSO timeline bar to activation detail, activation list rows, and share cards showing when contacts occurred during an activation with band-colored ticks and collapsed gaps (1hr+) shown as zigzag breaks

## [1.27.0] - 2026-02-09

### Added
- Add radio (rig) selection to session start wizard with a growing user-managed list, saved as default, propagated to all QSOs, visible in QSO detail, and exported as MY_RIG in ADIF
- Add transmit power (watts) field to session start wizard with 1,500W US max validation, saved as default, and automatically applied to all QSOs logged in the session
- Add mode-aware frequency suggestions for all modes in session start wizard — FT8, FT4, RTTY, AM, and FM now show correct frequencies instead of defaulting to CW (CAR-56)
- Add live "Active Now" section in session start showing POTA spots filtered by mode and license class, with clear-frequency recommendations based on ARRL band plan usage zones
- Add band plan reference sheet accessible from session start frequency section, showing band segments, license requirements, and activity frequencies
- Add RTTY activity frequencies to band plan data
- Add VHF/UHF band support (6m, 2m, 70cm) in frequency suggestions for FM mode

### Changed
- Enhance activation share card with RST-based colored dots on map (green/yellow/red matching the activation map), distance stats (avg/max), power, watts/mile, and radio info
- Show radio/rig and power on activation detail view and activation map overlay
- Add radio/rig selector to activation metadata edit sheet, applied to all QSOs in the activation

### Fixed
- Fix LoTW first sync making 25+ unnecessary API requests by trying single request first, falling back to adaptive windowing only on rate limit (CAR-44)
- Fix bug report showing "Not configured" for QRZ, LoFi, LoTW, and HAMRS services

## [1.26.1] - 2026-02-09

### Changed
- Redesign POTA activation cards with navigation-based detail view replacing inline disclosure groups
- Add prominent upload button directly on activation cards (full-width, borderedProminent style)
- Move secondary actions (edit, map, export, share, reject) to context menu and detail view toolbar
- Add dedicated activation detail view showing park info, upload controls, POTA jobs, and QSO list

### Fixed
- Fix POTA job matching for uploads where API returns nil firstQSO (e.g., all-duplicate uploads) by fuzzy-matching on park + callsign
- Display actual upload error messages inline on activation cards instead of vague "tap for details" text

## [1.26.0] - 2026-02-08

### Added
- Auto-record solar and weather conditions when starting a POTA logging session, stored in activation metadata (CAR-55)
- Add QSO detail view — tap any QSO in the Logs tab to see all metadata, sync status, notes, and source info (CAR-53)
- Show activation WPM, solar conditions, and weather in map callouts when tapping pins with POTA activation data (CAR-54)
- Persist average CW speed (WPM) from RBN spots to activation metadata when ending a POTA session (CAR-54)
- One-time backfill of average WPM for existing sessions that have stored RBN spot data (CAR-54)
- Show average CW speed from RBN spots in spot comments sheet during POTA activations (CAR-51)
- Collapse consecutive RBN spots in spot comments list into expandable groups to keep human comments visible (CAR-52)
- Warn when ending a POTA session during maintenance window (2330-0400 UTC) that uploads are unavailable, and suggest uploading later from the POTA Activations tab (CAR-49)

### Changed
- iPad sidebar now respects tab visibility settings immediately without requiring a restart (CAR-39)
- Remove 4-tab limit on iPad — all tabs can be shown in the sidebar (CAR-39)
- iPad shows all tabs by default on first launch instead of hiding Logger and Activity (CAR-39)
- Replace "More" tab with dedicated Settings entry in iPad sidebar (CAR-39)
- Rename "Tab Bar" settings to "Sidebar" when running on iPad (CAR-39)

### Fixed
- Normalize POTA park references at all import and entry points — fixes malformed refs like "US1234" or bare numbers being stored instead of "US-1234" (CAR-50)
- Auto-uppercase QRZ Callbook username field since QRZ usernames are always callsigns (CAR-41)
- Suppress "operator nearby" frequency warning when the nearby spot is the station being worked (e.g., tapping a POTA spot to hunt)
- Fix activation type resetting to Casual when scrolling the session start sheet (CAR-46)
- Fix 10m band plan missing CW mode in phone segment (28.300-28.500 MHz) for Technician and General licenses (CAR-38)
- Support dot-separated frequency notation (e.g., 14.030.50) for sub-kHz precision entry (CAR-40)
- Fix screen going to sleep after pausing and resuming a logging session despite "Keep screen on" being enabled (CAR-43)
- Fix callsign field cursor jumping to end when inserting numbers at a mid-text position (CAR-42)
- Fix activity grid in landscape and iPad showing too few columns — now shows a full year of history to fill available width

## [1.25.4] - 2026-02-08

### Added
- Add bulk actions for POTA activations with multi-select (upload, reject, export)

### Fixed
- Fix POTA upload error "No valid operator or station_callsign" for QSOs imported from HAMRS with empty myCallsign — fall back to user's primary callsign and emit both STATION_CALLSIGN and OPERATOR fields
- Fix bulk reject build error from missing CarrierWaveCore import and private modelContext access

## [1.25.3] - 2026-02-07

### Fixed
- Fix POTA reconciliation treating duplicate jobs (status 7) as unmatched, causing infinite re-upload loops for already-accepted activations
- Fix POTA reconciliation resetting in-progress jobs (pending/processing) back to needsUpload, causing duplicate uploads while POTA is still processing — now waits up to 30 minutes before considering a job stale

### Changed
- Document canonical sync flow ordering and invariants in sync architecture docs

## [1.25.2] - 2026-02-07

### Fixed
- Fix POTA uploads silently rejected due to wrong location in upload request — use park's actual location from POTA parks cache instead of unreliable grid-to-state derivation
- Add warning log when operator grid square maps to a different state than the park's known location

## [1.25.1] - 2026-02-07

### Added
- Add "Worked Friend" activity event — detect and surface QSOs with accepted friends in the activity feed

### Fixed
- Fix POTA uploads silently failing — detect empty `adif_files` response as rejection instead of assuming success
- Fix POTA submitted QSOs getting stuck permanently when POTA silently drops the upload (no job created) — reconciliation now resets orphaned submitted QSOs back to pending
- Mark QSOs with invalid park references (e.g., bare "US") as rejected to stop infinite retry loops

## [1.25.0] - 2026-02-07

### Added
- Add friend request notifications: badge on Activity tab and Friends toolbar button showing pending incoming request count, plus a banner card in the Activity feed that links to the Friends list
- Add detailed logging throughout POTA upload flow — upload request/response at INFO level (HTTP status codes, response bodies, ADIF content, request URLs), per-park timing, content summaries (bands/modes/date range), and per-job status/QSO count breakdowns during reconciliation
- Add "Force Reupload" button to POTA activation rows when debug mode is enabled — resets all QSOs back to pending and immediately triggers the upload

### Fixed
- Fix friend requests not appearing by syncing friends from server on Activity tab load and refresh
- Fix invite link deep links not matching when URL uses `activities.carrierwave.app` subdomain

## [1.24.2] - 2026-02-07

### Added
- Add community features opt-in during onboarding — users can choose to register with the activities server for friend discovery, challenges, and activity feeds
- Add "Enable community features" toggle in Activities settings to control discoverability in friend search
- Auto-register with activities server during sync if opted in but token is missing
- Add one-time community features prompt for existing users on Activity tab

### Changed
- Rename Challenges* files and types to Activities* (ChallengesClient, ChallengesError, ChallengesSyncService, ChallengesSettingsView)

### Fixed
- Fix friend invite link sheet dismissing on error instead of showing error message inline

## [1.24.1] - 2026-02-07

### Fixed
- Reconcile POTA upload presence against job log during sync — if the DB says a QSO is uploaded to POTA but no completed upload job exists, reset it to needs-upload so it gets re-uploaded

## [1.24.0] - 2026-02-07

### Changed
- POTA uploads now show as "submitted" (blue clock icon) until accepted by POTA job log, instead of immediately showing as complete — refresh jobs to see accepted status or retry failed uploads
- Consolidate POTA activation row actions (Edit, Map, Export, Share, Reject) into a single ellipsis menu button
- Show park reference and name inside expanded activation rows instead of cramming into the label
- Auto-expand activation rows that have pending uploads

### Fixed
- Fix POTA upload button not responding to taps — move upload action inside disclosure content where button taps work reliably instead of in the DisclosureGroup label where SwiftUI swallows taps
- Fix completed POTA jobs not reconciling QSO upload status — now auto-reconciles on view load, not just on manual refresh
- Fix QSO status circles staying gray after POTA job completes — single-park activations now use park-aware presence checks consistently, matching how confirmUploadsFromJobs writes per-park records

## [1.23.0] - 2026-02-06

### Added
- Edit activation metadata after completion — title, park reference, and watts via edit button or swipe action on activation rows
- Display activation metadata (title, watts, weather, solar) in activation rows and share cards
- Show all-time previous QSO count for each callsign entered in the logger
- Suggest friends based on QSO history — callsigns with 3+ contacts who are Carrier Wave users appear in the Friends list with Add/Dismiss actions
- Add detailed POTA upload debug logging — auth state, token metadata, ADIF preview, request/response details, and response headers in sync debug log

### Fixed
- Fix activation duration counting gaps between sessions — now sums individual session durations instead of spanning first-to-last QSO across all sessions
- Fix POTA uploads silently succeeding without sending data for two-fer (multi-park) activations. Park reference matching now correctly handles comma-separated references like "US-1044, US-3791"
- Fix legacy POTA needsUpload flag not being cleared after per-park uploads complete, causing repeated upload attempts
- Fix 2-3 second UI hang when opening Activities tab (replaced @Query with bounded fetch)
- Fix duplicate activities appearing in feed (e.g., "Made first CW contact" shown twice) — add dedup on creation and one-time cleanup of existing duplicates
- Fix evaluateNewQSOs loading entire QSO table instead of using fetchLimit
- Fix "Invite Friend" failing to generate a link when tapped before view fully appeared

## [1.22.2] - 2026-02-06

### Added
- POTA Jobs tab in Sync Debug view — centralized view of all POTA upload jobs sorted by date

### Fixed
- LoFi import now returns all park references for two-fer activations instead of only the first park
- Malformed park references from upstream APIs are now sanitized on import (e.g., "US1849" → "US-1849", bare numbers like "3687" dropped)

## [1.22.1] - 2026-02-05

### Fixed
- POTA upload prompt not appearing when ending an activation (was checking a UserDefaults key that was never set instead of Keychain credentials)

## [1.22.0] - 2026-02-05

### Added
- Map stats: activation time span, QSO/hr rate, average/longest distance, watts per mile on both QSO map and POTA activation map
- **Force Re-download** button on service detail sheets - tap any service on the dashboard to access full re-download without needing debug mode

### Fixed
- Number row buttons in logger now insert at cursor position instead of always appending to end of callsign

## [1.21.0] - 2026-02-05

### Added
- **POTA Job Status Display** - View POTA upload job statuses directly in the Activations view
  - Jobs are automatically matched to activations by park, date, and callsign
  - Warning icon appears on activations with failed jobs
  - Expand any activation to see all matching POTA jobs with status badges
  - Tap a job to view full details including errors and warnings from POTA processing
- **Two-fer POTA Upload Support** - Activations with multiple park references (e.g., "US-1044, US-3791") now upload correctly
  - QSOs are automatically split and uploaded to each park separately
  - Per-park upload status tracking shows which parks succeeded or failed
  - Combined activation row in POTA Activations view with single upload button
  - Tappable error icon shows failed parks with error messages
- **Two-fer Duplicate Repair** - Detect and merge duplicate QSOs from multi-source imports
  - Automatically detects QSOs with partial/truncated park references alongside complete versions
  - Dashboard prompts to merge duplicates when detected
  - Merges preserve the complete park reference and combine service presence records
- **DXCC Repair** - Background task repairs missing DXCC entities from raw ADIF data during sync

### Fixed
- DXCC entity now populated correctly during QRZ import (was missing in import path)
- LoTW sync now properly handles HTTP 403/503 errors instead of silently failing

## [1.20.0] - 2026-02-04

### Added
- **Friend Profile View** - Tap any callsign in the activity feed to view their profile
  - Shows recent activity from that friend
  - Displays activity stats (total activities, activities this week)
  - Shows friendship start date for connected friends
- **Friend Invite Links** - Generate shareable links to invite friends
  - Access via Friends list menu (three dots) > "Invite Friend"
  - Share link via iOS share sheet or copy to clipboard
  - Recipients can tap the link to send you a friend request

## [1.19.3] - 2026-02-03

### Added
- LoTW sync now fetches QSOs for all configured callsigns (current + previous), ensuring complete stats and confirmation tracking across callsign changes

### Fixed
- DXCC entity now populated from QRZ sync (previously only came from LoTW confirmations)

## [1.19.2] - 2026-02-03

### Added
- Tap-to-edit callsigns in session log - tap any callsign to bring it back to the input field for quick correction without changing the QSO timestamp

### Fixed
- POTA spot timestamps now parse correctly, showing "spotted X ago" in nearby operator warnings
- Log QSO button now remains accessible when RBN/POTA/Solar/Weather/Map panels are open - scroll content adds padding to keep the button visible above panels

## [1.19.1] - 2026-02-03

### Added
- Action Required log level in Sync Debug with purple highlighting for issues needing user attention

### Fixed
- QSOs logged under previous callsigns no longer show as permanently pending
  - Upload counts now only include QSOs matching the current primary callsign
  - New fixer automatically clears needsUpload flags on QSOs that would never upload
  - Logs which callsigns had pending uploads cleared during sync
- QSOs with missing band/frequency are now skipped during upload with a warning
  - Sync log shows which QSOs need manual correction (edit in Logs to add band)
  - Prevents silent upload failures for incomplete QSOs
  - Uses new "ACTION" log level with purple highlighting to stand out

## [1.19.0] - 2026-02-03

### Added
- **Activation Share Cards** - Share POTA activation summaries as images
  - Swipe right on any activation in POTA Uploads to reveal Share action
  - Card shows map with QSO locations and geodesic arcs to your location
  - Displays park reference, name, date, and stats (QSOs, duration, bands, modes)
  - Branded Carrier Wave styling for social sharing
- **Sync Debug Logging** - Detailed logging for diagnosing permanently pending QSOs
  - Logs which QSOs are pending upload to QRZ and POTA with full details (callsign, timestamp, band, mode, park reference, myCallsign)
  - Shows ServicePresence state (isPresent, needsUpload, rejected) for each pending QSO
  - Logs upload results and any errors for each service
  - Warns about QSOs that need POTA upload but have no park reference
  - View logs in Settings > Sync Debug

### Changed
- CW decoder feature hidden and disabled from the app (code retained for future re-enablement)

### Fixed
- Metadata pseudo-modes (WEATHER, SOLAR, NOTE) are no longer marked for upload
  - These Ham2K PoLo activation metadata entries were incorrectly showing as "pending" for QRZ and POTA
  - Now filtered at the source: `ImportService` and `LoggingSessionManager` skip upload markers for metadata modes
  - Existing metadata QSOs with pending upload flags are automatically repaired during sync
- Reduced noisy LoFi sync logs when account has cutoff date restriction
  - "QSO MISMATCH" warnings now only appear when there's no cutoff date (indicating a real issue)
  - Per-operation mismatch warnings removed entirely (they were expected behavior with cutoff dates)
- POTA no longer shows "Not configured" when session token expires
  - Now uses stored credentials to determine configuration status
  - Auto-reauthenticates with saved credentials when token expires during sync
  - Dashboard, sync, and upload all work seamlessly after token expiry
- LoTW sync no longer triggers "Page Request Limit!" (503) errors
  - Increased delay between requests from 0.5s to 3s to respect LoTW rate limits

## [1.18.0] - 2026-02-02

### Fixed
- Log search now searches all QSOs instead of only the most recent 1,000
  - Field-specific queries like `band:6m` now use database predicates for efficient full-table search
  - Fixed case mismatch bug where band queries failed (bands stored lowercase, query used uppercase)
- LoFi sync progress bar now displays during parallel service downloads
- Fixed POTA presence repair service crash due to SwiftData predicate not supporting enum values
- Dashboard no longer freezes UI when loading statistics for large QSO databases
  - Statistics computation now runs entirely on a background thread
  - Progress bar shows loading progress under Activity card
  - UI remains responsive during computation
- Sync processing no longer freezes UI at the end of QSO loading
  - QSO deduplication and creation now runs on a background thread
  - UI stays responsive during the "Processing" phase of sync
- LoFi sync no longer freezes UI during operation downloads
  - Parallel downloads with adaptive concurrency (2-8 concurrent requests)
  - Automatic backoff and concurrency reduction on errors
  - UI remains responsive during large syncs
- QSO conversion after download now yields periodically
  - Prevents UI freeze when processing large batches of downloaded QSOs
- Processing phase now shows progress bar instead of indefinite spinner
  - Displays current phase (Grouping, Loading, Processing, Saving)

### Added
- Dynamic sync progress indicator shows QSO count as services complete
- LoFi sync shows progress bar with percentage based on total QSOs
- **Flexible frequency input** - Enter frequencies as kHz or MHz with optional unit suffixes
  - Type "14060" or "14060 kHz" for kHz input (auto-converted to MHz)
  - Type "14.060" or "14.060 MHz" for MHz input
  - Units are case-insensitive ("khz", "KHz", "kHz" all work)
- RBN spots map shows spotter locations via HamDB grid lookup with arcs to target station
- Spotter circles sized by signal strength (SNR)
- **Background Spot Monitoring** - Automatic RBN/POTA spot monitoring during logging sessions
  - Spots polled every 45 seconds while session is active
  - Compact summary banner shows spot count, region breakdown (NE, EU, etc.), and distance range
  - Tap to expand and see individual spots with SNR, distance, and time ago
  - POTA spots included for POTA activations only
  - Distance shown in miles or kilometers (user setting in Logger settings)
- Spot age color coding: green (<2m), blue (2-10m), orange (10-30m), gray (>30m)
- "SELF" badge on spots where the activator matches your callsign
- Auto-attach POTA spot comments to matching QSOs as notes
- QRT spot posted automatically when ending POTA session (if session was spotted)
- Setting to enable/disable QRT spotting (Settings → POTA Activations)
- **P2P command** - Find park-to-park opportunities during POTA activations
  - Type `P2P` in logger to discover other POTA activators heard by nearby RBN skimmers
  - Cross-references POTA spots with RBN data from skimmers within 500km of your grid
  - Shows SNR, frequency, park info, and age for each opportunity
  - Tap to auto-fill callsign, frequency, and P2P notes in logger

### Changed
- RBN spots now limited to last 10 minutes (was 6 hours)

### Fixed
- Fix LoFi sync failing when operations are missing `updatedAtMillis` field
- Fix Dashboard stats flashing during recomputation after sync
- Fix UI freeze when service detail sheet is open during stats recomputation
- Fix callsign suffix detection treating W1WC/CW as unconfigured alternate callsign
- Fix crash when deleting QSOs from Logs tab due to array index invalidation during SwiftUI list update
- Fix RBN spots not appearing in spot menu due to incorrect API response field mapping

## [1.17.0] - 2026-02-01

### Added
- **Quick Entry Mode** - Type complete QSOs in a single line for rapid logging
  - Type "AJ7CM 579 WA US-0189" to auto-fill callsign, RST, state, and park reference
  - Supports RST (2-3 digit), grid square (4-6 char), state/province codes, POTA park references
  - Color-coded token preview shows what each field will be populated with
  - Single RST applies to received; two consecutive RSTs become sent/received
  - Unrecognized tokens become QSO notes
- **Park Search and Nearby** - Enhanced park entry with name search and nearby parks
  - Search parks by name with full-text search picker
  - See nearby parks based on your grid square location
  - Park number shorthand: type "1234" to auto-expand to "US-1234"
- **State Entry Field** - Manual state entry/override in QSO logger
  - Appears in More Fields section (can be set to always visible)
  - Overrides QRZ lookup state when manually entered
- **Logger Layout Improvements** - Condensed QSO entry form
  - Removed magnifying glass icon from callsign input (only shows command icon when applicable)
  - Default fields: State, RST Sent, RST Received on single row
  - Chevron button expands to show Grid, Park, Operator, Notes
  - All text fields use consistent height and font size
- **POTA Spots Panel** - Dedicated view for active POTA activator spots
  - Filter by band and mode (defaults to session's current band/mode)
  - Grouped by band with section headers
  - Tap spot to tune to frequency
  - Access via `POTA` command in logger
- **Operator Field QRZ Hint** - Operator field now shows QRZ name as placeholder hint and logs it automatically if not overridden
- **Logs Tab Tour** - Added intro tour for the Logs tab explaining the query language
  - Overview of simple callsign search and wildcards
  - Field filter syntax (band, mode, state, park, grid)
  - Date filter examples (after:7d, date:today, before:)
  - Status filters (confirmed, synced, pending)
  - Combining filters with AND/OR/NOT
- **Log Search Query Language** - Powerful search for QSO logs with field-specific filters
  - Basic search: type callsigns, park references, or SOTA refs directly
  - Field filters: `band:20m`, `mode:CW`, `state:CA`, `park:K-*`, `grid:FN31`
  - Date filters: `date:today`, `after:7d`, `after:30d`, `date:2024-01`
  - Status filters: `confirmed:lotw`, `synced:pota`, `pending:yes`
  - Boolean logic: implicit AND, `|` for OR, `-` for NOT
  - Performance warnings for slow queries with suggestions to add filters
  - Quick filters menu for common searches
  - Help sheet with syntax reference

### Changed
- **QSO Deletion Confirmation** - Deleting a QSO in the logger now shows a confirmation dialog

### Fixed
- **QSO Deletion in Logger** - Fixed deleted QSOs not disappearing from session log until view refresh
  - QSO list now updates immediately when a QSO is deleted from the edit sheet
- **Quick Entry Notes Display** - Multi-word notes now display as a single combined badge instead of separate badges per word
- **Quick Entry Button Logging** - Fixed Log QSO button logging entire input string instead of parsed callsign in quick entry mode
- **Quick Entry Typing Crash** - Fixed crash when typing in quick entry mode caused by unstable SwiftUI identifiers
  - ParsedToken now uses position-based IDs instead of random UUIDs
  - Prevents view hierarchy rebuild during active text input
- **Sync Callsign Filtering** - QSOs from previous callsigns no longer appear in sync queues
  - Import now only creates upload markers for QSOs matching primary callsign
  - Sync fetch adds defense-in-depth filtering for legacy data
  - Prevents failed uploads to QRZ/POTA when user has changed callsigns

## [1.16.2] - 2026-02-01

### Fixed
- **Logger Text Input Lag** - Fixed multi-second input lag when typing in logger callsign field for users with large databases
  - Removed unbounded @Query from SessionMapPanelView (now uses passed session QSOs)
  - Removed unbounded @Query from HiddenQSOsSheet (now fetches by session ID)
  - Removed dead keyboard height tracking that triggered unnecessary re-renders
- **App-Wide Full Table Scan Elimination** - Replaced all unbounded @Query usages with paginated background fetching
  - DashboardView: stats and service counts now compute in background
  - QSOMapView: uses pagination with "Show All" option
  - LogsListView: uses "Load More" pagination
  - POTAActivationsView: loads park QSOs in batches
  - CallsignAliasesSettingsView: computes QSO counts in background
  - ChallengeDetailHelperViews: QualifyingQSOsView uses limited fetch
  - AllHiddenQSOsView: uses "Load More" pagination
- **Dashboard Build Error** - Fixed reference to non-existent property in sync time observer

## [1.16.1] - 2026-01-31

### Added
- **Persistent Callsign Notes Cache** - Polo notes now load instantly on app launch from disk cache, with background refresh

### Fixed
- **Session Delete Crash** - Fixed crash when deleting a logging session by properly ending the session before deletion
- **QRZ Name Display** - Now shows QRZ nickname instead of full formal name when available
- **False Callsign Detection** - Placeholder strings like "EVENT" are no longer incorrectly detected as unconfigured callsigns

## [1.16.0] - 2026-01-31

### Added
- **Hidden QSOs Management** - View and restore hidden (deleted) QSOs in Settings → Developer → Hidden QSOs
  - See all hidden QSOs across the app
  - Restore individual QSOs or all at once
  - Option to permanently delete hidden QSOs
- **Sub-kHz Frequency Precision** - Logger now supports entering and displaying frequencies with sub-kHz precision (e.g., 14.03050 MHz)
- **Auto-Focus Callsign Field** - Callsign field is automatically focused after logging a QSO for rapid contest-style entry
- **Background QSO Enrichment** - Grid, name, and other callsign data are now saved to QSOs even when logged before lookup completes

### Changed
- **Delete Session Confirmation** - Session deletion now requires typing "delete" to confirm, preventing accidental data loss
- **Onboarding Skip Button** - Button now shows "Next" instead of "Skip" when services have been connected, clarifying that connections are saved
- **iPad Sidebar Shows All Tabs** - iPad now shows all tabs in the sidebar by default (no 4-tab limit)
- **Technician Band Warning** - Clearer warning message for bands where Technicians have no privileges at all (e.g., "Technicians cannot operate in any mode within the 20m band")
- **RST Fields** - RST fields now start empty with placeholder hints (599/59) instead of pre-filled values
- **Removed Quick Log Mode** - Fast logging is now the default and only mode; setting removed from preferences

### Fixed
- **Settings Crash on Launch** - Fixed crash when navigating to service settings (QRZ, POTA, LoFi, etc.) due to missing SyncService environment object
- **Logger Submit Crash** - Fixed crash when pressing Return in logger callsign field while keyboard is dismissing
- **Technician CW Privileges** - Fixed incorrect warnings for Technicians operating CW on 80m (3.525-3.600), 40m (7.025-7.125), and 15m (21.025-21.200) bands
- **iPad Tab Settings** - Tab bar setting changes now take effect immediately on iPad without requiring app restart
- **Logger Submit Lag** - QSO logging is now instant with no visible delay
  - Replaced full-database @Query with session-scoped fetch
  - Cached service configuration to avoid Keychain reads per-QSO
  - Prevented redundant callsign lookups when QSO list re-renders
  - Disabled animations during form reset for immediate feedback

## [1.15.3] - 2026-01-31

### Fixed
- **Settings Crash on Launch** - Fixed crash when navigating to Settings before SyncService initialized
- **QSO Statistics Performance** - Major performance improvements for users with 15k+ QSOs
  - Refactored QSOStatistics to a class with cached computations (realQSOs, activation groups, category items, streaks)
  - Dashboard now computes stats asynchronously off the main thread
  - Cached activation grouping eliminates duplicate O(n) iterations for successful/attempted activations
  - Static DateFormatter in park grouping eliminates repeated allocation
  - FavoritesCard now defers item computation until navigation
  - LogsListView caches filtered QSOs and available bands/modes
  - QSOMapView caches filter options and stats (uniqueStates, uniqueDXCCEntities)
  - StatDetailView caches sorted items instead of resorting on every render

## [1.15.2] - 2026-01-31

### Fixed
- **Save as Defaults Button** - Now shows visual checkmark confirmation when tapped
- **Skip Wizard Setting** - "Skip wizard next time" now works correctly, auto-starting sessions with saved defaults
- **Save Defaults Completeness** - Activation type and park reference are now saved as defaults

## [1.15.1] - 2026-01-31

### Fixed
- **Tab Switching Performance** - Reduced lag when switching between tabs
  - Added lazy loading for Dashboard, Map, and Activity tabs (content deferred until visible)
  - Cached QSOStatistics in Dashboard to avoid recomputing on every render
  - Cached map annotations and arcs to avoid expensive coordinate conversions on every render
- **Logger Text Field Performance** - Fixed significant lag when typing callsigns
  - Cached DateFormatter instead of creating new instance on every render
  - Cached POTA duplicate status to avoid filtering all QSOs on every keystroke

## [1.15.0] - 2026-01-31

### Added
- **Tab Bar Configuration** - Customize which tabs appear and their order
  - Settings → Navigation → Tab Bar
  - All tabs (Dashboard, Logger, Logs, CW, Map, Activity) can be shown/hidden
  - Drag to reorder tabs in the tab bar
  - Hidden tabs appear in the More menu
  - Map and Activity start hidden by default, accessible from More
- **NOTE Command** - Add timestamped notes to the session log
  - Type `NOTE <text>` in logger input (e.g., `NOTE Band is noisy`)
  - Notes appear in the Session Log interleaved with QSOs
  - Notes are stored with UTC timestamp
- **Configurable Always-Visible Fields** - Toggle which QSO fields stay visible
  - Settings → Logger → Always visible fields
  - Options: Notes, Their Grid, Their Park, Operator
  - Configured fields appear without tapping "More"
  - Preferences persist across sessions
- **Delete Session** - Remove unwanted sessions before sync
  - Long-press or tap END button to access menu
  - "Delete Session" hides all QSOs and removes the session
  - Hidden QSOs won't sync to external services
- **Callsign Prefix/Suffix Support** - Construct callsigns for portable operations
  - Add country prefix when operating abroad (e.g., I/W6JSV)
  - Standard suffixes: /P (Portable), /M (Mobile), /MM (Maritime), /AM (Aeronautical)
  - Custom suffix option for regional indicators or other uses
  - Full callsign displayed prominently with color-coded breakdown

### Changed
- **Bare Mode Switching** - Enter mode name directly (CW, SSB, FT8, etc.) instead of requiring "MODE CW"
- **QSY Spot Confirmation** - Frequency and mode changes during POTA activations now prompt to post a QSY spot instead of auto-posting
- **Auto Mode Detection** - Changing frequency automatically switches to the appropriate mode for that segment (CW for CW/DATA segments, SSB for phone segments)
  - New setting "Auto-switch mode for frequency" to enable/disable this behavior

### Fixed
- **POTA Duplicate Blocking** - Same band/date duplicates are now blocked, not just warned
  - Log button is disabled when entering a duplicate callsign on the same band
  - Duplicate warning banner still shows to explain why logging is blocked
- **Hidden QSOs Excluded from All Views** - Hidden QSOs no longer appear in:
  - Dashboard statistics (total QSOs, QSLs, entities, grids, bands, parks, streaks)
  - Map view
  - POTA Activations view
  - Challenge progress
  - Callsign alias detection
- **License Class Persisted** - QSOs now save the contacted station's license class from QRZ lookup
- **Callsign Notes Ordering** - Emojis and source names from Polo notes now display in consistent alphabetical order by source title
- **Activity Grid Clipping on iPad** - Calendar activity view no longer cut off in landscape with navigation menu hidden
- **Callsign Lookup Error Feedback** - Logger now shows why callsign lookups fail
  - Displays actionable error when QRZ API key is missing
  - Shows authentication errors with recovery suggestions
  - Network errors displayed with helpful messages
  - Previously failed silently with no indication
- **QRZ Callbook Login Restored** - Re-added QRZ Callbook login in Settings → External Data
  - Uses proper username/password authentication (separate from Logbook API key)
  - Requires QRZ XML Logbook Data subscription for callsign lookups

### Removed
- **Feature Selection in Onboarding** - Removed now-redundant step for enabling/disabling Logger and CW Decoder
  - Tab visibility is now configured via Settings → Navigation → Tab Bar

## [1.14.0] - 2026-01-30

### Added
- **QSY Auto-Spotting** - Automatically post QSY spot to POTA when frequency changes during active POTA session
- **HIDDEN Command** - View and restore deleted QSOs from current session
  - Type `HIDDEN` or `DELETED` in logger input to show deleted QSOs
  - Restore button to un-delete individual QSOs

### Changed
- **Cleaner Logger UI** - Removed navigation bar title and top bar Start Session button

### Fixed
- **iPad Settings Navigation** - Changing sidebar tab now properly exits Settings submenus
- **QSO Count Accuracy** - Session QSO count now excludes deleted QSOs
- **Logs List Filter** - Hidden QSOs no longer appear in the Logs tab

### Added
- **Configurable Callsign Notes Files** - Add custom Polo-style notes files in Settings
  - Configure title and URL for each source
  - Sources fetched and cached, refreshed daily
  - Enable/disable individual sources
  - View entry count and last fetch status
- **Merged Callsign Notes Display** - When callsign appears in multiple notes sources
  - All emojis from matching sources shown together
  - Last source's note text used for display
  - Tracks which sources matched for reference
- **Notes Display Mode Toggle** - Choose how callsign notes are displayed
  - Emoji mode: Shows combined emoji from all matching sources
  - Source names mode: Shows source titles as chips
- **MAP Command** - View session QSOs on a map
  - Type `MAP` in the logger input to show session map panel
  - Displays QSO locations with geodesic paths from your location
  - Swipe-to-dismiss panel like RBN/Solar/Weather
- **Editable Session Title** - Tap the session title to customize it
  - Custom title persists across app restarts
  - Clear custom title to revert to default (callsign + activation type)
- **Navigate to Logs on Session End** - Automatically switch to Logs tab when ending a session with QSOs
- **RBN/POTA Spot Lookup** - View combined spots from RBN and POTA
  - `RBN` command shows your spots from both RBN and POTA
  - `RBN <callsign>` command to look up any callsign's spots
  - Unified spot display with source badges (RBN/POTA)
  - Mini-map view for RBN spotter locations
- **POTA Spot Comments** - Real-time hunter feedback during activations
  - Background polling for spot comments during active POTA sessions
  - Spot comments button in session header with new comment count badge
  - Comments sheet to view all hunter feedback
- **POTA Auto-Spotting** - Automatic self-spotting during POTA activations
  - Toggle in Logger Settings to enable auto-spotting every 10 minutes
  - Automatically posts initial spot when starting a POTA session
  - Timer pauses when session is paused and resumes with the session
- **User Onboarding Flow** - Profile setup after intro tour
  - Enter callsign and automatically fetch profile from HamDB.org
  - Displays name, QTH, grid square, license class, and expiration date
  - Pre-fills service credentials with callsign (username shown grayed out, just enter password)
  - Connect QRZ, LoTW, and POTA during onboarding
  - Profile stored securely and used throughout the app
- **About Me** - New profile section in Settings
  - View and edit your profile information
  - Refresh profile data from HamDB
  - Shows callsign, name, location, grid, and license class
- HamDB license class lookup in Logger Settings
  - Automatically look up license class from HamDB.org by tapping search icon
  - Works with US amateur radio callsigns (no authentication required)
  - Supports Extra, General, Technician, Advanced (mapped to Extra), and Novice (mapped to Technician)
- LoFi sync test script (`scripts/lofi-sync-test.swift`) for local testing

### Changed
- **Improved RST Labels** - Changed from "RST/S" and "RST/R" to "Sent" and "Rcvd" for clarity
- **RST Defaults by Mode** - RST defaults to 599 for CW/digital modes, 59 for phone modes
  - Automatically updates when changing modes during a session
  - Resets appropriately after logging each QSO
- **End Session Button** - Replaced 3-dot menu with a dedicated "End Session" button
  - Shows red "End Session" when session is active
  - Shows green "Start Session" when no session
  - Navigation title hidden during active sessions to save space
- Onboarding profile setup now skipped if callsign is already configured
- Add "Later" button to onboarding flow to defer profile setup

### Fixed
- Fix crash on iOS 26 when checking for existing profile during onboarding (actor isolation violation)
- LoFi sync pagination now fetches all operations (was stopping after first page of 50)
  - Server returns `next_updated_at_millis` when using `synced_since_millis` pagination
- LoFi QSOs with missing `startAtMillis` field no longer crash sync (field is now optional)
- **Logger Field Testing Fixes** - Multiple improvements from POTA activation feedback
  - Screen timeout prevention during active logging sessions (new "Keep screen on" setting, enabled by default)
  - Quick Log Mode setting to disable animations for faster pileup logging
  - UTC time display consistency - QSO list now shows UTC times with "Z" suffix
  - QRZ callsign lookup now works - implemented QRZ XML callbook API integration
  - Compact callsign info bar appears above keyboard when typing
  - SPOT command now accepts comments (e.g., `SPOT QRT`, `SPOT QSY 14.062`)
  - Map now shows activation QSOs - grid from callsign lookup is saved to QSO
  - State, country, and QTH from callsign lookup are now saved to logged QSOs

## [1.13.1] - 2026-01-29

### Fixed
- LoFi sync debug logging now appears in in-app sync logs and bug reports (was only going to system console)

## [1.13.0] - 2026-01-29

### Added
- **Under Construction Banner** - Dismissible warning for features still in development
  - Shows on Logger and CW Decoder tabs
  - Can be dismissed per-session or permanently hidden
- **Keyboard Number Row** - Quick frequency entry in Logger
  - Number row (0-9 and decimal) appears above keyboard when entering callsigns
  - Keyboard dismiss button to hide keyboard
- **Enhanced LoFi Sync Debugging** - Comprehensive logging for diagnosing sync issues
  - Logs account cutoff_date from registration response (explains limited data access)
  - Logs operation and QSO count mismatches with expected vs actual totals
  - Logs date ranges of operations and QSOs fetched
  - Logs pagination details (records_left, synced_until, synced_since)
  - Logs per-operation QSO count mismatches with POTA reference and date info
  - Warning when 0 QSOs returned for operations that should have data
  - Bug reports now include LoFi-specific details (linked status, callsign, last sync timestamp)
- **QSO Logger Tab** - Streamlined logging for activations and casual operating
  - Session-based logging with configurable wizard (mode, frequency, activation type)
  - Soft delete pattern - QSOs are hidden, never truly deleted (WAL durability)
  - Command input: type frequency (14.060), MODE, SPOT, RBN, SOLAR, WEATHER in callsign field
  - Callsign lookup integration (Polo notes + QRZ) with info card display
  - RST fields with expandable "More" section for notes, their park, operator
  - Recent QSOs list filtered by current session
- **RBN Integration** - Real-time Reverse Beacon Network spots
  - RBN panel showing your spots with signal strength and timing
  - Mini-map view showing spotter locations
  - Frequency activity monitoring (±2kHz) with QRM assessment
- **Solar & Weather Conditions** - NOAA data integration
  - Solar panel showing K-index, SFI, propagation forecast
  - HF band outlook based on current conditions
  - Weather panel from NOAA with outdoor/antenna/equipment advisories
- **Band Plan Validation** - License class privilege checking
  - Warning banner when operating outside license privileges
  - Technician/General/Extra class support
  - Mode validation (CW vs SSB segments)
- **POTA Self-Spotting** - Post spots directly from the logger
  - Integrates with existing POTA authentication
  - One-command spotting during activations
- **Toast Notifications** - Feedback for logger actions
  - QSO logged, spot posted, command executed confirmations
  - Friend spotted alerts when friends appear on RBN
- **CW Adaptive Frequency Detection** - Automatically detects CW tone frequency within a configurable range
  - Filter bank of Goertzel filters scans 400-900 Hz (default) with 50 Hz spacing
  - Locks onto detected frequency after confirmation, stays locked during gaps between elements
  - Three range presets: Wide (400-900 Hz), Normal (500-800 Hz), Narrow (550-700 Hz)
  - Toggle between adaptive and fixed frequency modes in settings menu
  - Detected frequency displayed in UI with auto-detect indicator
- **CW Chat Transcription** - View decoded CW as a conversation between stations
  - Chat/Raw toggle to switch between conversation bubbles and raw transcript
  - Turn detection using frequency changes and prosigns (DE, K, KN, BK)
  - Messages grouped by speaker with callsign attribution
  - Left/right aligned bubbles for other station vs. you
- **Enhanced CW Highlighting** - More intelligent text pattern detection
  - Grid squares highlighted (e.g., EM74)
  - Power levels highlighted (e.g., 100W)
  - Operator names highlighted after NAME/OP keywords
  - Signal reports highlighted with "UR" prefix context
- **Callsign Lookup** - Automatic callsign information from multiple sources
  - Polo notes lists checked first (local, fast, offline)
  - Name and emoji displayed in chat bubbles when available
  - Two-tier lookup architecture ready for QRZ XML API

## [1.12.0] - 2026-01-28

### Added
- **iPad Support** - Full iPad-optimized layouts following Apple HIG
  - Sidebar navigation on iPad (NavigationSplitView) instead of tab bar
  - Activity view uses side-by-side layout (challenges + feed columns)
  - Dashboard stats grid shows all 6 stats in one row on iPad
  - Activity grid dynamically shows 26-52 weeks based on screen width
  - iPhone retains existing TabView navigation (unchanged)

## [1.11.1] - 2026-01-28

### Fixed
- Crash during sync when evaluating challenge progress (SwiftData predicate used computed property instead of stored property)

## [1.11.0] - 2026-01-28

### Added
- **Activity tab** (renamed from Challenges)
  - Activity feed showing friend, club, and personal activities
  - Filter bar to show All, Friends only, or Clubs only
  - Activity detection for notable events (new DXCC, bands, modes, DX contacts, streaks)
  - Automatic activity reporting to server during sync
- **Friends**
  - Friends list showing accepted friends and pending requests
  - Friend search by callsign
  - Send, accept, and reject friend requests
- **Clubs**
  - Clubs list showing memberships (via Polo notes lists)
  - Club detail view with member list
- **Adaptive sync for rate limiting**
  - LoTW: Adaptive date windowing automatically shrinks time windows when hitting rate limits
  - POTA: Adaptive batch processing adjusts batch size on timeouts
  - Resumable downloads with checkpoints survive app restarts
- **Tour updates**
  - Activity tab added to intro tour
  - Expanded social mini-tour explaining friends and clubs
- "Ready to Upload" section in POTA Activations view
  - Pending activations pinned to top, sorted by date descending
  - Park reference shown in each row for easy identification

### Fixed
- POTA tour text changed from "AWS Cognito" to "External Logins (Google, Apple, etc.)" for clarity
- Map confirmed filter now includes QSOs confirmed by either QRZ or LoTW (union)
- Crash after device sleep when evaluating challenge progress
- Sync pagination handling improved

## [1.10.0] - 2026-01-28

### Added
- QSO Map view improvements:
  - States and DXCC counts in stats overlay
  - "Show Individual QSOs" toggle for small dot markers per QSO
  - Always-visible active filters display (dates, band, mode, park, confirmed)
  - Geodesic curve paths to contacted stations (renamed from "Show Arcs")
  - Performance limit (500 QSOs) with toggle to show all
- Streak statistics improvements:
  - POTA section showing valid/attempted activation counts
  - Best streak date ranges now include year
- Intro tour updates:
  - New Statistics step highlighting streaks and activity tracking
  - New Map step highlighting geodesic paths and filters

### Fixed
- Map date picker now defaults to earliest QSO date instead of invalid date
- Metadata modes (SOLAR, WEATHER, NOTE) filtered from map mode picker
- All streaks now use UTC consistently for date calculations
- Tour text alignment in Track Your Progress step
- Swift 6 concurrency warnings

## [1.9.0] - 2026-01-27

### Added
- Callsign Aliases feature for users who have changed callsigns over time
  - Configure current callsign and list of previous callsigns in Settings
  - Auto-detects multiple callsigns in QSO data and suggests adding as aliases
  - QRZ sync now properly matches QSOs logged under any user callsign
  - Current callsign auto-populated from QRZ on first connection

## [1.8.3] - 2026-01-27

### Added
- "Request a Feature" button in Settings linking to Discord

### Fixed
- Deduplication now treats equivalent modes as duplicates (PHONE/SSB/USB/LSB/AM/FM/DV, DATA/FT8/FT4/PSK31/RTTY)
- When merging duplicates, the more specific mode is preserved (e.g., SSB over PHONE)

## [1.8.2] - 2026-01-27

### Added
- Bug report feature with clipboard copy and Discord link in Settings
- Discord server link in Settings

### Fixed
- Configure button on dashboard service cards now navigates to settings instead of spinning indefinitely

## [1.8.0] - 2026-01-27

### Changed
- Redesigned dashboard services section as a compact vertical stacked list
  - Replaced 2x3 grid of large cards (~130pt each) with HIG-compliant list rows (~44pt each)
  - Each service shows status indicator, name, sync count, and optional secondary stats
  - Tapping a service opens a detail sheet with full stats and actions
- Consistent "Not configured" status text across all services

### Fixed
- Consider park reference when merging duplicate QSOs

## [1.7.0] - 2026-01-26

### Added
- POTA parks cache for displaying human-readable park names throughout the app

### Fixed
- Dashboard activation stats now match POTA activations view calculations
- Swift 6 concurrency warnings in POTAParksCache

## [1.6.0] - 2026-01-26

### Fixed
- Handle case where user hasn't finished POTA account setup
- POTA login and activation grouping improvements
- Show QSO rows in POTA uploads view

## [1.5.0] - 2026-01-25

### Added
- Force re-download debug buttons for all services (LoFi, HAMRS, LoTW, QRZ, POTA)
- Methods to force re-download and reprocess QSOs from any service

### Fixed
- POTA uploads reliability improvements
- DXCC entity handling

## [1.2.0] - 2026-01-25

### Added
- QRZ QSL confirmed count on dashboard
- POTA Activations view replacing POTA Uploads segment
  - QSOs grouped by park and date
  - Shows activation status (valid/incomplete)
- POTA maintenance window handling (0000-0400 UTC)
  - Countdown timer on dashboard
  - Uploads automatically skipped during maintenance
  - Developer bypass option in debug mode
- Connected status icons for all services

### Changed
- Reorganized POTA views into POTAActivations directory

### Fixed
- Remove logout/disconnect menus from dashboard service cards
- POTA sync button disabled during maintenance window
- WebView creation dispatched to main actor
- Handle POTA 403 errors same as 401

## [1.1.0] - 2026-01-25

### Added
- POTA maintenance window detection and handling
- LoTW integration for QSL confirmations
- QSLs stat card on dashboard (replacing Modes)

### Changed
- Various UI improvements following Apple HIG

## [1.0.0] - 2026-01-24

### Added
- Initial release
- QSO logging with SwiftData persistence
- Cloud sync to QRZ, POTA, Ham2K LoFi, HAMRS, and LoTW
- iCloud file monitoring for ADIF imports
- Dashboard with activity grid and statistics
- DXCC entity tracking
- Grid square tracking
- Band and mode statistics

---

# Android

The Android app has its own version line (Rust core is shared with iOS/macOS).

## [Unreleased]

## [0.7.1] - 2026-10-23

### Fixed
- **Park names on POTA spots.** The relaunched POTA API leaves `parkName`
  empty on every spot and carries the park name in `name`; the shared Rust
  spot core now falls back to it, so spot lists show park names again.
- **Satellites open instantly from cached data.** The satellite screen shows
  cached orbital data right away and refreshes in the background, instead of
  a spinner while SatNOGS downloads. The shared satellite engine also gives
  SatNOGS's slow bulk downloads a 120-second budget (was 20 s), runs one
  refresh at a time, and serves cached data for 15 minutes after a failed
  download instead of retrying on every open.

## [0.7.0] - 2026-10-14

### Changed
- **New release signing key — reinstall required.** 0.7.0 is signed with a new
  key (the original keystore was lost), so Android refuses to install it over
  0.6.x and earlier. Sign in to Carrier Wave Sync (the only full-log backup on
  0.6.x; ADIF export there covers POTA activations only), uninstall the old
  app, then install 0.7.0. New certificate SHA-256 `7dbc092a…989e1`;
  0.4.0–0.6.2 were `116bd19a…0f827ff`.

### Fixed
- **Android build on Kotlin 2.1.** The AMT sign-in poll timeout constant no
  longer fails to compile (`UInt` multiplication isn't a constant expression).

### Added
- **Import ADIF files.** Logbook → ⋮ → Import ADIF… opens the system file
  picker for any `.adi`/`.adif` file. Records already in the logbook — same
  callsign, band, mode and 2-minute window, the rule iOS uses — are skipped,
  multi-operator logs keep only your QSOs, and an "Import Complete" dialog
  reports imported / duplicates / errors. The parse, filter, dedup and insert
  run in the shared Rust core (`AdifApi.importAdif`), so Android and iOS agree
  on what counts as a duplicate.
- **Another Morse Trainer streak.** More → Another Morse Trainer connects your
  AMT account with an emailed sign-in link (no password, read-only). Home then
  shows a purple "Morse" streak cell in Awards & streaks and draws practice
  days in purple on the activity grid (solid for practice-only days, a corner
  dot on days with QSOs too), with a small legend. Stats are cached offline and
  refresh when Home opens. Shares the Rust `AmtApi` with iOS/macOS.

## [0.6.2] - 2026-09-20

### Changed
- **Pointing mode keeps the tuning readout while steering.** The
  Doppler-corrected downlink/uplink, mode, and Doppler shift no longer
  disappear when you drift off target — they stay below the correction
  chevrons at a fixed size and position, so the frequency doesn't move
  when lock is gained or lost.

### Fixed
- **Satellite search crashed the app.** The search list keyed its rows by an
  unsigned NORAD id, a type Android can't store in saved instance state —
  the screen crashed as soon as the catalog had loaded and the first row
  rendered (masked in 0.6.0 by the fetch failure that left the list empty).
- **Zooming the satellite chart crashed with a bird selected.** The selected
  satellite's name label drew with the measuring `drawText` overload, whose
  text constraints go negative once the dot's projected position leaves the
  canvas — which pinch-zooming routinely causes. The label now pre-measures
  and draws the laid-out text, which is safe at any offset (reported by
  KM7BUM).
- **Satellites show real names instead of "OBJECT C" placeholders, and
  FO-29-class birds are back.** Canonical SatNOGS registry names (with
  OSCAR designator aliases) replace TLE launch placeholders, and
  AMSAT-tracked birds whose SatNOGS transmitters are mislabeled
  `service: Unknown` — FO-29 among them — are no longer dropped from the
  catalog (both via the shared Rust core; reported by KM7BUM).

## [0.6.1] - 2026-09-20

### Fixed
- **Diagnosable network errors.** Fetch failures (e.g. the Satellites
  SatNOGS load) now report the underlying cause — DNS, TLS, connection
  refused, or timeout — instead of the opaque "error sending request for
  url (…)", so a screenshot of the error is enough to tell what actually
  failed.

## [0.6.0] - 2026-09-20

### Added
- **Satellites.** The full satellite suite arrives on Android, driven by the
  new shared Rust engine (`SatelliteApi`: SGP4 propagation, SatNOGS/AMSAT
  cache-through refresh, pass prediction, alert planning): live azimuthal
  sky chart with coastlines, drag/pinch and tap-select; search, per-bird and
  all-sky pass lists with favorites; pass alerts as exact alarms (degrading
  gracefully when revoked) with a 6-hour background refresh, boot recovery,
  and notification deep links; post-LOS quick log that writes QSOs with
  `SAT_NAME`/`PROP_MODE=SAT` under a born-completed session (a live POTA
  activation is never disturbed); in-pass audio recording with tap marks
  that pre-seed the quick-log rows and inline playback; a tilt-aware sky
  dome; and a boom-mounted antenna pointing mode with compass tape,
  elevation deviation scale, Doppler-corrected tuning, and gyro boom-axis
  calibration.

## [0.5.2] - 2026-08-27

### Changed
- **SOTA spots temporarily disabled.** The SOTAwatch API shuts down
  2026-08-31 and its replacement requires prior approval before clients may
  connect; SOTA spots return once Carrier Wave migrates to the new API. SOTA
  summit data and SOTA session logging are unaffected.

### Fixed
- **"SOTA: JSON parse error" banner on the Hunter page.** SOTAwatch began
  injecting an invalid deprecation-notice entry into its spots feed, which
  broke the whole SOTA source. Spots now decode independently, so one bad
  entry can never take down a feed.

## [0.5.1] - 2026-08-02

### Changed
- **Hunter Log filter menu now collapses on scroll.** The source chips,
  map/filter toggles, last-refresh pill, and sort picker slide away when you
  scroll down through the spot list and reappear when you scroll back up,
  giving spots more room on smaller screens (CAR-297).

### Fixed
- **QSOs logged in a session were invisible in Home & Logbook until relaunch.**
  The shared logbook snapshot only refreshed on its own writes, so QSOs logged
  through an active session (which go straight to the store via `SessionApi`)
  never appeared on the Home or Logbook tabs — only a search would surface
  them — making an ended session look like it had lost its contacts. The
  repository now registers a Rust `StoreObserver` (the same reactivity iOS gets
  from SwiftData `@Query`) and re-fetches the snapshot on any committed QSO
  change, debounced so a burst collapses to one refresh (CAR-291).
- **Map top-edge flicker.** The full-screen Map tab and Parks & Summits search
  no longer flicker along the top edge while panning — the osmdroid `MapView`'s
  transient overdraw is now clipped to its bounds, matching the embedded map
  cards (CAR-293).
- **Session detail was broken (couldn't delete or edit a session).** The
  post-session detail fetched its QSOs with a limit above the store's
  `MAX_FETCH_LIMIT`, so the fetch threw and — because the session and its QSOs
  loaded in one guarded block — silently discarded the session too. The screen
  then showed the fallback "Session" title with no summary card, and every
  menu action gated on the session (Delete/Reopen/Edit Info) did nothing.
  QSOs are now fetched within the store limit (CAR-294).
- **Session detail & replay title bars sat too low.** Their nested top bars
  re-applied the status-bar inset already handled by the app's main scaffold,
  leaving a gap above the title; those bars' window insets are now zeroed
  (CAR-294).

## [0.5.0] - 2026-07-21

### Added
- **Propagation check ("How's my antenna?").** A new host over the shared Rust
  `PropagationApi`: a start sheet (callsign, bands, grid, duration cap), a live
  view with headline stats, an interactive map, an azimuthal range-ring card,
  per-source connectivity indicators, and a streaming spot feed, plus a results
  view with a per-band breakdown (max distance, median and peak SNR) and
  recorded connectivity gaps. Passive (receive-only) for now — no transmit /
  Auto-CQ mode or saved history yet.
- **Brag sheet share card.** The Brag Sheet gains a Share button with the six
  custom map styles (Azimuthal, Midnight, Warm, Ocean, Arctic, Ember): the
  stats card and its map composite from the shared Rust rasterizer — with the
  azimuthal range-ring labels overlaid — then share as an image. An empty grid
  falls back to a mapless card with Share still enabled.
- **POTA activation browser — awards, conditions, ADIF export, share.** The
  activation browser gains a POTA Awards & Certificates screen (overview,
  tiered progress, Kilo/LaPorta/Six Pack specials from the shared Rust
  `pota_awards`); a Conditions sheet on the detail screen showing recorded
  solar/weather metadata; single-activation and multi-select bulk ADIF export
  (shared Rust ADIF writer → `.adi` share intent); and an activation share
  card with the six Rust-rasterized map styles, RST-colored per-QSO pins, home
  traces, and flat/azimuthal framing — mirroring iOS. Reusable share plumbing
  (style picker, layer capture, FileProvider write, ring overlay, RST colors)
  now lives in a shared `ui/share/` package.
- **Parks & Summits map.** A new map (Parks chip on the Map tab): clustered
  POTA park and SOTA summit pins with name search, park boundary and trail
  overlays (server-merged polygons), SOTA activation zones, US state/county
  lines, WWFF areas, grid-square and TOTA tile layers, tappable callouts
  with park details, and the Rosette multiplier finder (POTA+SOTA,
  POTA+WWFF, county-line spots) — all on the shared Rust core.
- **Debug log.** A More-tab screen collecting app diagnostics in memory
  (copy/clear), mirroring iOS's in-app log surfaces; map lookup failures now
  land there.
- **Spot sorting.** A Recent / Frequency / Needs segmented control above the
  spots list, matching iOS: newest-first, lowest-frequency-first, or
  highest-need-priority-first ordering.
- **Map camera auto-fit.** On first load the QSO map now frames the
  Rust-computed bounds of your contacts (antimeridian-aware), matching iOS
  first-load framing, instead of a fixed zoom on the home grid.
- **Timeline replay.** Sessions gain a full-screen replay screen (from the
  session detail map card's Replay button): scrub or play through the
  session at 1×/2×/4×/8× while QSO pins accumulate and RBN spot circles
  sized by SNR fade out on the shared decay curves — event tick marks and
  elapsed/remaining labels on the scrubber, matching iOS.
- **QSO detail map card.** The Logbook edit sheet shows my/their pins, the
  geodesic arc, and a distance/bearing footer for the opened QSO.
- **Callsign map section.** A single-pin card with distance and compass
  bearing from your home grid, above the QSO detail map.
- **Session detail map card.** Session QSO pins, rove stops, and arcs with
  auto-fit framing on the session detail screen.
- **Spots mini-map.** A collapsible map above the spots list: RBN spots
  colored/sized by SNR, POTA/SOTA/WWFF in their program colors, arcs from
  your grid to each spotter.

### Changed
- **Club map precise pins.** Member grid centroids refine in the background
  to precise QRZ/HamDB coordinates via the shared Rust lookup + cache;
  members with no grid on file now get pins.

### Fixed
- **SOTA activation-zone downloads no longer fail with a rate-limit error.**
  Fetching activation zones fired many chunked requests with no pacing and gave
  up on the first `429`, so a bulk download aborted. The refresh now paces
  itself under the server's per-IP limit and honors the server's retry backoff,
  so it completes (and resumes) instead of erroring out. (Shared with iOS.)
- **Stale map reloads.** Changing map filters rapidly no longer lets a slow
  earlier load overwrite a newer one — each reload cancels the in-flight
  request.
- **Club map refinement no longer double-fires.** Opening a club detail ran
  the member location lookup twice (cached and server member loads); it now
  runs once unless the roster actually changes.

## [0.4.0] - 2026-07-16

### Added
- **The activation logger.** Starting a session now opens a live QSO-entry
  logger (new **Sessions** tab) — a session header, a callsign/RST/grid/notes
  form with mode-default RST, SCP suggestions, day-scoped dupe detection, a
  running QSO list, and pause/end — all driven by the shared Rust core,
  mirroring the iOS Sessions tab.
- **Redesigned session start wizard.** Icon-led section headers, an operator
  hero (callsign + grid), a segmented mode picker, program chips (POTA selected
  by default), an inventory-backed gear loadout selector, a collapsed "More
  Options" disclosure, and a pinned Start button that carries the disabled
  reason. Frequency and park auto-populate on open.
- **Interactive frequency scope.** A scroll-to-tune ruler with a band/step
  strip, live spot rows, a Set field, and Find-clear, matching the iOS selector.
- **Brag Sheet.** Customizable achievement stats across weekly/monthly/all-time
  periods, backed by the shared Rust engine.
- **Magic-link sign-in opens the app directly.** Tapping the emailed
  verification link now hands off to the app (App Links + a `carrierwave://auth`
  scheme) and completes sign-in itself instead of finishing in the browser.
- **Edit logged QSOs from the Hunter tab.** Tapping the "Hunter Log" summary
  card now expands today's logged contacts beneath it; tapping any contact opens
  an inline editor for the common fields (callsign, band, mode, frequency, RST,
  their grid/QTH/state/country/park, notes), with delete. Saves and deletes go
  through the shared store. (CAR-289)
- **Band / mode / needs filters on the spot feed.** A new filter button on the
  Hunter (and Sessions) spot browser opens a sheet to narrow the feed by band,
  mode, and "needs only", layered on top of the existing source chips; the
  button shows a badge with the active-filter count. (CAR-289)

## [0.3.0] - 2026-07-12

### Added
- **`SPOT` and `HUNT` logger commands.** In an active session, the `SPOT`
  command now posts a POTA self-spot through the shared spot engine (fanning
  out across every park in an n-fer reference), and `SPOT REPEAT <minutes>` /
  `SPOT STOP` drive a repeating self-spot timer. `HUNT` (and `POTA` / `SPOTS`)
  opens the live activator-spots browser as a bottom sheet over the logger,
  defaulting the feed to the session's mode family (CW/Phone/Digital); tapping
  a spot seeds the quick-entry command bar. SOTA self-spotting isn't supported
  yet and reports so.

### Fixed
- **Paused sessions can be resumed again.** Pausing a session deactivates it, so
  the Sessions tab flipped to the idle prompt with no way back — the session was
  safe in the store but stranded. The idle prompt now lists paused sessions with
  a Resume button (reactivating one pauses any other active session).

## [0.2.2] - 2026-07-12

### Added
- **Themes.** Six selectable app themes from a new Appearance card on the More
  tab, applied instantly and persisted across launches: Instrument (the
  original green-on-charcoal default), Nixie (warm tube glow), Waterfall (SDR
  spectrogram blues), Boatanchor (Collins-style cream light theme — the
  sunlight-readable field option), Phosphor (monochrome green CRT), and Grey
  Line (vaporwave dusk).

## [0.2.1] - 2026-07-12

### Added
- **Magic-link sign-in opens the app directly.** Tapping the emailed
  verification link now hands off to the app (App Links, plus a
  `carrierwave://auth` scheme) and finishes sign-in itself instead of stranding
  you in the browser — no switching back and waiting.

### Fixed
- **Magic-link sign-in no longer fails with a spurious "network error."**
  Leaving the app to open the emailed link could tear down the connection; the
  shared Rust poll now tolerates transient transport/5xx blips and retries
  instead of aborting the whole sign-in.
- **Cancel actually stops a sign-in.** Cancelling now cancels the in-flight
  poll, so it can't keep polling in the background or flip the UI afterward.

## [0.2] - 2026-07-12

### Added
- **Session start wizard.** Starting a session opens a full wizard at parity
  with iOS — Activate / Casual / Contest flows, an operator hero (callsign +
  grid), a segmented mode picker, program chips (POTA selected by default), an
  inventory-backed gear loadout with a collapsed summary, a collapsed "More
  Options" disclosure, and a pinned Start button carrying the disabled reason.
  Frequency and park auto-populate on open, and park references show name,
  location, and your own activation/hunter stats. Includes TOTA, pack
  checklist, multi-operator, and prefix sections.
- **Activation logger (new Sessions tab).** A live QSO-entry logger — session
  header, a callsign/RST/grid/notes form with mode-default RST, Super Check
  Partial suggestions, day-scoped dupe detection, a running QSO list, and
  pause/end — all driven by the shared Rust `SessionApi`.
- **Interactive frequency scope.** A scroll-to-tune ruler with a band/step
  strip, live spot rows, a Set field, and Find-clear, matching the iOS
  selector.
- **Logger command bar.** Quick-entry commands (`FREQ`/`MODE`/`SPOT`/`RBN`/
  `HUNT` and their aliases) run through the shared Rust command handler.
- **Brag Sheet.** Customizable achievement stats across weekly, monthly, and
  all-time periods, backed by the shared Rust engine.
- **SDR Tune-In.** Listen to an activator on a public KiwiSDR straight from the
  hunter feed — receiver selection and audio decode run in the shared Rust
  core, with a mini player bar.
- **External Data card.** The Account screen gains FCC callsigns, POTA parks,
  SOTA summits & zones, WWFF directory, Super Check Partial, equipment catalog,
  and contest definitions — each with count, age, and refresh.
- **POTA respot.** POTA spots gain a respot button that posts a fresh spot
  through the shared Rust core, with a confirmation preview and a 5-minute
  anti-spam cooldown.
- **Pull-to-refresh spots.** Pull the hunter spot list down to poll
  immediately, with a live "last refreshed" pill.
- **Set session fields from the quick-entry bar.** A callsign-less line like
  `14.046 CW CN87` updates the active session's frequency, mode, and grid for
  QSOs logged from then on.

### Changed
- **Frequency-scope logic moved to the shared Rust core** — ruler rows and
  band-plan verdicts are now identical to iOS.
- **Brag Sheet config** is now stored in the shared `synced_config` store.

## [0.1] - 2026-07-04

### Added
- **First Android release.** Carrier Wave on Android, built on the same shared
  Rust core (via UniFFI) as iOS and macOS.
- **iOS-mirroring tabs** — Home, Sessions, Logbook, Map, Friends, and More.
- **Live spot monitoring.** The hunter feed runs on the shared Rust spot engine
  with callsign enrichment and an "All" merged feed; command bars show dupe
  badges and Super Check Partial suggestions.
- **Quick-entry command bar** with lone-callsign recognition and live
  enrichment shown inline.
- **End-to-end encrypted log sync** — per-server data keys, an auto-seeded
  first sync, 429 retry, and a live sync phase and timing readout.
- **Clubs & Friends** membership on the shared Rust core, applied in batched
  transactions and auto-syncing on launch and sign-in.
- **Profile settings and an activity heatmap.**
- **Awards & Streaks dashboard card** built from shared Rust aggregates.
- **POTA UTC-midnight split** for multi-day activations on session end.
- **Signed release APKs** for shareable builds.
