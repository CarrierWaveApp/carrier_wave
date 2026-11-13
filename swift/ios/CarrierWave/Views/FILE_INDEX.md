## Views - Achievements (`swift/ios/CarrierWave/Views/Achievements/`)
| File | Purpose |
|------|---------|
| `AchievementBadgeView.swift` | Single achievement tile (icon, name, accent color, locked/secret state) |
| `AchievementShowcaseView.swift` | Grid of catalog achievements grouped by category, lights up earned ones |
| `AchievementShowcaseContainer.swift` | Loader: fetches catalog + user awards via ActivitiesClient and feeds the showcase |
| `AchievementDetailSheet.swift` | Tap-to-show detail sheet (icon, tier, full description, earned status, locked-state copy) |

## Views - Recording Player (`swift/ios/CarrierWave/Views/RecordingPlayer/`)
| File | Purpose |
|------|---------|
| `RecordingWaveformView.swift` | Reusable amplitude waveform with QSO span regions, segment boundaries, playback head, drag-to-seek |
| `CompactRecordingPlayer.swift` | Inline card for activation detail and sessions list |
| `RecordingPlayerView.swift` | Full-screen player with transport controls, speed picker, transcript panel, collapsible QSO list |
| `RecordingPlayerView+Actions.swift` | Share clip sheet with draggable range handles, QSO markers, playback preview, and export |
| `ShareClipSheet+Subviews.swift` | ShareClipSheet subviews: waveform overlay, handles, transcript snippet, export actions |
| `RecordingShareCardView.swift` | Branded share card view for SDR recording clips (waveform, metadata, QSOs, transcript) |
| `RecordingShareCardRenderer.swift` | Renders RecordingShareCardView to UIImage via ImageRenderer |
| `RecordingSharePreviewSheet.swift` | Preview sheet for rendered share card with Share and Save to Photos |
| `RecordingTranscriptView.swift` | Karaoke-style CW transcript with per-word highlighting, auto-scroll, segment dividers |

## Views - Sessions (`swift/ios/CarrierWave/Views/Sessions/`)
| File | Purpose |
|------|---------|
| `SessionsTabView.swift` | Top-level Sessions tab container: switches between idle (sessions list) and active (logger) based on session state |
| `SessionsIntentView.swift` | Intent-first landing screen: header builder, optional role prompt + quick-start row, intent grid, continue/Hunter Log/quick-start sections |
| `SessionsIntentView+Actions.swift` | Routing for the four intent cards (Activate/Hunt/Casual/Contest) plus recent/saved template start helpers |
| `SessionsIntentView+IntentGrid.swift` | 2×2 IntentGrid and IntentCard structs (extracted to keep parent file under SwiftLint cap) |
| `SessionsIntentView+RolePrompt.swift` | First-launch operator-style prompt card shown until OperatorRole is set |
| `SessionsIntentView+QuickStart.swift` | "Same as Last Session" card + bypass-wizard action that calls sessionManager.startSession directly with the prior session's settings |
| `SessionDialogModifiers.swift` | Finish and delete session confirmation dialog View modifiers |
| `SessionsView.swift` | Unified sessions list merging POTA activations and all sessions, with rich content |
| `SessionsView+Actions.swift` | Data loading, POTA actions, session deletion for SessionsView |
| `SessionsView+Helpers.swift` | Utility functions: findSession, engine lookup, maintenance timer |
| `SessionsView+Share.swift` | Brag sheet generation and equipment list building for share cards |
| `SessionsView+QRZUpload.swift` | QRZ upload actions and pending count computation for Sessions list |
| `SessionsListGrouping.swift` | Sendable row snapshot + `SessionsListGroupingActor`: off-main newest-first sort and UTC month bucketing for the cached Sessions list |
| `SessionRow.swift` | Unified rich session row: timeline, conditions, badges, upload status |
| `SessionADIFImportModifier.swift` | ViewModifier for importing ADIF into a session with metadata validation |
| `BatchGridEditSheet.swift` | Sheet for batch-setting grid square on all QSOs in a session |
| `SessionQSORow.swift` | Compact QSO row for session detail (tap to edit, swipe-to-delete) |
| `SessionAddQSOSheet.swift` | "Add QSO" sheet for an ended session: one quick-entry line (same `QuickEntryParser` grammar as the logger, colour-coded `QuickEntryPreview`, debounced `LoggerCallsignCard` lookup, "Will log" preview rows with in-log duplicate badge) logged via `SessionLateEntryService` |
| `SessionQSOExpandedDetail.swift` | Expanded view shown when a QSO row is opened: contact, location, extras, notes, attached spot comments |
| `SessionDetailView.swift` | Unified session/activation detail with three-tier layout: hero, QSOs, insights |
| `SessionDetailView+Hero.swift` | Tier 1 hero card: summary, stats, band/mode pills, details, shifts, conditions |
| `SessionDetailView+Insights.swift` | Tier 3 horizontal insights carousel: Map, States, Parks compact cards |
| `SessionDetailView+Components.swift` | Stat strip, rove stops, details section, and supporting types |
| `SessionDetailView+QSOs.swift` | QSO list sections (flat and rove-grouped) and data loading |
| `SessionDetailView+Clubs.swift` | Club members summary card for session detail (callsigns + club names) |
| `SessionDetailView+StatesWorked.swift` | Signal mosaic: 10×5 grid of US states worked with intensity and popover details |
| `SessionDetailView+POTA.swift` | POTA upload controls, jobs section, recording player, and data loading |
| `SessionDetailView+TOTA.swift` | TOTA section: tile + score header, bonus chips, T3 list, refresh-spots footer |
| `SessionDetailView+TOTAComponents.swift` | TOTA score ledger, path map (track polyline + tile boundary overlay) with GPX export, T3 candidate list |
| `SessionDetailView+Parks.swift` | Park boundary loading and card building for carousel in session detail |
| `ParkCardCarouselView.swift` | Instagram album-style swipeable park maps with GIS boundaries and grid overlay |
| `TimelineMapView.swift` | Session replay view: map with time slider showing QSOs and RBN spots chronologically, sourced from `MapApi.sessionTimeline` + shared Rust curves |
| `TimelineSliderView.swift` | Custom slider with QSO (blue) and RBN spot (green) tick marks |
| `VideoExportButton.swift` | Export Video entry point on session detail |
| `VideoExportDefaults.swift` | UserDefaults-backed last-used VideoExportConfig (layers, HUD density, theme) for sheet pre-fill |
| `VideoExportSheet.swift` | Export configuration (mode, audio, map style) and progress UI |
| `VideoExportSheet+Progress.swift` | Progress view with thumbnail preview and time estimate |
| `PSKReporterSenderSection.swift` | "Who heard me?" section for digital mode sessions (fetches PSK Reporter sender spots, deduplicates by receiver) |
| `SessionSpotsSection.swift` | Persisted spots display section for session detail (POTA highlighted, RBN collapsed) |
| `SessionSpotsSummaryRow.swift` | Expandable spots summary row for sessions list (region pills, distance range, logger-style aggregation) |
| `SessionMetadataEditSheet.swift` | Unified edit sheet for all session types (equipment, photos, notes, operators) |
| `MultiOpExportSheet.swift` | Multi-operator ADIF export sheet with per-operator file generation |
| `SessionADIFExportSheet.swift` | Program-agnostic per-session ADIF export sheet (POTA / SOTA / dual / casual), share + save + copy buttons |
| `SessionADIFExportSheet+Flavors.swift` | Per-program (POTA / WWFF / SOTA) flavored share rendering for n-fer sessions; shows one "Submit to X" button per detected program (ADIF or SOTA V2 CSV transferable) plus a combined-archive link |
| `SplitADIFExportSheet.swift` | Split ADIF export UI: toggles for UTC day/park/operator splitting with file list |
| `PhotoViewer.swift` | Full-screen photo viewer with pinch-to-zoom |
| `VideoExportSheet.swift` | Sheet for configuring and initiating video export (mode, audio, map style) |
| `VideoExportSheet+Progress.swift` | Progress view shown during video rendering (thumbnail preview, frame counter, time remaining) |

## Views - Conditions (`swift/ios/CarrierWave/Views/Conditions/`)
| File | Purpose |
|------|---------|
| `ConditionsCard.swift` | Dashboard card with sparkline and latest metrics, links to full history |
| `ConditionsHistoryView.swift` | Full-screen conditions history with timeline/location tabs and date range |
| `ConditionsHistoryChartView.swift` | Time-series line chart for solar/weather metrics with Swift Charts |
| `ConditionsByLocationView.swift` | Bar chart comparing conditions across grid squares |

## Views - Contests (`swift/ios/CarrierWave/Views/Contests/`)
| File | Purpose |
|------|---------|
| `ContestsCard.swift` | Dashboard card showing active and upcoming contests from WA7BNM Calendar |

## Views - Components (`swift/ios/CarrierWave/Views/Components/`)

| File | Purpose |
|------|---------|
| `BadgePillModifier.swift` | Reusable `.badgePill()` view modifier for capsule-shaped badges |
| `BrandWordmark.swift` | Quiet leading-toolbar logotype (radio-waves glyph + "Carrier Wave") — Home title that never competes with the hero |
| `CountedPill.swift` | Capsule pill pairing a label with a parenthesised count (`20m (12)`) — used by session/day hero pills |
| `SessionStatStrip.swift` | Tier 1 hero stat strip (value/label/percentile cells) shared by `SessionDetailView` and `DaySummaryView` |
| `IdentityCard.swift` | Canonical operator identity hero (callsign, flag, license, metadata, club pills) — used by AboutMeView and CallsignHistoryView |
| `BadgesStripCard.swift` | Self-contained earned-badges horizontal strip with detail sheet — used by AboutMeView and CallsignHistoryView |
| `ContactCountBadge.swift` | Tiered contact count badge (bronze/silver/gold at 10/25/50 QSOs) |
| `ExperimentalBadge.swift` | Consistent badge for experimental features (orange beta, red alpha) |
| `ReferenceChip.swift` | Generic removable chip for reference codes (replaces SummitChip, WWFFChip) |
| `SingleReferenceEntryField.swift` | Generic single-value reference entry field with chip, lookup, picker |
| `UnderConstructionBanner.swift` | Under-construction banner for incomplete features |
| `WorkedBeforeBadges.swift` | Shared dupe/worked-before badge component for spot rows |

## Views - Logger (`swift/ios/CarrierWave/Views/Logger/`)
| File | Purpose |
|------|---------|
| `LoggerContainerView.swift` | iPad two-pane wrapper: HStack with logger + spots sidebar on regular, plain logger on compact. Accepts external sessionManager from SessionsTabView |
| `LoggerSpotsSidebarView.swift` | Tabbed sidebar with segmented picker for POTA/RBN/P2P spots |
| `SpotSelection.swift` | SpotSelection enum, SidebarTab enum, SpotCommandAction enum for sidebar integration |
| ~~`SidebarPOTASpotsView.swift`~~ | **Deleted** — merged into `POTASpotsView` with `POTASpotsDisplayMode` |
| ~~`SidebarPOTASpotsView+Clubs.swift`~~ | **Deleted** — merged into `POTASpotsView+Clubs.swift` |
| ~~`SidebarRBNSpotsView.swift`~~ | **Deleted** — merged into `RBNPanelView` with `RBNDisplayMode` |
| `SidebarP2PView.swift` | P2P opportunities adapted for persistent sidebar display |
| `SidebarMapView.swift` | Sidebar wrapper around `SessionQSOMap` with stats bar header |
| `iPadCommandStrip.swift` | Persistent command row for iPad (always visible, not keyboard-dependent) |
| `LoggerView.swift` | Main logger struct definition with stored properties and body |
| `LoggerView+Layout.swift` | Portrait layout, panel overlays, callsign lookup display, WebSDR badge |
| `LoggerView+SessionHeader.swift` | Session header views, controls bar, band/mode/equipment capsules |
| `LoggerView+SessionBadges.swift` | Session control bar badges: space weather chip, SDR, WebSDR, radio, equipment helpers |
| `OperatorsSheet.swift` | Multi-op operators sheet with enriched callsign lookup cards |
| `LoggerView+FormFields.swift` | Callsign input, compact fields, QSO list section, computed properties |
| `LoggerView+Commands.swift` | Command execution, spot posting, spot handling |
| `LoggerView+QSOLogging.swift` | QSO logging, quick entry, multi-callsign quick entry |
| `LoggerView+HuntLog.swift` | HUNT command handler: log one-off off-frequency QSO without disturbing active session |
| `LoggerView+SessionEnd.swift` | Session end handling, POTA upload prompt |
| `LoggerView+Data.swift` | Data refresh, callsign lookup, duplicate detection (all session types), frequency warnings, spot enrichment |
| `LoggerView+DataHelpers.swift` | SCP suggestions, callsign/park helpers, utility functions |
| `LoggerView+HelperViews.swift` | CallsignDuplicateStatus, LoggerNoteRow, LoggerQSORow, DuplicateStatusBanner, SwipeToDismissPanel |
| `BoundaryMarkerRow.swift` | Inline separator row for UTC day changes and POTA shift boundaries in QSO lists |
| `LoggerView+EditSheets.swift` | LoggerQSOEditSheet, SessionTitleEditSheet, SessionParkEditSheet |
| `LoggerView+SessionSheets.swift` | HiddenQSOsSheet, DeleteSessionConfirmationSheet, SessionBandEditSheet, SessionModeEditSheet |
| `LoggerView+Modifiers.swift` | Sheet presentations and lifecycle/event handler modifiers |
| `LoggerView+Landscape.swift` | Logger landscape two-pane layout (form left, QSO list right) and compact session header |
| `CallsignTextField.swift` | UITextField wrapper for callsign entry with proper cursor handling |
| `SCPSuggestionsView.swift` | Horizontal chip bar showing SCP callsign suggestions |
| `LoggerCallsignCard.swift` | Callsign info display card for logger |
| `LoggerCallsignComponents.swift` | ChipFlowLayout, DetailChip, CompactCallsignBar, error banners |
| `LoggerView+MultiLookup.swift` | Multi-callsign concurrent lookup logic for multi-op contacts |
| `MultiCallsignLookupState.swift` | Enum for multi-callsign lookup states (loading/found/notFound/error) |
| `MultiCallsignLookupView.swift` | Compact chips + expandable card for multiple callsign lookups |
| `NetworkHealthBanner.swift` | Persistent network degradation/disconnection warning banner |
| `SessionStartSheet.swift` | Session wizard for mode, frequency, activation type, equipment |
| `SessionStartSheet+Wizards.swift` | `SessionOperationType` enum + per-type wizard layouts (activation / casual / contest) tailoring which sections show |
| `SessionStartSheet+Sections.swift` | Callsign and activation section views |
| `SessionStartSheet+Contest.swift` | Contest section for session start (extracted from Sections) |
| `CallsignPrefixSheet.swift` | Searchable prefix picker: GPS suggestion, country browser, custom entry |
| `SessionStartSheet+Equipment.swift` | Equipment, attendees, and notes sections for session start |
| `SessionStartSheet+Templates.swift` | Save-as-template and apply-template logic for session start |
| `SessionStartSheet+Reminders.swift` | Gear reminder checklist section (don't-forget items) for session start |
| `SessionStartSheet+Loadouts.swift` | Rust-backed loadout actions (load/apply/create/rename/delete) over `LoadoutStore`; drives the Gear section's pull-down |
| `SessionStartSheet+GearSection.swift` | Form-native Gear section ("Option A"): loadout pull-down selector + expandable inline component menus + inline new/save/rename dialogs |
| `SessionStartSheet+Brand.swift` | Brand styling helpers (tinted card row surfaces) for the session wizard |
| `SessionStartSheet+Hero.swift` | Callsign hero (full + compact bar variants — compact when callsign/grid stable, full when something needs attention) |
| `GearComponentMenu.swift` | One inline gear slot (Radio/Antenna/Key/Mic): inventory pull-down + fully-inline typeahead add (Rust catalog search + add), no sheet |
| `EquipmentInventoryModel.swift` | `@Observable` live inventory surface — reads active gear from cw-store (Rust), refreshes on the `.equipmentItem` store observer |
| `SessionStartSheet+FrequencySuggestion.swift` | Auto-picks the most-activated band (constrained to the selected radio's capable bands) then a free frequency on it via `FreeFrequencyPlanner`/`ActiveSpotsLoader` (live POTA/SOTA/RBN spots), falling back to the mode's calling frequency; explanatory note + "Change" override callout |
| `ContestScoreSummaryView.swift` | Contest score summary and Cabrillo export in end session flow |
| `EquipmentPickerSheet.swift` | Generic equipment picker (antenna, key, mic) with user-managed list |
| `SessionStartHelperViews.swift` | Helper views and validation for session start (CallsignBreakdown, ActivationSection, FrequencySuggestions) |
| `CrossReferenceSuggestionView.swift` | Suggestion chip for cross-program reference matching (POTA/WWFF/SOTA) |
| `LiveActivitySuggestionsView.swift` | Unified FrequencyBandView: static band frequencies + live POTA/SOTA/RBN spots (via `ActiveSpotsLoader`) + nestled clear-frequency recommendations (via `FreeFrequencyPlanner`) |
| `BandPlanSheet.swift` | Interactive band plan reference with visual chart, segments, license requirements, and activities |
| `BandChartView.swift` | Visual ARRL-style band allocation chart with license class and mode zone display |
| `BandChartLegendView.swift` | Color key legend for band chart display modes |
| `RadioPickerSheet.swift` | Radio/rig picker sheet with user-managed list and RadioStorage helper |
| `SessionEquipmentEditSheet.swift` | Compact equipment editor (radio, antenna, key, mic) for active sessions |
| `ParkPickerSheet.swift` | Multi-select park search/nearby sheet for n-fer |
| `ParkEntryField.swift` | Multi-park entry with chips, search picker, and shorthand |
| `SummitPickerSheet.swift` | Single-select SOTA summit search/nearby sheet |
| `NearbyReferenceSuggestions.swift` | Inline nearby park/summit suggestions for session start (GPS + grid fallback) |
| `SummitEntryField.swift` | SOTA summit entry with live name lookup and search picker |
| `WWFFReferenceEntryField.swift` | WWFF reference entry with live name lookup and search picker |
| `WWFFReferencePickerSheet.swift` | Single-select WWFF reference search/nearby sheet |
| `WWFF/WWFFActivationProgressView.swift` | WWFF activation progress with per-reference 44-QSO tracking and award tier progression |
| `WWFF/WWFFRepresentativeLookupView.swift` | WWFF national representative lookup with email compose for log submissions |
| `ParkDetailSheet.swift` | Park detail sheet with stats, leaderboard (top activators/hunters), and recent activations from POTA API |
| `ActiveSessionRow.swift` | Compact row for active/paused sessions with Continue/Finish actions |
| `RBNPanelView.swift` | Combined RBN/POTA spots panel with mini-map |
| `RBNPanelView+Data.swift` | Panel data loading (Rust engine per-callsign fetch) + source color/icon helpers |
| `SpotsMiniMapView.swift` | Map view showing spotter locations with arcs to target |
| `SpotCommentsSheet.swift` | POTA spot comments display sheet |
| `SolarPanelView.swift` | Solar conditions panel (K-index, SFI, propagation) |
| `SolarPanelSpaceWeatherSection.swift` | Space weather alerts section within Solar Panel |
| `SpaceWeatherBannerView.swift` | Compact overlay banner for active space weather events in logger |
| `WeatherPanelView.swift` | Weather conditions panel from NOAA |
| `FrequencyActivityView.swift` | Nearby frequency activity display with QRM assessment |
| `FrequencyWarningBanner.swift` | Unified frequency warning banner (license violations + activity warnings) |
| `LoggerToastView.swift` | Toast notification system for logger |
| `QSYLogConfirmationSheet.swift` | Confirmation sheet for qsy://log URIs (shows pre-filled QSO for review) |
| `QRQCrewSpotSheet.swift` | QRQ Crew spot prompt sheet (WPM entry + post confirmation) |
| `LoggerKeyboardAccessory.swift` | Ordered accessory rows above keyboard (numbers, prefixes, keyer, commands) |
| `KeyboardRowConfig.swift` | KeyboardRowKind order model + CallsignPrefixer smart-replace helpers |
| `KeyboardAccessoryBuilder.swift` | UIKit builder for keyboard accessory view (ordered rows) |
| `KeyboardAccessoryBuilder+PrefixRow.swift` | Prefix hot-key row for the UIKit accessory (CAR-290) |
| `POTASpotRow.swift` | Individual POTA spot row component |
| `SOTASpotRow.swift` | Individual SOTA spot row component with summit info |
| `POTASpotsView.swift` | POTA activator spots panel with filtering |
| `POTASpotsView+Clubs.swift` | Club member spot sections for POTA spots panel |
| `POTASpotsHelperViews.swift` | Helper views for POTA spots (filter sheet, loading, empty, error states) |
| `P2PPanelView.swift` | Park-to-park opportunities panel with SNR display |
| `P2POpportunityRow.swift` | Row view for a single P2P opportunity |
| `SessionMapPanelView.swift` | Phone logger wrapper around `SessionQSOMap` with dismiss header |
| `NextRoveStopSheet.swift` | Half-sheet for transitioning to next park stop in a rove |
| `RoveProgressBar.swift` | Horizontally scrolling rove stop pills for session header |
| `EndSessionFlowView.swift` | Multi-step end session flow (summary, POTA upload, brag sheet) |
| `EndSessionFlowView+Steps.swift` | POTA upload and brag sheet step views for end session flow |
| `TOTAEndFlowSummary.swift` | Condensed TOTA score card for the end-of-session summary step (with last-chance edits) |
| `TOTAActivationFields+ScoringInputs.swift` | Start-sheet rows for TOTA category (Standard/Mobile), winter override, and Personal Effort Factor |
| `POTAUploadPromptSheet.swift` | Post-session modal prompting POTA upload (legacy, kept for reference) |
| `SpotFilters.swift` | Band and mode filter enums for spots |
| `QuickEntryPreview.swift` | Quick entry token display with color-coded badges |
| `SpotContactMismatchBanner.swift` | Banner showing spot-vs-QSO callsign near-misses |
| `SpotSummaryView.swift` | Compact spot monitoring summary with region breakdown, mini-map toggle, and full spot list |
| `WebSDRPanelView.swift` | WebSDR connection status, recording controls, level meter |
| `WebSDRPanelView+Subviews.swift` | Extension with level meter, buffer indicator, reconnecting/error views |
| `WebSDRPickerSheet.swift` | KiwiSDR receiver selection with favorites, enrichment, and band matching |
| `WebSDRReceiverRow.swift` | Enriched receiver row with antenna badges, SNR, band match |
| `RadioPanel.swift` | Bottom sheet for radio control (frequency, mode, connection status, transport picker) |

## Views - Logger Frequency Scope (`swift/ios/CarrierWave/Views/Logger/FrequencyScope/`)
| File | Purpose |
|------|---------|
| `FrequencyScopeField.swift` | Radio-section frequency control: collapsed summary (freq · band · live status) that expands to the inline band scope on tap; band selector hidden by default; binds the wizard's `frequency` string |
| `FrequencyScopeList.swift` | Vertical snapping kHz scope — spot rows (Band Scope `ScopeRow` vocabulary), hatched off-plan zones, per-segment labels, centered green/orange reticle |
| `FrequencyScopeModel.swift` | `ScopeSpot` + band-plan/activity evaluation via `BandPlanService`/`BandPlan` (license privilege, mode segment, FT8/FT4 watering holes, QRM) driving the "This is FT8" / "This is Extra, and you're General" advisory |

## Views - Logger FT8 (`swift/ios/CarrierWave/Views/Logger/FT8/`)
| File | Purpose |
|------|---------|
| `FT8SessionView.swift` | Main FT8 session view with portrait/landscape layouts, status pill, and session summary toast |
| `FT8WaterfallView.swift` | Canvas-based spectrogram waterfall display with optional tap-to-select channel |
| `FT8ChannelPicker.swift` | Sheet for selecting FT8 TX channel with occupancy recommendations |
| `FT8DebugPanel.swift` | Collapsible debug panel with audio level, decode stats, input picker |
| `FT8DecodeListView.swift` | Segmented decode list (directed/CQ/all activity) with compact mode toggle |
| `FT8ConversationCard.swift` | Active QSO conversation card with TX/RX transcript and message override |
| `FT8TranscriptRow.swift` | Single TX/RX message row for conversation transcript |
| `FT8NextTXRow.swift` | Next TX message display with expandable override picker |
| `FT8TXStatusLine.swift` | TX state indicator (armed/transmitting/halted) for control bar |
| `FT8ControlBar.swift` | Operating mode controls with CQ modifier menu, TX status, and QSO/POTA counter |
| `FT8CycleIndicatorView.swift` | 15-second cycle progress indicator with TX/RX state |
| `FT8SetupWizardView.swift` | First-time FT8 setup wizard (audio connection, radio setup, verify audio) |
| `FT8EnrichedDecodeRow.swift` | Multi-line enriched decode row with callsign, SNR badge, entity, distance, and achievement badges |
| `FT8CompactDecodeRow.swift` | Single-line compact decode row for space-constrained display |
| `FT8BadgeViews.swift` | Achievement badges (New DXCC/State/Grid/Band/Dupe) and SNR color badge |
| `FT8AudioLevelBar.swift` | Compact EQ-style audio meter (RMS pips + peak indicator) plus decode count; tap-to-expand debug panel |
| `FT8SessionSummaryToast.swift` | Session summary toast showing band, duration, and QSO count on stop |

## Views - CW Transcription (`swift/ios/CarrierWave/Views/CWTranscription/`)
| File | Purpose |
|------|---------|
| `CWTranscriptionView.swift` | Main CW transcription container with controls |
| `CWSettingsMenu.swift` | Settings menu for WPM, frequency, and signal options |
| `CWWaveformView.swift` | Real-time audio waveform visualization, includes CWLevelMeter |
| `CWTranscriptView.swift` | Decoded text display with timestamps |
| `CWDetectedCallsignBar.swift` | Detected callsign display with "Use" button, highlighted text |
| `CWChatView.swift` | Chat-style conversation display with message bubbles |
| `CWMessageBubble.swift` | Individual message bubble for chat view |
| `CWCallsignInfoCard.swift` | Callsign info display card and chip components |

## Views - Tune In (`swift/ios/CarrierWave/Views/TuneIn/`)
| File | Purpose |
|------|---------|
| `TuneInMiniPlayerView.swift` | Persistent mini player bar above tab bar (collapsed state with live indicator, mute, close) |
| `TuneInExpandedPlayerView.swift` | Full expanded player sheet with receiver details, audio level, CW transcript, clip bookmark, action buttons |
| `TuneInExpandedPlayerView+SmartFeatures.swift` | Smart feature UI: QSY alert banner, receiver suggestion banner, follow activator button |
| `TuneInCellularAlert.swift` | Cellular data warning alert modifier for first-time use on cellular |
| `TuneInStrategySheet.swift` | Strategy selection confirmation dialog modifier for receiver selection approach |

## Views - DXpeditions (`swift/ios/CarrierWave/Views/DXpeditions/`)
| File | Purpose |
|------|---------|
| `DXpeditionsView.swift` | Main DXpeditions list with month navigation |
| `DXpeditionRow.swift` | DXpedition row with callsign, entity, activity bar |
| `DXpeditionDetailView.swift` | Detail view with day grid and expedition info |

## Views - Explore (`swift/ios/CarrierWave/Views/Explore/`)
| File | Purpose |
|------|---------|
| `ExploreFeature.swift` | Curated catalog model for the feature gallery (pitch, find-it hint, optional experiment gate) |
| `ExploreView.swift` | Feature gallery — single front door for marquee features with inline opt-in toggles for hidden experiments; reached from More tab and Getting Started card |

## Views - Dashboard (`swift/ios/CarrierWave/Views/Dashboard/`)
| File | Purpose |
|------|---------|
| `ActivityGridView.swift` | GitHub-style activity grid with horizontal scrolling; cells push to `DaySummaryView` on tap, long-press shows date/count peek. cells are the shared `ActivityGridCell` (CarrierWaveData) — green activation, blue hunter, purple AMT practice |
| `DaySummaryView.swift` | Unified day-of-activity screen reached from `ActivityGrid` tap and `RecentQSOsSection` "See All". Hero, insights carousel, band timeline, session cards |
| `DaySummaryView+Insights.swift` | Swipeable insights carousel for the day summary: tappable map preview and US states mosaic |
| `DaySummaryView+Sessions.swift` | Session cards section: rich cards for time-bounded sessions (drill-in to SessionDetailView), inline-expand cards for hunter log and loose QSOs |
| `DashboardView.swift` | Main dashboard with stats grid and services list |
| `DashboardLayout.swift` | Dashboard section/card enums, layout preferences, CollapsibleDashboardSection |
| `DashboardCustomizeSheet.swift` | Sheet for toggling individual card visibility |
| `DashboardView+Actions.swift` | Dashboard action handlers (sync, clear data) |
| `DashboardView+Repairs.swift` | One-time backfill and repair jobs (WPM, conditions, park refs, K-index) |
| `DashboardView+Services.swift` | Services list builder and detail sheet builders |
| `DashboardView+Stats.swift` | Stats grid and streak row components |
| `DashboardView+Needs.swift` | Smart spots dashboard card data loading and recompute triggers |
| `NeedsDashboardCard.swift` | Dashboard card with DXCC/WAS progress pills and needs on-air summary |
| `POTAAwardsDashboardCard.swift` | POTA awards summary card for dashboard (unique parks progress) |
| `BandOpeningsCard.swift` | Dashboard card showing HF band propagation conditions (day/night per band group from HamQSL) |
| `DXpeditionsCard.swift` | Dashboard card showing active DXpeditions with "See All" link |
| `HomeHeroCard.swift` | State-driven next-action hero pinned to the top of Home (resume open session / Start Session + Hunt Spots tiles, role-aware ordering) |
| `OnAirCard.swift` | Unified "On Air Now" dashboard card combining conditions, DXpeditions, and contests; spots condense to a one-line count summary (full rows on the sheet) |
| `OnAirSheet.swift` | Expanded sheet for the On Air card with full conditions, DXpeditions, contests, and band conditions |
| `DashboardIsolatedCards.swift` | Observation-isolated card wrappers (ActivityCardContent, StatsSummaryGrid, FavoritesCardWrapper, WASCardWrapper, LazyStatDetailView) |
| `DashboardHelperViews.swift` | Reusable dashboard components (StatBox, StatBoxDeferred, MetricsCard, LazyStreakDetailView) |
| `QSOStatistics.swift` | QSO statistics calculations (entities, grids, bands, parks, frequencies) |
| `QSOStatistics+Streaks.swift` | Streak calculation extensions for QSOStatistics |
| `AsyncQSOStatistics.swift` | Progressive stats computation wrapper with cooperative yielding |
| `AsyncQSOStatistics+Apply.swift` | Apply computed stats to observable properties and widget data |
| `AsyncQSOStatistics+Pipeline.swift` | Build per-category filter pipelines showing intermediate counts for "What's This?" sheets |
| `AsyncServicePresenceCounts.swift` | Background computation of service presence counts |
| `StatsComputationActor.swift` | Background actor for QSO statistics computation |
| `StatsComputationActor+Extensions.swift` | Extensions for activations, streaks, and count metrics |
| `SinglePassAccumulator.swift` | Single-pass accumulator for basic counts, favorites, and WAS |
| `ServiceListView.swift` | Vertical stacked service list with status indicators |
| `SyncProgressCard.swift` | Per-service sync progress card shown during sync |
| `ServiceDetailSheet.swift` | Service detail sheet for tap-through actions |
| `SyncReportViews.swift` | Sync report header, stat chips, status badge, step row |
| `SyncFunnelDetailView.swift` | Expandable sync funnel timeline, reconciliation, warnings |
| `AggregateSyncReportSheet.swift` | Combined sync results sheet with aggregate diamond funnel (new vs enriched) and per-service breakdown |
| `StatDetailView.swift` | Drilldown view for stat categories |
| `StatItemRow.swift` | Individual stat row with expandable QSOs and report inaccuracy context menu |
| `StatsReportBuilder.swift` | Background actor that builds diagnostic bundles for stats accuracy reports |
| `StatsReportBuilder+Trace.swift` | Filter trace logic for stats report builder (per-QSO decision log) |
| `ReportInaccuracyView.swift` | SwiftUI form for reporting stats inaccuracies with diagnostic bundle generation (reached from award screens only) |
| `StatExplanationSheet.swift` | Sheet view presenting structured "What's This?" methodology for stats and awards (single explanation surface) |
| `StreakDetailView.swift` | Streak statistics detail view with mode/band breakdowns + the Another Morse Trainer practice streak (or a connect link) |
| `EquipmentStatsActor.swift` | Background actor for equipment usage stats from LoggingSession data |
| `AsyncEquipmentStats.swift` | Observable wrapper for equipment stats with background computation |
| `AsyncBragSheetStats.swift` | Observable wrapper routing brag stats through the shared Rust `BragSheetApi` (catalog/config/compute); lean snapshot fetch feeds only the share map + statistician section |
| `DashboardView+BragSheet.swift` | Dashboard entry card with NavigationLink to brag sheet |
| `EquipmentUsageCard.swift` | Dashboard card showing top equipment, QSO magnet, combos, gathering dust |
| `EquipmentDetailView.swift` | Sortable equipment ranking drilldown with category filtering |
| `FriendsOnAirCard.swift` | Dashboard card showing friends in current POTA spots |
| `FriendActivityCard.swift` | Dashboard card showing recent friend activity feed items |
| `DashboardView+GridTracker.swift` | Grid tracker dashboard card with NavigationLink to detail view |

## Views - Grid Tracker (`swift/ios/CarrierWave/Views/GridTracker/`)
| File | Purpose |
|------|---------|
| `GridTrackerCard.swift` | Dashboard card with mini Maidenhead heatmap and grid counts |
| `GridTrackerDetailView.swift` | Full grid tracker view with stats, interactive heatmap, and worked grid list |
| `GridHeatmapView.swift` | Canvas-based Maidenhead grid heatmap (compact and full variants) |

## Views - Brag Sheet (`swift/ios/CarrierWave/Views/BragSheet/`)
| File | Purpose |
|------|---------|
| `BragSheetView.swift` | Main brag sheet view with period picker, hero section, stat grid |
| `BragSheetView+HeroSection.swift` | Hero cards (up to 4) with BragHeroCard component |
| `BragSheetView+StatGrid.swift` | 2-column grid of stat cells with BragStatGridCell component |
| `BragSheetStatRendering.swift` | BragInlineTableCell for bandTable/modeStreakList (over `FfiBragStatValue`) |
| `BragSheetIcons.swift` | iconKey→SF Symbol mapping + `FfiBragStatValue` hero/subtitle display helpers (host-side, unit-preference aware) |
| `BragSheetPeriodDisplay.swift` | `FfiBragPeriod` display names + UTC windowing (share snapshot filtering + period label) |
| `BragSheetConfigMigration.swift` | One-time migration of the legacy UserDefaults brag config into cw-store kv via `importLegacyConfig` |
| `BragSheetCustomizeView.swift` | Customization sheet with preset chips and category-grouped stat toggles |
| `BragSheetCustomizeView+StatRow.swift` | Individual stat row with enable toggle and hero star button |
| `BragSheetShareCardView.swift` | Share card view for brag sheet with dark purple gradient, map, stats grid |
| `BragSheetShareRenderer.swift` | Renders brag sheet share card to UIImage; custom styles via the Rust `renderShareMap` FFI (`ShareMapFFIRenderer`), adaptive/flat/globe via MKMapSnapshotter |
| `BragSheetShareRenderer+Drawing.swift` | Drawing helpers for the MKMapSnapshotter brag sheet map: grid lines, trace lines, dot markers, day/night terminator |
| `BragSheetStatisticianSection.swift` | Professional Statistician Mode section with box plots and distributions |

## Views - Logs (`swift/ios/CarrierWave/Views/Logs/`)
| File | Purpose |
|------|---------|
| `LogsContainerView.swift` | Container for QSOs list (sessions moved to Sessions tab) |
| `ADIFImportModifier.swift` | ViewModifier for ADIF file import via system file picker |
| `LogsListView.swift` | Searchable/filterable QSO list content (renders `QSORowSnapshot` via `LogbookSnapshotSource`) |
| `LogsListView+Toolbar.swift` | Toolbar menu extracted from LogsListView (import, scan, search help, quick filters) |
| `LogsListHelperViews.swift` | Helper views (QueryWarningBanner, QueryHelpSheet) |
| `QSORow.swift` | Logbook row cell + ServicePresenceBadge, rendered from `QSORowSnapshot` |
| `LogbookSnapshotSource.swift` | Protocol + SwiftData/Rust impls supplying `[QSORowSnapshot]`, routed by `cwStoreQSOMode` |
| `QSORowSnapshot+FromQSO.swift` | App-target mapper: live `QSO` → `QSORowSnapshot` (incl. presence summary) |
| `LogbookIDBridge.swift` | Bridges snapshot id → live `QSO` for writes/detail; `QSODetailLoader` |
| `LogsListDataLoading.swift` | Source-driven load/query/pagination + read-after-write drain barrier |
| `LogsListDateSections.swift` | Date section grouping (DateSection, DateSectionHeader) for the QSO list |
| `LogsQuickFilterChips.swift` | Horizontal quick filter chip bar (QuickFilter, QuickFilterChipsView) |
| `QSODetailView.swift` | QSO detail view showing all metadata, sync status, and source info with edit button |
| `QSODetailView+Map.swift` | Point-to-point map section showing geodesic arc between operator and contacted station |
| `QSOEditSheet.swift` | Edit sheet for modifying QSO fields (callsign, band, mode, RST, location, notes) |
| `LogsListView+BulkDelete.swift` | Bulk-delete bar and selection-mode actions extracted from LogsListView |
| `LogsListView+GroupSession.swift` | Groups selected QSOs into a new completed LoggingSession (summary + session creation) |
| `GroupIntoSessionSheet.swift` | Sheet for creating a completed LoggingSession from selected log QSOs (activation type, references, callsign, title) |

## Views - Import (`swift/ios/CarrierWave/Views/Import/`)
| File | Purpose |
|------|---------|
| `LogScannerView.swift` | UIViewControllerRepresentable wrapping VNDocumentCameraViewController |
| `LogScanImportView.swift` | Coordinator view: camera → config → OCR → review → import flow |
| `ScanConfigSheet.swift` | Pre-scan config: RST order, default date, callsign |
| `ScanReviewView.swift` | Review table with confidence indicators and per-row editing |

## Views - POTA Activations (`swift/ios/CarrierWave/Views/POTAActivations/`)
| File | Purpose |
|------|---------|
| `POTAAwardsHelperViews.swift` | Reusable stat pill, progress row, and completed row components for awards |
| `POTAAwardsView.swift` | POTA activator awards progress view with 8 award categories |
| `WAS250Section.swift` | ARRL America 250 WAS award section with state grid and Triple Play progress |
| `POTAActivationsView.swift` | POTA activations grouped by park with upload |
| `POTAActivationsView+Actions.swift` | Actions extension (upload, reject, share, subviews) |
| `POTAActivationsView+Helpers.swift` | Session edit application, callsign updates, session lookup, bounded batched ActivationMetadata lookup load |
| `POTAActivationsHelperViews.swift` | Helper views for POTA activations (ActivationRow, sheets) |
| `POTAActivationsBulkActions.swift` | Bulk action components (multi-select, upload/reject/export toolbar, progress banner) |
| `BulkADIFExportSheet.swift` | Bulk ADIF export UI: Combined vs Split-by-Park mode (one ADIF per park) |
| `BulkADIFExportSheet+Split.swift` | Bulk split-export helpers: park-split config builder + multi-file share |
| `POTAActivationLabel.swift` | Shared activation label view (date, park, status, metadata) |
| `POTAJobViews.swift` | POTA job display components (POTAJobRow, POTAJobDetailSheet) |
| `QSOTimelineView.swift` | Horizontal timeline bar showing QSO timing during activations (compact + share card variants) |
| `QSOTimelineLayout.swift` | Timeline layout engine: segments, gap detection, x-position computation, band colors |
| `POTALogEntryRow.swift` | Individual POTA log entry display (legacy) |
| `ActivationConditionsComponents.swift` | Compact solar gauge and weather badge components for activation rows |
| `ActivationConditionsSheet.swift` | Detail sheet showing full solar/weather conditions for an activation |
| `ActivationMetadataEditSheet.swift` | Thin wrapper bridging activation editing to SessionMetadataEditSheet |
| `ActivationShareCardView.swift` | Shareable activation card with map and stats |
| `ActivationShareCardComponents.swift` | Reusable component views for share cards (header, footer, stats, park info) |
| `ActivationSharePreviewSheet.swift` | Share preview sheet with ShareLink and Save to Photos; displayed image is state so Share/Save export exactly what's shown |
| `ActivationSharePreviewSheet+Refresh.swift` | On open, retries `repairMissingGrids` for contacts without a grid and re-renders via `SharePreviewData.rerender`; also re-renders on `.didRepairQSOGrids` (CAR-135) |
| `ActivationShareRenderer.swift` | Render activation card to UIImage for sharing; map resolved at render time via `ActivationShareMapResolver`, tile fetch through injectable `ShareMapSnapshotProvider`, falls back to `ActivationShareOfflineMap` when imagery is unavailable |
| `ActivationShareMapResolver.swift` | `nonisolated` fallback chain for contact coordinates (grid → their park → their summit → DXCC centroid → "N contacts without location"); value-typed `ActivationShareContact` snapshot of a QSO |
| `ActivationShareOfflineMap.swift` | Deterministic CoreGraphics fallback map (purple gradient, graticule, RST-coloured great-circle traces, pins, "Map imagery unavailable offline" caption) at the same 368×200 size as the tile map |
| `ShareMapSnapshotProvider.swift` | Injectable seam around `MKMapSnapshotter` for the share card: production provider with an 8 s timeout, `.unavailable` for offline/tests |
| `ShareCardStatisticianSection.swift` | Extra brag sheet section for Professional Statistician Mode (box plot, badges, distributions) |
| `ActivationStatsChartsView.swift` | Swift Charts for activation detail (band distribution, QSO rate, distance histogram) |
| `ActivationStatsSummaryView.swift` | Two-column stats summary grid for activation detail |
| `ADIFExportSheet.swift` | ADIF export sheet with share, save, copy options |
| `ActivationMapHelpers.swift` | Map utilities for activation share cards (region/bounds, geodesic paths — delegated to Rust `mapBoundsFor`/`greatCircleArc`) and activation stats helper (`computeMapStatistics`) |
| `ActivationMapView.swift` | Full-screen activation map with RST-based contact coloring |
| `ActivationMapComponents.swift` | RST coloring helpers, annotation/marker views, QSO callout |
| `ShareableImage.swift` | Transferable wrapper for UIImage sharing |

## Views - Activity Log (`swift/ios/CarrierWave/Views/ActivityLog/`)
| File | Purpose |
|------|---------|
| `ActivityLogView.swift` | Main activity log view (spots, quick log, recent QSOs) |
| `HunterPanelOverlays.swift` | `HunterPanelState` + bottom-anchored RBN / Solar / Weather / Map panels for the Hunter Log's command row (`CommandRowItem.hunterLogItems`), reusing the activation logger's panel views without a session |
| `ActivityLogCard.swift` | Dashboard card component (setup prompt or active stats) |
| `ActivityLogHeader.swift` | Daily counter bar and station profile banner |
| `ActivityLogSetupSheet.swift` | Initial activity log setup sheet (name, callsign, profile) |
| `ActivityLogSettingsView.swift` | Activity log settings (profiles, upload, daily goal) |
| `ActivityLogSpotsList.swift` | Hunter spot list container with worked-before checking |
| `ActivityLogSpotsList+Clubs.swift` | Club member spot grouping and section headers for hunter log |
| `ActivityLogSpotsList+Spotting.swift` | No-log "Spot" action from long-press menu: POTA respot with cooldown bypass alert |
| `ActivityLogSpotsList+UnreadDivider.swift` | `sortedSpots` ordering + the "N new since you looked" divider helpers for the Hunter Log spot list |
| `ActivityLogSpotRow.swift` | Individual spot row: frequency / callsign / source-info / memberships / status |
| `ActivityLogSpotRow+Badges.swift` | Spot row badge helpers (age column, NEW DXCC, state pill, dupe/worked badges) |
| `SpotLogSheet.swift` | Half-sheet for logging a QSO from a tapped spot |
| `SpotFilterBar.swift` | Horizontal scrolling filter chips for spot list |
| `SpotFilterSheet.swift` | Full filter sheet (source, saved-query filter, band, mode, toggles); defines `SpotFilters` incl. `savedQueryID` |
| `SpotFilterSheet+SavedQuery.swift` | "Filter by Saved Query" section — engine band-scope query selection (mirrors Sweep's `bandScopeFilterMode`) |
| `QuickLogSection.swift` | Manual callsign entry section with quick entry parsing |
| `QuickLogSection+Lookup.swift` | Callsign lookup logic for hunter quick log (single + multi-callsign concurrent) |
| `RecentQSOsSection.swift` | Recent QSOs list for today |
| `NeedBadge.swift` | Color-coded need badge and badge row (up to 3 badges per spot) |
| `NeedsSummaryCard.swift` | Banner showing needs-on-air count and summary text |
| `NeedsManagementView.swift` | Auto-detected and custom needs list with HamAlert export entry point |
| `AddCustomNeedSheet.swift` | Sheet for creating user-defined needs (callsign, state, park patterns) |
| `HamAlertExportSheet.swift` | Confirmation and export UI for pushing needs to HamAlert |
| `StationProfilePicker.swift` | Station profile selection sheet |
| `AddEditProfileSheet.swift` | Station profile add/edit form |
| `BandTimelineView.swift` | Horizontal band timeline showing activity segments |
| `ActivityShareCardView.swift` | Daily activity share card using ShareCardContent |

## Views - Activity (`swift/ios/CarrierWave/Views/Activity/`)
| File | Purpose |
|------|---------|
| `ActivityView.swift` | Main activity tab with community section and activity feed |
| `ActivityGrouping.swift` | Groups consecutive same-callsign activity items within time windows |
| `ActivityItemRow.swift` | Individual activity feed item display |
| `ConsolidatedActivityRow.swift` | Consolidated/expandable row for grouped activity feed items |
| `SessionBragSheetCard.swift` | Full brag sheet card for completed sessions in activity feed (map, stats, timeline) |
| `SessionBragSheetCard+Components.swift` | Map, stats, equipment, and footer sections for session brag sheet card |
| `FilterBar.swift` | Feed filter chips (All/Friends) |
| `FriendsListView.swift` | Friends list with inline search, pending requests, suggestions, and invite links |
| `FriendsListView+Rows.swift` | Friend row components (IncomingRequestRow, OutgoingRequestRow, FriendRow, InviteLinkSheet) |
| `FriendSuggestionsSection.swift` | Friend suggestion rows with Add/Dismiss actions |
| `FriendSearchView.swift` | Standalone friend search (SearchResultRow shared component) |
| `ClubsListView.swift` | List of clubs user belongs to |
| `ClubDetailView.swift` | Club detail with segmented tabs (Members/Activity/Map), status dots, MemberRow |
| `ClubActivityView.swift` | Paginated club activity feed using FeedItemDTO |
| `ClubMapView.swift` | Club member map — grid-first pins from `lastGrid`, refined via `QrzApi.locate`; clustered pins, loading overlay |
| `ClubMapAnnotationViews.swift` | MKAnnotation/MKAnnotationView subclasses for member pins and clusters |
| `ClubStatsView.swift` | Club stats section (member count, on-air, recently active, grids) |
| `ClubSpotsSectionHeader.swift` | Shared sticky section header for club member spots in POTA/hunter log lists |
| `CommunityFeaturesPromptSheet.swift` | One-time prompt for existing users to opt into community features |
| `ShareCardView.swift` | Branded share card templates |
| `ShareCardRenderer.swift` | Render share cards to UIImage |
| `SummaryCardSheet.swift` | Configure and generate summary cards |

## Views - Callsign (`swift/ios/CarrierWave/Views/Callsign/`)
| File | Purpose |
|------|---------|
| `CallsignHistoryView.swift` | Unified callsign history page — identity, QSOs, recordings, friend activity |
| `CallsignHistoryHeader.swift` | Thin wrapper that hands callsign + lookup info + friendship to the canonical IdentityCard |
| `CallsignStatsRow.swift` | Three-column stats grid (QSO count, bands, recorded time) |
| `CallsignMapSection.swift` | Compact map showing station's grid location with distance/bearing |
| `CallsignBandModeChart.swift` | Horizontal bar chart of QSO distribution by band/mode |
| `CallsignQSOTimeline.swift` | Chronological QSO list with inline recording clips |
| `CallsignQSORow.swift` | Individual QSO row with band/mode badges, frequency, RST, park ref |
| `CallsignTuneInRecordings.swift` | Tune In recordings section (WebSDR recordings of this station) |
| `CallsignActivitySection.swift` | Friend activity feed section |
| `CallsignNotesSection.swift` | Polo notes and callsign annotations display |
| `QSORecordingClipLoader.swift` | Service to find recording clips for QSOs via DetectedQSORange |
| `QSORecordingClipView.swift` | Inline recording clip player widget |

## Views - Tour (`swift/ios/CarrierWave/Views/Tour/`)
| File | Purpose |
|------|---------|
| `TourSheetView.swift` | Reusable bottom sheet component for tour screens |
| `IntroTourView.swift` | Intro tour flow coordinator |
| `IntroTourStepViews.swift` | Individual step content views for intro tour |
| `MiniTourContent.swift` | Content definitions for all mini-tours |
| `MiniTourModifier.swift` | View modifier for easy mini-tour integration |
| `LoggerTourManager.swift` | Interactive logger tour state machine |
| `LoggerTourMockData.swift` | Mock data structs for interactive logger tour |
| `LoggerTourOverlay.swift` | Full-screen overlay for interactive logger tour |
| `TourGuideBubble.swift` | KI5GTR tour guide speech bubble component |
| `OnboardingView.swift` | Onboarding view (main layout, navigation, primary button) |
| `OnboardingView+Steps.swift` | Step content views (callsign, lookup result, operator role) |
| `OnboardingView+Actions.swift` | Helper views (profile grid, service card) and actions (lookup, save, role persistence) |

## Views - Settings (`swift/ios/CarrierWave/Views/Settings/`)
| File | Purpose |
|------|---------|
| `SettingsView.swift` | Main settings navigation with search integration |
| `SettingsView+Sections.swift` | Settings list sections (profile, general, developer, about) |
| `SettingsView+Search.swift` | Search destination navigation handlers |
| `SettingsHelperTypes.swift` | Helper types (ExportedFile, DatabaseExporter, ShareSheet) |
| `SettingsSearchDestination.swift` | `SettingsSearchDestination` enum — every screen Settings search can open (split out of `SettingsSearchItem.swift` for file length) |
| `SettingsSearchItem.swift` | Search item model and static search index |
| `SettingsSearchResultsView.swift` | Search results list component with NavigationLink rows |
| `TabConfigurationView.swift` | Tab bar / sidebar ordering and visibility configuration |
| `AllHiddenQSOsView.swift` | View and restore hidden (deleted) QSOs |
| `AppearanceSettingsView.swift` | Tab bar, dashboard metrics, appearance, units settings |
| `HuntFilterSettingsView.swift` | Persistent HUNT filter settings (activity, band, mode, clubs, friends) |
| `HuntSettingsView.swift` | Persistent preferences for HUNT and P2P spot panels (age, activity, clubs, friends) |
| `P2PFilterSettingsView.swift` | Persistent P2P filter settings (band, mode) + P2PFilterSheet |
| `LoggerDetailSettingsView.swift` | Logger + activity log settings |
| `LoggerDetailSettingsView+Other.swift` | WebSDR + Hunter Log sections extracted to keep parent struct under SwiftLint type_body cap |
| `POTAActivationSettingsView.swift` | POTA activation toggles (auto-spot, conditions, statistician) |
| `SyncSourcesSettingsView.swift` | Standalone sync sources list wrapping SyncSourcesSection |
| `DataToolsSettingsView.swift` | Data management (callbook, notes, external data, export) + deduplication |
| `NeedsSettingsView.swift` | Smart spot notification controls, tracking toggles, HamAlert credential management |
| `FullADIFExportSheet.swift` | Full QSO log ADIF export sheet with progress bar and share/save/clipboard |
| `FullQSONExportSheet.swift` | Full QSO log QSON export sheet with progress bar and share/save/clipboard |
| `AboutMeView.swift` | User profile page (card-based layout: identity hero, badges strip, club numbers, actions) |
| `AboutMeView+ProfileDisplay.swift` | Thin wrapper that hands UserProfile to the canonical IdentityCard; also defines noProfileCard |
| `AboutMeView+BadgesStrip.swift` | Thin wrapper that hands the operator's callsign to the canonical BadgesStripCard |
| `AboutMeView+ClubNumbers.swift` | Club Numbers card (SKCC + per-club editable monospaced number fields) |
| `AboutMeView+ActionsCard.swift` | Refresh from HamDB + inline Change Callsign card (presents CallsignChangeGuideView on change) |
| `CallsignChangeGuideView.swift` | Post-callsign-change checklist: per-service rows with auto-verified checkmarks, settings deep links, and external service links |
| `OperatorRolePickerRow.swift` | Inline operating-style picker row (extracted from SettingsView+Sections) |
| `EditProfileSheet.swift` | Modal editor sheet for local UserProfile fields (name, location, grid, license class) |
| `ServiceSettingsViews.swift` | QRZ/LoFi auth configuration |
| `POTASettingsView.swift` | POTA account credentials + verify-only login ("Verified" checkmark) |
| `CloudSettingsViews.swift` | LoFi settings (iCloud ADIF folder monitoring moved to CloudSyncSettingsView) |
| `CloudSyncSettingsView.swift` | iCloud QSO sync toggle, status, account info, ADIF import folder |
| `CloudSyncSettingsView+Activity.swift` | Activity summary section extension (last fetch/upload, today's stats, sync log link) |
| `CloudSyncActivityView.swift` | Timeline view of recent sync events, grouped by date |
| `HAMRSSettingsView.swift` | HAMRS connection settings |
| `LoTWSettingsView.swift` | LoTW login configuration |
| `ClubLogSettingsView.swift` | Club Log connection settings (email, app password, API key) |
| `EQSLSettingsView.swift` | eQSL connection settings (username, password) |
| `TOTASettingsView.swift` | Tiles on the Air settings: API key entry, connection test, manual ADIF file upload |
| `AMTSettingsView.swift` | Another Morse Trainer: email-link sign-in (polls `AMTService`), connected account + practice streak/totals, "Show Streak on Dashboard" toggle (sets `dashboardMetric2` to `amtPractice`), sign out |
| `WsjtxSettingsView.swift` | WSJT-X listener (CAR-282): `WsjtxServicesRow` (Services row with `ExperimentalBadge(.wsjtx)` + listening dot), enable toggle, running/stopped + last error, session counts, WSJT-X status line, host/port committed on submit/blur, this phone's IPv4 addresses with copy buttons; footers explain WSJT-X → Settings → Reporting → UDP Server and the foreground-only caveat |
| `WsjtxSettingsView+Feed.swift` | Live feed section: newest-first decodes / logged / duplicate / error rows with UTC time and kind icon, Clear button |
| `ExperimentsView.swift` | Experiments hub — lists all experimental features with maturity badges and opt-in toggles |
| `ActivitiesSettingsView.swift` | Activities feature settings |
| `SMSSpottingSettingsView.swift` | SMS spot marker setup and instructions for off-grid POTA/SOTA spotting |
| `POTAAuthWebView.swift` | POTA OAuth WebView |
| `StartupProfileView.swift` | Profile viewer: startup + runtime timeline, summary, live refresh, import/share/clear |
| `ProfileTimelineChartView.swift` | Zoomable/pannable timeline chart for profiling events (Swift Charts, pinch-to-zoom, drag-to-pan) |
| `StartupProfileView+Orientation.swift` | Orientation transitions section in profile view |
| `StartupProfileView+Sections.swift` | Extracted sections: summary, milestones, detail rows, and detected hangs list |
| `SyncDebugView.swift` | Sync debugging interface |
| `SpotlightDebugView.swift` | Developer Spotlight debug view: shows `SpotlightDebugState` (phase, isAvailable, schema versions, last-run counts/elapsed/error) and exposes a "Force Full Rebuild" button. Registered explicitly in `project.pbxproj` (PBXFileReference + PBXBuildFile + Sources phase + membership exception) so Xcode Cloud picks it up without relying on synchronized-folder auto-sync |
| `PendingUploadsView.swift` | Pending upload QSOs grouped by reason, with filtering and export |
| `PendingUploadRow.swift` | Row component for a single pending QSO with reason and services |
| `PendingUploadsNavigationSection.swift` | Navigation link with badge count for Sync Sources settings |
| `UploadDiagnosticsView.swift` | User-facing upload error diagnostics with grouped issues and guidance |
| `SyncLogFilteredView.swift` | Filtered sync log with problems banner, level/service filters |
| `AttributionsView.swift` | Third-party attributions |
| `ExternalDataView.swift` | External data cache status and refresh |
| `ExternalDataView+POTASection.swift` | POTA parks cache status section |
| `ExternalDataView+SOTASection.swift` | SOTA summits cache status section |
| `ExternalDataView+SOTAZonesSection.swift` | SOTA activation-zones bulk-prefetch status section (count + pending-compute) |
| `ExternalDataView+WWFFSection.swift` | WWFF directory cache status section |
| `OperatorProfileCacheView.swift` | Status surface for offline operator-profile cache (count, watermark, manual rebuild) |
| `BugReportView.swift` | Bug report form with dpaste upload and Discord instructions |
| `CallsignAliasesSettingsView.swift` | Manage current and previous callsigns |
| `SettingsSections.swift` | Sync Sources section with service navigation links |
| `CallsignNotesSettingsView.swift` | Manage callsign notes file sources (URL + title) |
| `KeyboardRowsSettingsView.swift` | Keyboard Rows hub: toggles, reorder, pinned stack preview |
| `KeyerRowSettingsView.swift` | CW keyer row info page (auto-appear conditions, CW Messages link) |
| `KeyboardRowSettingsView.swift` | Configure number row symbols above keyboard |
| `PrefixRowSettingsView.swift` | Configure prefix hot-key row (position-local suggested / custom list) |
| `CommandRowSettingsView.swift` | Configure command row buttons above keyboard |
| `DashboardMetricsSettingsView.swift` | Configure which metrics appear on dashboard card |
| `WebSDRRecordingsView.swift` | List of all WebSDR recordings with delete, share, and details |
| `WebSDRFavoritesView.swift` | WebSDR favorites management with manual add (advanced mode) |
| `BackupSettingsView.swift` | Backup management UI (manual backup, restore list, settings) |
| `WebSDRFavoritesView+Rows.swift` | Compact row rendering for WebSDR favorites (extension) |
| `ReceiverDetailSheet.swift` | Detail sheet for a KiwiSDR receiver with favorite toggle |
| `AddReceiverSheet.swift` | Manual receiver add sheet (host:port entry with validation) |
| `RadioSettingsView.swift` | Radio device scan, selection, transport picker (BLE / WiFi / Flex / SCU-LAN10), protocol configuration |
| `RadioSettingsView+SCULAN10.swift` | Global Radio settings SCU-LAN10 section — host/port/credentials + Connect/Disconnect |
| `EquipmentBrowserView.swift` | Equipment inventory browser with category filters, add/retire/delete |
| `EquipmentItemDetailView.swift` | Equipment detail view with nickname, notes, specs, bands/modes, retire/delete |
| `EquipmentItemDetailView+Connection.swift` | Connection section for radios — summary row, sheet trigger, icon by transport |
| `RadioConnectionSheet.swift` | Per-item radio connection editor — transport/protocol pickers, BLE/Wi-Fi/Flex detail fields, "Use CW Bridge" toggle, deep-link to global Radio settings for scanning/SmartLink |
| `AddEquipmentSheet.swift` | Sheet for adding custom equipment with band/mode/portability selection |


## Views - Map (`swift/ios/CarrierWave/Views/Map/`)
| File | Purpose |
|------|---------|
| `ParkSearchMapView.swift` | Park and summit reference map with search, polygon overlays, and SOTA summit pins (SwiftUI shell around `ParkSearchMapKit`) |
| `ParkSearchMapView+Data.swift` | Data loading, boundary fetching, trail loading, and search for park/summit map |
| `ParkSearchMapView+Views.swift` | Overlay UI (selection callout with swipe-to-dismiss, search results chips, loading badge) for the park/summit map |
| `ParkSearchMapKit.swift` | `UIViewRepresentable` wrapping `MKMapView` for the park/summit map — host for park polygons, trail polylines, NEXRAD radar `MKTileOverlay`, and SwiftUI-hosted pins. Replaces SwiftUI `Map` so the radar moves in lockstep with everything else |
| `ParkSearchMapKit+Sync.swift` | Overlay subclasses (`BoundaryFillOverlay`, `BoundarySkirtOverlay`, `TrailLineOverlay`, `TrailSkirtOverlay`), MKAnnotation wrappers, SwiftUI-hosted `ParkAnnotationView`/`SummitAnnotationView`, and the diff helpers `ParkSearchMapKit.Coordinator` uses to push data into the map |
| `ParkSearchMapKit+Grids.swift` | Maidenhead grid-square (`GridLineOverlay`) and TOTA tile (`TileLineOverlay`) boundary overlays for the reference map: `MapGridGeometry` (zoom-gated, capped rectangle builder + signature) and the coordinator `syncGrids`/`syncTiles` diff helpers. Gated by `.activityLayers` |
| `ParkSearchMapKit+Admin.swift` | US state (`StateLineOverlay`) / county (`CountyLineOverlay`) outline overlays + coordinator `syncAdmin` diff helper. Gated by `.activityLayers` |
| `ParkSearchMapView+AdminBoundaries.swift` | Admin boundary loading: viewport fetch via `ParkMapApi.adminBoundariesInBox` (cache-through), county zoom-gate, merge/eviction, and the `adminBoundaries` render filter |
| `ParkSearchMapKit+SotaZones.swift` | SOTA activation-zone fill overlays (`SotaZoneFillOverlay`) + coordinator `syncSotaZones`/`zoneFillRenderer` (translucent teal polygons with holes). Gated by `.activityLayers` |
| `ParkSearchMapView+SotaZones.swift` | SOTA zone loading: viewport summit gathering, cached read via `ParkMapApi.sotaZonesFor`, merge/eviction, and the `sotaZones` render filter (zoomed-in only) |
| `ParkSearchMapKit+WWFF.swift` | WWFF overlays: `WWFFFillOverlay` (borrowed POTA polygon, magenta) + `WWFFMarkerOverlay` (diamond fallback) + coordinator `syncWWFF`/`wwffRenderer`. Gated by `.activityLayers` |
| `ParkSearchMapView+WWFF.swift` | WWFF loading: KFF reference load, viewport gathering, `KFF→US` POTA-boundary borrow via `ParkMapApi.wwffBorrowedBoundaries`, marker fallback, merge/eviction, `wwffItems` render filter |
| `MultipliersSheet.swift` | Sheet listing flagged multiplier candidates with kind badges; tap recenters the map |
| `ParkSearchMapView+Multipliers.swift` | Multiplier sheet wiring: viewport ref snapshot, `ParkMapApi.findMultipliers` scan, zoom-to-candidate |
| `MyParksView.swift` | Searchable list of parks user has activated or hunted with counts |
| `ParkPinView.swift` | Park pin and callout views (with personal activity stats) for the reference map |
| `SummitPinView.swift` | SOTA summit pin and callout views for the reference map |
| `MapContentBuilders.swift` | Shared `@MapContentBuilder` functions: geodesic arcs, QSO annotations, rove stops, my-location marker, `RoveStopMarker`, and `standardMapStyle` modifier |
| `ShareMapFFIRenderer.swift` | Host bridge onto the Rust `renderShareMap` FFI for the six custom `ShareMapStyle` themes: builds `FfiShareMapInput` from pins/clusters/traces/center, renders off-main, composites azimuthal ring-label text; `ShareMapStyle.ffiStyle` mapping + `UIColor.shareMapComponents` live here |
| `ThemedMapImage.swift` | SwiftUI view rendering a custom-style static map via `ShareMapFFIRenderer` (off-main `.task`); optional per-coordinate pin colors |
| `SessionQSOMap.swift` | Shared session QSO map with RST pins, arcs, and rove stops (used by `SessionMapPanelView` and `SidebarMapView`) |
| `QSOMapView.swift` | Main map view showing QSO locations; loads its view-model in one call via `MapApi.qsoMap` (Rust) and holds the grid-overlay/annotation/arc cache state |
| `QSOMapView+Data.swift` | Thin FFI mapping layer: `FfiMapFilter`/`FfiQsoMapAnnotation`/`FfiMapArc`/`FfiMapStats` → `QSOAnnotation`/`QSOArc`/`MapStatistics` |
| `GridSummaryLoader.swift` | Loads `GridTrackerSummary` from cw-store SQL `GROUP BY` (`RustAnalyticsReadSource.gridTiles`) — the only grid aggregation path since the SwiftData scan was removed |
| `QSOMapHelperViews.swift` | Map markers, filter sheet, callout views |
| `GridSquareOverlay.swift` | Maidenhead grid square overlay, search bar, and current grid label for the map |
| `MapFilterState.swift` | Observable filter state for map |
| `QSOAnnotation.swift` | Annotation model for map markers; `QSOArc` holds a Rust-precomputed geodesic path |
| `AzimuthalMapView.swift` | Canvas-rendered azimuthal equidistant projection with spot heatmap and antenna pattern overlay |
| `AzimuthalContainerView.swift` | Container wiring spots, QSOs, antenna selection, and compass into the azimuthal map |
| `AzimuthalContainerView+Filters.swift` | Filter pills and source toggles for the azimuthal map (band, mode, distance, antenna, QSOs, map tiles) |
| `AzimuthalStandaloneView.swift` | Standalone azimuthal view for Map tab (resolves grid via GPS, loads spots/QSOs) |
| `AzimuthalStandaloneView+Fetch.swift` | Spot fetching from RBN, POTA, SOTA, WWFF and HamDB grid enrichment |
| `AzimuthalDataProvider.swift` | Projects spots and QSOs into azimuthal coordinates, builds sector data |
| `AzimuthalTileRenderer.swift` | Background actor: MKMapSnapshotter capture + per-pixel reprojection to azimuthal equidistant CGImage |
| `AntennaType+DisplayName.swift` | Display names for antenna types (extracted from container view) |
| `DistanceOption.swift` | Distance range options for azimuthal map (regional, continental, hemispheric, global) |
| `GridOverlayRenderer.swift` | Builds Maidenhead grid square MapPolygon overlays with status-based coloring |

## Views - Recovery (`swift/ios/CarrierWave/Views/`)
| File | Purpose |
|------|---------|
| `RecoveryModeView.swift` | Full-screen recovery takeover when ContainerSetup fails — restore from backup, send diagnostics, or destructive reset |

## Views - Weather (`swift/ios/CarrierWave/Views/Weather/`)
| File | Purpose |
|------|---------|
| `WeatherRadarView.swift` | Full-screen NEXRAD radar map (MKMapView + tile overlay) with active NWS alerts banner; gated by `.weatherRadar` experiment, US-only |
| `WeatherAlertsBanner.swift` | Compact NWS alerts chip (worst severity + count) + `WeatherAlertsSheet` list view, mirroring the Space Weather chip/sheet pattern |

## Views - WhatsNew (`swift/ios/CarrierWave/Views/WhatsNew/`)
| File | Purpose |
|------|---------|
| `WhatsNewSheet.swift` | Post-update sheet presenting unseen WhatsNewEntry release notes grouped by version |

## Views - Remote (`swift/ios/CarrierWave/Views/Remote/`)

Tab UI for the iOS-as-remote-for-Sweep mode. Routed to from `ContentView.remoteTabContent` and gated by the `.remoteSweep` experimental flag.

| File | Purpose |
|------|---------|
| `RemoteSweepRootView.swift` | Top-level Remote tab; routes between discovery list, pairing form, connected experience, and error states |
| `RemoteSweepConnectedView.swift` | TabView while connected: Radio (state + tune), Scope, Waterfall, Spots (tap-to-QSY), CW (keyer pane) |
| `RemoteSweepWaterfallView.swift` | Live waterfall canvas; subscribes to the `radio.waterfall` topic only while visible; dequantizes UInt8 bins back to 0..1 floats and renders with the same color ramp as macOS |
| `RemoteSweepCWPane.swift` | Mirror of activation-log `CWKeyerRow`: WPM menu, STOP, CUSTOM text, slot buttons with long-press editor sheet bound to `cwSetSlot`; smart-disables slots whose `RemoteCWMacros.requiredMacros` aren't satisfied by the current `RemoteQSOContext` |
| `RemoteCWEntryStrip.swift` | Compact "current QSO" strip: callsign + RST + serial + exchange + lookup chip, two-way bound to a shared `RemoteQSOContext` |

## Views - Query (`swift/ios/CarrierWave/Views/Query/`)

Spot SQL editor, gated by the `.queryRunner` experimental flag and reached from the Experiments hub. A port of CW Sweep's Query Workbench over the Rust spot engine's query FFI (`run_query` / `profile_query` / `format_sql`); replaces the old read-only `QueryRunnerView` experiment.

| File | Purpose |
|------|---------|
| `SpotQueryEditorView.swift` | Monospace SQL editor with Run / Profile / Format, saved-query menu, dirty marker, schema sheet |
| `SpotQueryEditorModel.swift` | @Observable editor state: engine query execution off-main, line/col error mapping, row-limit + show-more, `.cwquery` CRUD, starter-query seeding |
| `SpotQueryResultsView.swift` | Compact label/value result rows, truncation "Show More", plus `SpotQuerySaveSheet` (name/description) |
| `StarterQueries.swift` | Verbatim port of Sweep's starter `.cwquery` set, seeded into an empty store |
| `SpotSchemaCatalog.swift` | Hand-curated table/column descriptions for the engine's scope DB (port of Sweep's `SchemaCatalog`) |
| `SpotSchemaHelpView.swift` | Static schema reference sheet (port of Sweep's `SchemaBrowserView` copy) with insert-snippet buttons |

## Views - Band Scope (`swift/ios/CarrierWave/Views/BandScope/`)

Band Scope v2 two-lens spot browser (`.bandScope` experimental flag, Experiments hub): frequency-sorted **Scope** list + recency-sorted **Heard** list, one tier color system, SQL-driven goal-profile filtering (Scope dims / Heard hides). Logic in Services/BandScope.

| File | Purpose |
|------|---------|
| `BandScopeContainerView.swift` | Root: Scope\|Heard segmented toggle (both lenses stay mounted), profile mode pill + honest `173 → 41` count, quick-toggle buttons, band menu, sheet hosting |
| `BandScopeTheme.swift` | Spec §12 palette (tier hexes, surfaces) mapped to feature-scoped tokens; SF Mono via `.monospaced` |
| `ScopeListView.swift` | Frequency lens: sticky 5 kHz headers, YOU line at sorted position, pileup expansion, freshness fade × filter dim, scroll-visibility → scrubber sync |
| `ScopeRow.swift` | Row anatomy (§8): freq/Δ column, tier dot (amber glow), callsign, WPM, one goal chip, age; `ScopeSubRow` (busted badge), `FrequencyColumn`, `TierDot`, `GoalChip`, `BandScopeAge` |
| `ScopeGapDivider.swift` | Clear-spectrum QSY affordance rows (§4) + `QSYSheet` (tune to midpoint, set anchor) |
| `ScrubberStrip.swift` | Canvas position strip (§3): tier ticks, viewport window (debounced), anchor caret, tick labels, tap-to-scroll |
| `HeardListView.swift` | Recency lens (§13): time-bucket sticky headers, unseen line, `NewSpotsPill` (merge + scroll-to-top) |
| `HeardRow.swift` | Heard row anatomy + `NeedsShelf` (pinned amber cards) + `BandFilterTiles` (per-band density strips) |
| `PeekSheet.swift` | Shared bottom sheet (§11): full chip set, heard N×, Tune (sets anchor) + Log QSO (`SpotLogSheet` reuse, refreshes anchor) |
| `GoalProfileSheet.swift` | Profile picker + minimal user-defined profile editor (§16) |


## Views - Satellites (`swift/ios/CarrierWave/Views/Satellites/`)

Live amateur-satellite map (`.satellites` experimental flag, hidden tab): SatNOGS TLEs propagated on-device with SGP4 by the shared Rust engine (`SatelliteApi` — the same engine Android runs), filtered to sats with amateur-service transmitters.

| File | Purpose |
|------|---------|
| `SatellitesRootView.swift` | Root: load/error states, 5s SGP4 sync tick, observer chain (GPS one-shot → `myGrid` → `loggerDefaultGrid`), tilt-up sky-dome trigger with hysteresis, ±12h time-scrubber slider (snaps back to live near "now"), toolbar (satellite list, upcoming passes, ellipsis menu incl. force refresh), status capsule + `SatelliteInfoCard` (selected sat incl. transmitter modes/frequencies + Az/El); ellipsis menu → "Rotator & Trackers" opens `SatelliteRotatorSheet`, "Community Activity" opens `SatelliteCommunityActivitySheet`; passes `communityStatusByNorad` + `selectedReporters` to the map and `selectedReports` + `communityActivity`/`selectedCommunityRows` to the info card (its `onOpenCommunity` opens the community sheet on that row); the info card shows a one-line orange `SatelliteRotatorService.statusLine` caption while a rotator follows |
| `SatellitesRootView+Overlays.swift` | Root's bottom-overlay chrome split out of the main file: ±12 h time scrubber (`timeOffsetLabel`, snap-back near now), status capsule (count / QTH / TLE age), and `openPointingIfPending` — the satellite list's row tap opens `AntennaPointingView` only after the list sheet has dismissed |
| `SatelliteAzimuthalMapView.swift` | Azimuthal-equidistant "great circle" chart centered on the observer QTH (replaced the MKMapView globe — MapKit force-locks camera heading north-up when zoomed out): TimelineView(20fps)+Canvas, `AzimuthalChartFrame` projection (bearing = angle, great-circle distance = radius, compass heading folded into the angle for free rotation at any scale), range rings + `CoastlineData` outlines (antipode-tear guard), selected footprint cap + ground track, dead-reckoned dots with a community ring (AMSAT last-24 h colour; none when untracked), reporter grid squares for the selected bird (`drawReporters`), tap-to-select; drag moves the HOME POINT with live tracking: each finger delta re-centers the projection (inverse azimuthal projection per gesture change) so the map follows the finger by true re-projection, never a screen translation; QTH dot projected like everything else; house recenter button while panned |
| `AzimuthalChartFrame.swift` | Azimuthal-equidistant projection math for the great-circle chart (split from the map view): forward point/ringPoint, screen-anchored compassPoint, and the inverse `coordinate(at:)` used to commit a drag as a new projection center |
| `SatelliteSkyDomeView.swift` | Attitude-driven sky dome (auto-shown when the phone reaches vertical, exits 10° below; hysteresis): `SkyProjector` pinhole-projects az/el along the back camera, TimelineView(20fps)+Canvas draws horizon/30°/60° rings, cardinals, all sats (dead-reckoned via az/el rates), dashed pass arcs (orange = selected, white = hovered via cached `skyTrack`), ~7° hover with metadata card, off-screen arrow, 5° lock-on haptic; AR toggle (persisted `satelliteSkyDomeAROverlay`) puts live camera passthrough + scrim behind the sky overlay via the pointing `PointingCameraController`/`PointingCameraPreview` |
| `SkyProjector.swift` | `SkySighting` + `SkyProjector` pinhole projection (az/el to screen along the back camera, off-axis angle, screen direction) — split from the dome view; also used by the pointing screen and its AR marker |
| `SkyDomeFooter.swift` | Sky-dome bottom overlay: hover metadata card (name/NORAD/az/el/range/alt + mode-badged transmitter lines), selected-satellite status with on-target + polarization-roll line, or select hint |
| `AntennaPointingView.swift` | Full-screen antenna-mount mode (below the horizon: no reticle, no elevation scale, AZ-only readout, pass plot) ("Point" button on `SatelliteInfoCard`, fullScreenCover): strap the phone to the boom (back camera = boresight); sky-dome theme (black bg, forced dark) with a thick semantic status frame (red/orange/green lock at <5°, blue below horizon), G1000-style compass tape + elevation deviation scale, big status-tinted left/right + up/down corrections; on lock shows Doppler-corrected downlink/uplink (from `rangeRateKmPerSec`) + ModeColors mode chip + polarization roll/circular hint; below horizon counts down the next pass and steers to the rise azimuth; keeps screen awake + runs its own 5s SGP4 sync loop (root's task cancels under the cover); `dial.medium` header button (orange while the rotator follows) opens `SatelliteRotatorSheet`; on appear relinks the saved rotator and starts `SatelliteRotatorService` feeding it targets |
| `AntennaPointingAR.swift` | AR overlay for pointing mode (toggle in the header, persisted `satellitePointingAROverlay`): `PointingCameraController` (@MainActor AVCaptureSession, back wide camera, lazy config + permission flow), `PointingCameraPreview` (AVCaptureVideoPreviewLayer representable, aspect-fill), `PointingARMarker` (satellite projected onto the camera via `SkyProjector`, orange ring/green when locked + name), `PointingARCrosshair` (fixed boresight reticle) |
| `AntennaPointingContent.swift` | Pointing-mode frame model + center content: `PointingFrame` (per-render phase, guidance errors, Doppler tuning fields), `PointingLockedContent` (ON TARGET + Doppler downlink/uplink, ModeColors chip, polarization hold), `PointingBelowHorizonContent` (next-pass countdown + rise line) |
| `AntennaPointingInstruments.swift` | Pointing-mode instruments (G1000 conventions, app theme): `PointingCompassTape` — ±45° heading-tape section (5/10/30° ticks, N/E/S/W labels, white lubber line, orange fly-to bug, hollow when clamped off-window); `PointingElevationScale` — glideslope-style vertical deviation scale (±30° window, dots at ±10/20°, orange diamond, hollow off-scale); `PointingCorrectionReadout` — giant status-tinted "◀◀ 23°" / "▲▲ 12°" numbers |
| `MutualPassPlannerSheet.swift` | Mutual-pass planner (person.2 toolbar button): station A prefilled from the observer QTH, station B accepts a grid, a callsign (resolved to the most recent `theirGrid` in the QSO log), or an accepted friend from a picker menu; `SatelliteModeCategory` chips (persisted, ≥1 always on, ordered by QSO-mode frequency with the resolved callsign) gate candidates by ACTIVE transmitter capability and re-run the search on change; station-B autocomplete chip row (see `MutualPassStationSuggest.swift`); 24h sweep → `MutualPassRow` list (matching transmitter mode badge + downlink, window, minutes together, color-graded limiting peak + you/them peaks) → navigationDestination to the profile view |
| `MutualPassStationSuggest.swift` | Station-B autocomplete for the planner (debounced 200ms): `StationSuggestion` chips filtered by the typed text — matching friends first (yellow, person icon; prefix beats substring), then distinct recent callsigns from the QSO log (bounded fetch, `starts(with:)` predicate); hides for grid-shaped input; also hosts `updateModeOrder` (mode-chip ordering by per-callsign QSO history) |
| `MutualPassProfileView.swift` | Mutual-pass profile screen: `MutualProfilePlane` projects world positions onto the A–B–geocenter cross-section; summary card (times, peaks, minutes together, station separation km), animated card (12s loop) with time/per-station-elevation readout + legend; station A labeled by the operator's callsign (`CallsignAliasService`); shows a "altitude scale compressed" note for high orbits; `MutualPassTimesTable` grid below the profile shows both-rise/best/both-set in Zulu + each station's own local time (their zone via `MKReverseGeocodingRequest` off-main, longitude estimate offline) |
| `MutualPassProfileCanvas.swift` | The cross-section drawing + `ProfileProjection`: Earth surface arc with both stations (labels stagger when crowded), pass path colored by visibility (green both / orange one / dim neither), animated satellite with dashed sight lines to each visible station, live surface coverage arc; altitude log-compressed so HEO/Molniya apogees don't shrink the Earth (LEO stays ~true) |
| `MutualPassRow.swift` | One mutual window row: satellite name + matching transmitter (mode badge, downlink), window times, minutes together, color-graded limiting peak elevation + you/them peaks |
| `SatelliteCommunityActivitySheet.swift` | AMSAT community status grid ("Community Activity" in the root ellipsis menu): every AMSAT-tracked transmitter as a `CommunityActivityList` row from the engine's `communityActivity` (server histogram, 20 min cache, stale-offline footer); options menu picks 1 h / 3 h / 6 h / 1 d strip cells (persisted) and toggles favorites-only, hide-silent, in-catalog-only; a reset chip in the legend bar shows the zoomed span; favorites float to the top; rows push `CommunityTransmitterDetailView` via `navigationDestination(for: String.self)` (`initialRowID` pushes one on load, for the info card deep link); footer carries the AMSAT attribution link; `CommunityActivityStatus.color` holds AMSAT's legend colours |
| `CommunityActivityList.swift` | Phone-first vertical list: pinch anywhere zooms every strip together and a sideways drag pans them (shared `CommunityViewport` binding, vertical drags still scroll); `CommunityRowView` (name, capability tag, mode badge, enrichment line — next-pass countdown + peak in orange, "not in catalog" / "SatNOGS: inactive", own QSO count, last heard) over a `CommunityStripView` stacked-bar sparkline drawn at fractional positions for the visible slice (oldest left; bar height = reports vs the row's busiest bucket, segments heard / telemetry / not-heard) under a pinned `CommunityTimelineAxis` (UTC day ticks, hour ticks once zoomed under two days, "now" when the newest bucket is visible); `CommunityFormat` countdown/ago/MHz helpers |
| `CommunityTransmitterDetailView.swift` | One transmitter's week on Swift Charts (pushed from the list): `CommunityDetailSummary` card (down/uplink, SatNOGS active, last heard + 24 h counts, next pass, own QSOs, Show on Map), `CommunityWeekChart` (hourly stacked `BarMark`s by verdict, your passes as orange `RectangleMark` bands from `passes(for:from:to:)`, dashed "now" rule; scrollable x axis for panning, pinch zooms the visible domain between 6 h and the week, double-tap resets, hold-to-scrub via `chartXSelection` with a `CommunityHourCallout`), `CommunityHourOfDayChart` (24 UTC-hour stacked bars summed over the week); toolbar Report button opens `SatelliteCommunityReportSheet` on this row; AMSAT attribution in the last footer |
| `SatelliteCommunitySection.swift` | Community block on the selected bird's info card: dot + "heard Xm ago", a mini "Report" button (`onReport` → `SatelliteCommunityReportSheet`, hidden when AMSAT doesn't track the bird), one week sparkline per AMSAT capability row (tap → the community sheet opens straight on that row's hour-by-hour page), the previous-orbit line; untracked birds say "Not tracked on AMSAT's status page" |
| `SatelliteCommunityReportSheet.swift` | "Report to AMSAT" sheet (info-card Report button, toolbar button on `CommunityTransmitterDetailView`): transmitter picker over the bird's AMSAT rows, verdict (Heard / Telemetry Only / Not Heard; Crew Active only on the ISS crew row), observation time (last 7 days), callsign + grid prefilled from `loggerDefaultCallsign` / `myGrid` / `loggerDefaultGrid`; Submit → `SatelliteTrackerModel.submitCommunityReport` (engine POSTs to status.amsat.org, operator-initiated only), AMSAT's rejection reason in an alert, receipt alert notes a replaced quarter-hour report; `AmsatAttributionLabel` — the CC BY 4.0 "Satellite status data: AMSAT" link used under every community view |
| `CommunityDot.swift` | The community signal where the operator already looks: 8 pt dot in AMSAT's last-24 h legend colour (hollow ring = untracked by AMSAT) on upcoming-pass rows and the info card header; the map draws the same colour as a marker ring |
| `SatelliteUpcomingPassesSheet.swift` | All-sky "what's next" schedule (calendar toolbar button): every pass in the next 6h across satellites with an active transmitter, sorted by rise time — workable-only filter (peak ≥ 10°, persisted, on by default; funnel toolbar toggle + escape hatch in empty state); rows show a `CommunityDot`, name, mode badge + downlink, live countdown / in-progress with minutes left, duration, color-graded peak elevation, rise→set compass path; tap selects the satellite on the map |
| `SatellitePassListSheet.swift` | Next-passes sheet for the selected satellite ("Passes" button on `SatelliteInfoCard`): 48h `SatellitePassForecast` rows (AOS–LOS window, live countdown/in-progress, duration, color-graded peak elevation, peak range, compass azimuth path) + header with NORAD/polarization/transmitter metadata; shared workable-pass filter (peak ≥ 10°, persisted `SatelliteWorkability.workablePassFilterKey`, funnel toggle); QTH-not-set / always-visible / no-pass empty states |
| `SatelliteBearingArrow.swift` | `SatelliteHeadingSampler` (5 Hz, 2°-quantized copy of `screenHeadingDeg` — the raw 30 Hz stream reconfigured List cells mid-touch and ate first taps) + `SatelliteBearingArrow` (compass arrow toward an azimuth, counter-rotated by the sampled heading; green when the bird is up) |
| `SatellitePassArcView.swift` | `SatellitePolarFrame` (azimuth = angle from the top less a heading, elevation = radius, horizon at the rim) + the compact ISS-Detector-style pass plot: rim, 30°/60° rings, 45° spokes, cardinals, pass arc (dim behind now, dashed ahead, travel chevron, rise/set rim dots), satellite dot (live or at the rise point); pure Canvas, caller supplies clock + rotation |
| `AntennaPointingView+PassArc.swift` | Pointing screen's pass plot: `isBelowHorizon`, `passArcPlot` (below-horizon state, rotated so the boom azimuth is up like the tape), `refreshPassArc` (arc anchored to the first unset pass via `skyArc`, re-forecasts after LOS; called after the forecast loads and on the 5 s sync) |
| `SatelliteListSheet.swift` | Satellite list (`list.bullet` toolbar button, replaced the bare search sheet): every catalog bird under the shared filter chips + search, ordered up-now → next rise → no pass (24 h sweep, favorites section first), rows with primary transmitter, next-pass countdown/duration/peak or live elevation, and a `SatelliteBearingArrow` — a compass arrow toward the bird (live azimuth when up, rise azimuth otherwise) counter-rotated by `AntennaMotionService.screenHeadingDeg` so it points at the real sky; tapping a row selects the bird and (after the sheet dismisses) opens `AntennaPointingView`; swipe to favorite, context menu "Show on Map" selects only |
| `SatelliteQuickLogSheet.swift` | Post-LOS quick log ("Log" button on `SatelliteInfoCard` + "Log pass QSOs" on the pointing screen's below-horizon state): satellite/transmitter/mode/time prefilled, N rows of callsign + grid (auto-appending, per-row time override), forced SAT_NAME + PROP_MODE=SAT; saves via `SatelliteQuickLogService` |
| `SatelliteAlertSettingsSheet.swift` | Pass-alert settings (bell button on the satellites tab): master toggle, lead-time picker, marginal opt-in, notification-permission state + Open Settings link, favorites list with unstar |
| `NextPassesStrip.swift` | Compact "next workable passes" chips (favorites first, ≥20° peak, max 3) in the root bottom overlay above the time scrubber; tap selects the bird |
| `SatellitePassPlaybackView.swift` | Pass-audio playback inside the quick-log sheet: play/pause + scrubber + one chip per tap mark (tap rewinds 5 s before the mark to re-copy the exchange) |
| `SatelliteDuplexSheet.swift` | Two-radio FM duplex sheet (antenna button in the pointing header, orange while tuning): per-role `RadioLinkSection` bridge picker (scan/bind/connect/forget, detected radio), swap roles, Auto vs Manual-downlink Doppler picker, per-satellite uplink CTCSS field, Start/Stop tuning + live predicted/sent/radio-readback frequencies, operator correction, Doppler shift, link errors |
| `TrackerDetectedAlert.swift` | `.trackerDetectedAlert(model:)` (root + pointing views): "CSN S.A.T. detected — Connect?" from `SatelliteRotatorService.autoDetect.pending` with Connect / Not Now / Ignore This Device |
| `RotatorStatusChip.swift` | Logger-style rotator chip ("PSR-100 · 207°/0°", green tracking / blue linked / red error) in the Satellites map header (tap → Rotator & Trackers sheet) and the sky-view header |
| `RotatorPointTrackButton.swift` | Sky-dome "Point & Track" capsule (rotator linked + satellite selected): slews the rotor to the satellite (or rise azimuth) and turns Follow on; shows commanded az/el while tracking, tap again to stop |
| `RotatorManualControls.swift` | Hand controls for a linked rotator (Manual control section of the rotator sheet): Commanded (from taps) vs Satellite target lines with Go to satellite, 1°/5°/15° step picker, jog pad (`RotatorController.nudge`, hold to repeat, commanded shown under reported), go-to AZ/EL, Park, Stop, last sent command + reply; any manual move leaves follow mode |
| `SatelliteRotatorSheet.swift` | Rotator & trackers sheet (`dial.medium` button in the pointing header, "Rotator & Trackers" in the root ellipsis menu): "Trackers on this network" LAN sweep via `TrackerDiscoveryService` (scan button + progress, swept subnets/last-scan footer, errors), one row per `DiscoveredTracker` (name, detail, kind chip, Connect / linked check), manual add by IP + kind picker (S.A.T. / PSR-100 / rotctld); "Rotator" section over `RotatorController` (unit, protocol, state, reported vs target az/el, pointing error, Follow toggle, Park/Stop, min-elevation stepper, web-UI `Link`, Disconnect / Forget, reconnect-saved) — all through `SatelliteRotatorService.shared`  Target row shows the desired pointing + its source (satellite above horizon / waiting at rise azimuth / select a satellite) even before a rotator is linked|
| `AntennaPointingView+Capture.swift` | Pointing screen's P3 capture surface: REC PASS button, giant in-recording MARK button + stop + elapsed, and the post-LOS quick-log button/sheet (split out for the 500-line file limit) |
