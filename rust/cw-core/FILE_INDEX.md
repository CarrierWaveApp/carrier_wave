# cw-core File Index (`rust/cw-core/`)

Portable Rust core (Phase 0+ of the Rust migration). See `README.md` for crate
overview and `../../docs/plans/2026-06-13-rust-core-migration.md` for the plan.

## Workspace

| File | Purpose |
|------|---------|
| `Cargo.toml` | Workspace manifest + shared dependency versions |
| `README.md` | Crate overview, build/test, durability-test commands, status |
| `CLAUDE.md` | Component conventions (no `cargo fmt`; build+clippy+test gate) + pointers |
| `cw-web-crypto/` | **Own workspace** (wasm32-only getrandom `js` feature) — wasm-bindgen crate for the logbook web viewer: `src/lib.rs` (escrow open + blob seal/decrypt), `src/logbook.rs` (`LogbookIndex` query engine), `src/sdr.rs` (KiwiSDR decoder/handshake/tune/directory/ranking over `cw-domain::kiwisdr`). Built with `wasm-pack build --target web`, pkg vendored into `server/logbook-web/vendor/cw-web-crypto/` |

## cw-domain (`cw-domain/src/`)

| File | Purpose |
|------|---------|
| `lib.rs` | Crate root, re-exports |
| `service_type.rs` | `ServiceType`/`SyncMode` — port of `ServiceType.swift` |
| `band.rs` | `BandUtilities` — band derivation / ranges, port of `BandUtilities.swift` |
| `band_plan.rs` | US FCC band segments + per-region calling-frequency tables — port of `BandPlan.swift` + `BandPlan+Frequencies.swift` |
| `iaru_region.rs` | IARU Region 1/2/3 enum + coordinate-driven detection — port of `IARURegion.swift` |
| `location_prefix.rs` | DXCC entity table (id + name + primary prefix + lat/lon, ~155 entries) + nearest-neighbor lookup + longest-primary-prefix matcher — port of `LocationPrefixLookup*.swift` |
| `mode.rs` | `ModeEquivalence`/`ModeFamily` + `is_metadata_mode`/`METADATA_MODES` (WEATHER/SOLAR/NOTE) — port of `ModeEquivalence.swift` + `QSOMode.isMetadata` |
| `hunter_log.rs` | Hunter-log pure helpers: `band_mode_park_key` (worked-before dedup key) + `derive_dxcc` (callsign/grid → DXCC entity) — ports `WorkedBeforeCache.bandModeParkKey` + `ActivityLogManager+FT8QSOLogger` DXCC head |
| `maidenhead.rs` | Grid↔coordinate, distance, bearing, tile bounds, TOTA tile-rect region scan (`tota_tiles_in_region`) — port of `MaidenheadConverter.swift` + `MapGridGeometry.tileRects`/`indexBounds` (`ParkSearchMapKit+Grids.swift`) |
| `quick_entry.rs` | Logger quick-entry grammar (callsign + RST/grid/park/freq/state/mode/time tokens, multi-callsign, color-coded preview tokens) — port of `QuickEntryParser.swift`; reuses `fmt::parse_frequency`; canonical parity tests live here |
| `continent.rs` | DXCC entity number → continent (NA/SA/EU/AF/AS/OC, fixed precedence) — port of `ContinentMapper.swift`; backs the brag geographic stats |
| `brag_sheet.rs` | Brag Sheet catalog (58 stat types) + 11 categories + periods + 7 presets + `BragConfiguration`/`BragPeriodConfig` + `BragStatValue` formatting — port of the 6 Swift `Models/BragSheet/*.swift` domain enums + `BragSheetStatRendering.swift` |
| `azimuthal.rs` | Azimuthal equidistant projection + great-circle path + sector-binning — port of `AzimuthalProjection.swift` |
| `antenna.rs` | Antenna type/pattern math + free-text description parser — ports `AntennaPattern.swift` + `AntennaDescriptionParser.swift` |
| `callsign_edit_distance.rs` | Levenshtein over uppercased strings + near-match search — port of `CallsignEditDistance.swift` |
| `catalog_matcher.rs` | Fuzzy equipment-catalog scorer (`search`/`best_match`, `CatalogEntryRef`) — port of `CatalogMatcher.swift`; case-preserving edit distance, deterministic tie-break |
| `morse.rs` | Morse tables + timing + pattern/word edit distance — ports `MorseCode.swift` + `MorseEditDistance.swift` |
| `nato_phonetics.rs` | NATO/ITU phonetic alphabet speller — port of `NATOPhonetics.swift` |
| `cw_text_element.rs` | Decoded CW text element enum + suggestion category — ports `CWTextElement.swift` + `SuggestionCategory.swift` |
| `fmt.rs` | Frequency + unit/distance/temperature/wind/cardinal formatters (`UnitSystem` enum supplied by caller) — ports `FrequencyFormatter.swift` + `UnitFormatter.swift` |
| `cty.rs` | CTY.dat parser + `DxccEntity` + `CtyDatabase` lookup — port of `CTYParser.swift` |
| `coastline.rs` | Natural Earth 110m land polygons (103 polygons / 4,982 pairs), embedded from `data/coastline.json` via `include_bytes!` — port of `CoastlineData*.swift` |
| `dedup.rs` | `QsoSnapshot` + duplicate group/winner/merge logic + two-fer matcher — ports `QSOSnapshot.swift` + `DeduplicationMatcher.swift` + `TwoferMatcher.swift`; `deduplication_key` (`CALL\|BAND\|MODE\|2-min bucket`) — port of `QSO.makeDeduplicationKey`, the import-dedup identity |
| `park_geometry.rs` | Park/trail boundary pure-math geometry: signed area, ray-cast point-in-ring, Douglas-Peucker simplify, polygon buffer skirt with miter clamp, polyline buffer with averaged vertex normals — port of `ParkBoundary+Geometry.swift` + `TrailBoundary+Geometry.swift` |
| `multiplier.rs` | Activation-multiplier ("rosette") finder: POTA+SOTA point-in-polygon (reuses `park_geometry::point_in_ring`), POTA+WWFF passthrough, county-line proximity (1,500 m threshold, local equirectangular point-to-segment distance) — port of `MultiplierFinder.swift` |
| `park_reference.rs` | POTA/WWFF park-reference parsing/sanitization/subset/overlap helpers — port of `ParkReference.swift` |
| `polo_notes.rs` | Ham2K Polo callsign-notes parser (emoji/name/note split) — port of `PoloNotesParser.swift` + `PoloNotesEntry.swift` |
| `reference_csv.rs` | POTA parks / SOTA summits / WWFF directory CSV parsers (+ shared quoted-field line parser, HTML-challenge guard) — ports of the three `*Cache` parse halves; SOTA expiry compare is chronological (documented deviation from iOS's lexicographic compare) |
| `scp.rs` | Super Check Partial database (dedup/sort + prefix/substring/near-match) — port of `SCPDatabase.swift` |
| `skcc.rs` | SKCC roster parser + award resolution + by-callsign index — port of `SKCCMembershipStore.swift` parsing half + `SKCCMember.swift` |
| `spots/` | Shared spots engine domain (plan `docs/plans/2026-07-02-spots-engine-rust-port.md`): `model.rs` (`UnifiedSpot`/`EnrichedSpot`/`SpotSource`/`NeededStatus`/`MatchedNeed` + `guess_mode`, ports `UnifiedSpot.swift` + `NeedTypes.swift`), `region.rs` (14-region grid classifier + groups/continents, `SpotRegion.swift`), `merge.rs` (`SpotPool` priority dedup/prune, `SpotAggregator.swift` pool half), `band_edges.rs` (inclusive HF band map, `BandEdges.swift`), `cluster_parser.rs` (DX-de line/mode/WPM/split parsing, `DXSpotParser.swift` + `SplitInfoParser`), `filters.rs` (Sweep+iOS filter predicate union), `needs.rs` (`NeedsSnapshot` + spot needs matcher, iOS `SpotNeedsMatcher.swift`), `observations.rs` (scope observation/spotter rows + projection enrichment, `SpotObservationMapper.swift`), `goal_profile.rs` (Band Scope v2 goal-profile → SQL compiler: per-lens `scope_pass`/`heard_pass`/`wpm_dim` queries over `scope.spots`, strict literal escaping) |
| `sql_format.rs` | SQL pretty-printer (`format_sql`) for the query workbench Format button — port of Sweep's `SQLFormatter.swift` (tokenizer + paren-frame emitter; Swift quirks preserved, idempotent) |
| `streak.rs` | Calendar-day streak calculator over `chrono::NaiveDate` — port of `StreakCalculator.swift` |
| `tota.rs` | Tiles on the Air scoring engine + T3 correlator + tile detector + winter detector — ports `TOTAScoringEngine.swift` + `TOTAT3Correlator.swift` + `TOTATileDetector.swift` + `TOTAWinterDetector.swift` |
| `contest/` | Contest engine (v0.3 definitions; plan `docs/plans/2026-07-04-contest-engine-rust-port.md`): `model.rs` (serde defs incl. recursive aggregate ops + tolerant unknown field types, ports `Models/Contest*.swift`), `engine.rs` (dupes/serials/multipliers/score/rescore/rate w/ injected time, `ContestEngine.swift` + `+Phases`), `condition.rs` (field vocabulary + predicate eval), `exchange_parser.rs` (token classification, ARRL/state/province sets), `callsign.rs` (normalize + WPX prefix), `cabrillo.rs` (Cabrillo 3.0, byte-identical to Swift golden), `schedule.rs` (occurrences + annual rules), `off_time.rs` / `band_change.rs` (compliance trackers), `enrichment.rs` (CWT prefill). Live-server fixtures in `tests/fixtures/contests/` + `tests/contest_fixtures.rs` |
| `share_render/` | Themed share-map rasterizer (map port Phase D): `themes.rs` (`Rgba`/`ShareTheme`/`ThemeStyle` + 5 flat palettes midnight/warm/ocean/arctic/ember + `Azimuthal`, ports `FlatMapRenderer.ColorTheme` + `AzimuthalMapRenderer`'s hardcoded palette), `flat.rs` (tiny-skia PNG `render_flat(FlatMapSpec, ShareTheme)`: ocean bg → grid → coastlines w/ fill+crosshatch+stroke → geodesic traces → pins → center marker; ports `FlatMapRenderer` + `+Drawing`; antimeridian handled by explicit per-polygon nearest-±360-shift + threshold split, NOT the Swift triple-draw), `azimuthal.rs` (tiny-skia PNG `render_azimuthal(AzimuthalMapSpec, ShareTheme) -> (Vec<u8>, Vec<RingLabel>)`: bg → ocean circle → coastlines (stroke-only, breaks path off-projection) → dashed range rings (native tiny-skia `StrokeDash`) → geodesic traces via `AzimuthalProjection::great_circle_path` → pins → center marker; ports `AzimuthalMapRenderer` minus `drawRingLabel`, which returns `RingLabel{x,y,text}` anchors — no text rasterized, ring-top-center anchor since Rust has no font metrics), `primitives.rs` (pin marker + center marker geometry/tiny-skia drawing helpers shared by `flat.rs`/`azimuthal.rs`, identical constants on both Swift sides), `viewport.rs` (`compute_flat_share_viewport(coords, w, h) -> ShareViewport{center_lat/lon, lat/lon_span}` + `tightest_longitude_bounds`; verbatim port of the deleted `FlatMapRenderer.computeViewport`: bounds-midpoint center with operator folded in, `max(range*0.25,8)` lat / `max(range*0.2,8)` lon padding, aspect-fit expansion, ±85°/one-globe clamps). Golden PNGs + azimuthal ring-label text fixture in `tests/fixtures/share_render/` + `tests/share_render_goldens.rs` (pin THIS impl; regen via `CW_REGEN_GOLDENS=1`) |
| `us_grid_state.rs` | Maidenhead grid square → US state approximation table — port of `POTAClient+GridLookup.swift` (`gridToUSState`); the POTA `statesActivated` grid fallback |
| `text_protocol.rs` | `;`-terminated response extractor shared by Kenwood + Yaesu — port of `TextProtocolParser.swift` |
| `kenwood.rs` | K3/Elecraft ASCII command builders + parsers — port of `KenwoodProtocol.swift` |
| `kiwisdr/` | KiwiSDR domain: `mode.rs` (passband tables, `KiwiSDRTypes.swift`), `adpcm.rs` (IMA ADPCM, `KiwiSDRADPCM.swift`), `protocol.rs` (SND/MSG parsing + redirect targets + tune command), `directory.rs` (Skywavelinux JS + kiwisdr.com HTML parsing, haversine nearby search), `status.rs` (`/status` parsing), `selection.rs` (Tune-In candidate dedup, QSY detection, receiver-quality rules) |
| `yaesu.rs` | Yaesu CAT ASCII command builders + IF response parser — port of `YaesuProtocol.swift` |
| `civ.rs` | CI-V binary frame builder/extractor + BCD frequency + mode mapping — port of `CIVProtocol.swift` |
| `adif.rs` | ADIF record parser + field extractor (case-insensitive `<eor>`/`<eoh>`, submode-wins-over-mode) — port of `ADIFParser.swift` |
| `propagation.rs` | HF band propagation estimator from SFI + K-index + UTC hour — port of `PropagationEstimator.swift` |
| `adif_catalog.rs` | ADIF 3.1.7 mode + band + submode→parent tables — port of `ADIFCatalog.swift` (states deferred) |
| `adif_validator.rs` | Per-field + composite ADIF validators (callsign/band/mode/submode/freq/date/time/grid) — port of `ADIFFieldValidator.swift` |
| `adif_writer.rs` | ADIF QSO record writer (`write_adif`/`write_bulk_adif`, byte-golden field order/header/`<EOR>` framing, UTF-8 octet field lengths) — port of `ADIFExportService.swift` (POTA single + bulk export); `write_session_adif(AdifSessionRecord[], AdifSessionHeaderOpts)` resolves the park per record (`None` → no `MY_*` POTA block, P2P fields kept) and writes the session summit as `MY_SOTA_REF` |
| `wsjtx.rs` | WSJT-X plain message data — `QsoLogged` (type 5) / `LoggedAdif` (type 12), defined here so `cw-net` (decoder) and `cw-store` (mapping) need not depend on each other; `cw-net::wsjtx` re-exports them — plus pure mapping helpers `store_mode` (WSJT-X mode → store mode, JT65 submode fold, unknown passthrough) and `khz_from_hz`/`band_from_hz`; greenfield (CAR-280) |
| `callsign_detector.rs` | Regex-based callsign extraction + context-priority primary-call detection + grid/power/RST extractors — port of `CallsignDetector.swift` core |
| `callsign_flag.rs` | Callsign-prefix → country flag emoji (intentionally partial hand-rolled table, 2-char before 1-char) — port of `CallsignFlagHelper.swift` |
| `query/mod.rs` | Query language entry points (`parse`, `parse_and_analyze`) |
| `query/token.rs` | `QueryField`/`QueryToken`/`SourcePosition` — port of `QueryToken.swift` |
| `query/error.rs` | `QueryError` — port of `QueryError` |
| `query/ast.rs` | `ParsedQuery`/`QueryExpression`/`TermCondition`/`DateMatch` — port of `QueryAST.swift` |
| `query/lexer.rs` | `QueryLexer` — port of `QueryLexer.swift` |
| `query/parser.rs` | `QueryParser` + conditions + field terms — ports `QueryParser*.swift` |
| `query/analyzer.rs` | `QueryAnalyzer`/`QueryAnalysis` — port of `QueryAnalyzer.swift` |
| `query/tests.rs` | Query language tests |
| `satellite/mod.rs` | Satellite domain root: `Observer`/`SatTle`/`SatTransmitter` shared types |
| `satellite/propagator.rs` | SGP4 (crates.io `sgp4`) + TEME→ECEF→geodetic/topocentric frames — the layer SatelliteKit did internally. Mirrors SatelliteKit's quirks verbatim for parity (non-standard `1+e²sin²φ` observer prime-vertical AND its `geo2eci→eci2geo→geo2eci` observer round-trip); fixture-tested against SatelliteKit output (~0.006° az/el) |
| `satellite/catalog.rs` | `build_ham_satellites` — amateur/workability gates, capability filter, active-first sort, display names; port of `SatelliteTrackerModel.buildHamSatellites` |
| `satellite/tracker.rs` | `SatPosition` + `propagate_all`/`ground_track` with finite-difference rates; port of `SatelliteTrackerModel` propagation statics |
| `satellite/pass_predictor.rs` | 60 s coarse scan + 1 s bisection + 10 s peak sampling; port of `SatellitePassPredictor` (SatelliteKit-fixture parity tests, geostationary always-visible case) |
| `satellite/mutual.rs` | Two-station joint-visibility windows + profile samples; port of `MutualPassPlanner` |
| `satellite/workability.rs` | Derelict list + AMSAT 7-day silence + capability filter + 10°/20° thresholds; port of `SatelliteWorkability` (injected `now`) |
| `satellite/mode_category.rs` | FM/linear/CW/digital transmitter buckets; port of `SatelliteModeCategory` |
| `satellite/display_name.rs` | OSCAR designator resolver + TLE line-zero strip; port of `SatelliteDisplayName` |
| `satellite/polarization.rs` | Curated NORAD→polarization table + pointing hints; port of `SatellitePolarization` |
| `satellite/alert_planner.rs` | Pass-alert planning (24 cap, minute-rounded `satpass-` ids, notification copy); port of `SatellitePassAlertPlanner` with its 6 tests verbatim |
| `satellite/amsat.rs` | `AmsatStatus` + `capability_tag`/`base_name`/`freshest` (pure half of `AmsatStatusService`); `ActivityBucket`/`ActivityStatus` — the community-activity grid cell model with AMSAT's legend classification (heard / telemetry-only / not-heard / conflicting) and `merge_buckets` hourly→coarser-cell re-bucketing; `ReportKind`/`AmsatReport` raw-report model and `previous_orbit` (reports within one orbital period + 30 min → `OrbitSummary` with distinct heard callsigns) |

## cw-domain data (`cw-domain/data/`)

| File | Purpose |
|------|---------|
| `coastline.json` | Natural Earth 110m land polygons (103 polygons, 4,982 (lat, lon) pairs) — canonical source the iOS/macOS apps now regenerate from. Loaded via `include_bytes!` in `coastline.rs`. |

## cw-ft8 (`cw-ft8/src/`)

| File | Purpose |
|------|---------|
| `lib.rs` | Crate root + Phase-1 status notes |
| `constants.rs` | `Ft8Constants` — timing/tones/dial frequencies, port of `FT8Constants.swift` |
| `message.rs` | `Ft8Message` enum + computed props, port of `FT8Message.swift` |
| `ffi.rs` | Raw `ft8_lib` bindings (generated by `build.rs` via bindgen) |
| `decoder.rs` | Safe Rust wrapper over monitor + ftx_decode pipeline — port of `FT8Decoder.swift` |
| `encoder.rs` | Safe Rust wrapper over `ftx_message_encode` + 8-FSK synth — port of `FT8Encoder.swift` |
| `wav.rs` | 12 kHz mono 16-bit PCM WAV loader — port of `FT8Decoder.loadWAV` |
| `../build.rs` | Compiles vendored `ft8_lib` via `cc`; generates `ffi.rs` via `bindgen` |
| `../tests/wav_parity.rs` | Parity gate vs Swift: same WAVs, same expected text → message-set agreement |

## cw-store (`cw-store/src/`)

| File | Purpose |
|------|---------|
| `lib.rs` | `Store` open/key/migrate (SQLCipher), entity re-exports, encryption tests |
| `error.rs` | `StoreError` |
| `migrations.rs` | Versioned schema; v1 = `qso` (DDL via `qso::QSO_DDL`), v2 = the other 11 synced entities (each entity owns its `*_DDL` const), v4 = `pota_park` reference table, v5 = `club`/`club_member`, v6 = `sync_kv`, v7 = `friendship`, ..., v13 = `callbook_location`, v14 = `gis_boundary_cache`, v15 = `idx_qso_park_upper`, v16 = `qso.sat_name`/`qso.prop_mode` (first guarded `ALTER TABLE ADD COLUMN` via `add_column_if_missing`), v17 = `satellite_data_cache` |
| `sota_summit.rs` | `sota_summit` reference table (full-replace writer, count, fetch, `sota_summit_zone_inputs` for the zones bulk fetch, `fetch_sota_summits_in_box` map-viewport bbox read) — mirrors `SOTASummitsCache` |
| `sota_zone.rs` | `sota_zone` activation-zone table (`SotaZoneRow` w/ GeoJSON geometry; upsert accumulates across lazy server passes; `sota_zones_for_summits` cached-only bulk read by code) — mirrors the `SOTAZonesCache` disk file |
| `wwff_reference.rs` | `wwff_reference` directory table (full-replace writer, count, fetch, `fetch_wwff_references_in_box` map-viewport bbox read; all statuses kept) — mirrors `WWFFReferencesCache` |
| `reference_search.rs` | `search_references` — unified case-insensitive search across `pota_park`/`sota_summit`/`wwff_reference` (`RefSearchHit`, `RefKind`); single `UNION ALL` query, SQL-side `CASE` rank tiers (exact/prefix/substring), `LIMIT` enforced in SQL |
| `gis_cache.rs` | `gis_boundary_cache` table (schema v14) — TTL-cached GeoJSON boundaries keyed by `(kind, cache_key)` for park/trail/admin polygons + SOTA zones; `upsert_gis`/`fetch_gis`/`evict_gis`, shared 7-day TTL, per-kind eviction caps |
| `satellite_cache.rs` | `satellite_data_cache` table (schema v17) — one raw wire-JSON blob per kind (`tle`/`transmitters`/`amsat`/`amsat_activity`/`amsat_reports:<norad>`), TTL applied by the reader (6 h orbital, 20 min activity, 10 min reports; stale-degrade); replaces the iOS SatNOGS disk caches |
| `pota_awards.rs` | POTA activator awards aggregate (unique parks, WAS states via `pota_park` + grid fallback, kilo/near-kilo, LaPorta, six-pack, rover, repeat-offender, dx-entities) — faithful Rust fold port of `POTAAwardsActor` + `POTAAwardsComputation`; fetches park-QSO columns once, folds in Rust (not a flat `GROUP BY`) |
| `analytics.rs` | `compute_configured_brag` — orchestrates `cw_domain::brag_sheet` stat computation over a `BragConfiguration` (per-stat QSO fold), club-overlay stats (`ClubMembersWorked`/`ClubsRepresented`) returned as `NoData` for the caller (`cw-ffi`) to overlay |
| `qso.rs` | `Qso`/`QsoFilter` + `QSO_DDL` + bounded query API (`MAX_FETCH_LIMIT`); full-fidelity mirror of the `QSO` `@Model` (~50 fields incl. my_grid/their_grid, contest, QRZ/LoTW, sat_name/prop_mode, imported_at/modified_at). Activity-log/session queries: `fetch_qsos_for_session` (per-session window) + `fetch_activity_log_qsos_since` (all hunter QSOs today, backs the worked-before cache) + `fetch_activation_qsos` (`(park, my_callsign, UTC-day)` non-metadata/visible, ASC — the POTA-activation ADIF-export scope); `satellite_qso_counts_since` (own QSOs per upper-cased `SAT_NAME` since an epoch, for the community-activity grid) |
| `adif_import.rs` | ADIF-file import policy shared by the hosts — port of the non-UI half of iOS `ImportService.importADIF`: `filter_for_multi_op` (+ `strip_portable_suffix`) keeps only this operator's / unattributed records in a multi-op log; `Store::deduplication_keys()` (four-column scan → `HashSet<deduplication_key>`, hidden rows included — the `fetchExistingDeduplicationKeys()` set); `ADIF_FILE_IMPORT_SOURCE = "adifFile"`. Orchestration is `cw-ffi::adif_api::AdifApi::import_adif` |
| `wsjtx_import.rs` | WSJT-X → `Qso` mapping (CAR-280): `qso_from_qso_logged` (type 5) and `qso_from_logged_adif` (type 12, `cw_domain::adif::parse` → `qso_from_adif_record`, the Rust port of iOS `ImportService.createQSO` — also used by the ADIF-file import in `adif_import.rs` / `cw-ffi::adif_api`); `WsjtxImportContext` (station-callsign fallback, `imported_at`, session); provenance `import_source_raw_value = "wsjtx"`; stable identity `id = UUIDv5(WSJTX_QSO_NAMESPACE, deduplication_key)` so the QSOLogged + LoggedADIF pair for one QSO upsert into one row (`wsjtx_dedup_key`/`wsjtx_qso_id`) |
| `logging_session.rs` | `LoggingSession` (76 fields incl. TOTA/contest/solar/weather + blobs) — port of `LoggingSession.swift`. Session-merge/lifecycle ops: `fetch_logging_sessions_by_status`, `reassign_qsos_to_session` / `reassign_session_spots_to_session` / `reassign_websdr_recordings_to_session`, `hide_qsos_in_session` |
| `service_presence.rs` | `ServicePresence` (per-service upload/confirm state; `qso_id` FK) — port of `ServicePresence.swift` |
| `session_spot.rs` | `SessionSpot` (spots captured during a session) — port of `SessionSpot.swift` |
| `activation_metadata.rs` | `ActivationMetadata` (keyed on `park_reference`; solar/weather) — port of `ActivationMetadata.swift` |
| `activity_log.rs` | `ActivityLog` (hunter-log workflow) — port of `ActivityLog.swift` |
| `equipment_item.rs` | `EquipmentItem` (radio/antenna inventory; JSON blobs) — port of `EquipmentInventory.swift`; `EquipmentSort` (CreatedAtDesc / NameAsc) on the filter |
| `loadout.rs` | `Loadout` (named equipment-only preset: radio/antenna/key/mic + radio_item_id) — portable replacement for iOS `SavedSessionTemplate`; schema v11, local/observed only |
| `radio_macro.rs` | `RadioMacro` (CAT macros; JSON step/arg blobs, tombstones) — port of `RadioMacro.swift` |
| `websdr_recording.rs` | `WebSDRRecording` (KiwiSDR clip metadata) — port of `WebSDRRecording.swift` |
| `websdr_favorite.rs` | `WebSDRFavorite` (keyed on `host_port`) — port of `WebSDRFavorite.swift` |
| `upload_destination.rs` | `UploadDestination` (per-service upload toggle) — port of `UploadDestination.swift` |
| `cloud_sync_metadata.rs` | `CloudSyncMetadata` (CK record mapping; composite `(entity_type, local_id)` key) — port of `CloudSyncMetadata.swift` |
| `friendship.rs` | `Friendship`/`FriendshipFilter` + `FRIENDSHIP_DDL` (schema v7) — social graph cache (accepted friends + pending requests), keyed by `friend_user_id`, status × is_outgoing; port of `Friendship.swift` |
| `contest_definition.rs` | `ContestDefinitionRow` + `CONTEST_DEFINITION_DDL` (schema v9) — contest-definition cache (summary columns + raw v0.3 body verbatim), replaces the iOS `ContestDefinitionsStore` JSON-file cache; upsert / bounded fetch / retain-reconcile |
| `sync_dirty.rs` | Cross-entity sync-journal dirty-flag ops keyed by `JournalEntityType` raw value: `mark_all_dirty` (port of `+MarkAllDirty.swift`; QSO skips metadata modes) + `clear_dirty` (port of `+Outbound.swift` `clearDirtyFlag` confirm step incl. CAR-245 newer-than-snapshot guard). Per-entity table/dirty-col/id-col/modified-col resolver |
| `testing/mod.rs` | Re-exports `CrashController` + `sample_qso_min` (feature `testing`) |
| `testing/crash_vfs.rs` | Crash-injection shim VFS over the default VFS (feature `testing`); power-loss/torn-page/ENOSPC fault injection + crash-image snapshot |
| `bin/durability_crasher.rs` | App-crash child: upsert, ACK, abort() (feature `testing`) |

## cw-store tests (`cw-store/tests/`)

| File | Purpose |
|------|---------|
| `durability.rs` | Write-durability torture suite: power-loss/torn/ENOSPC/app-crash/concurrency |

## cw-net (`cw-net/src/`)

| File | Purpose |
|------|---------|
| `lib.rs` | Crate root + Phase-3 status notes, public re-exports |
| `http.rs` | `HttpClient` (reqwest wrapper) + `HttpError` + shared User-Agent |
| `clients.rs` | Per-service async clients (RBN/POTA/SOTA/WWFF/PSK/DONKI/HamQSL/LoFi), rate-limit + TTL cache primitives, `QueryBuilder`. `RbnClient` proxies through `{activities}/v1/rbn/spots` |
| `amt.rs` | Another Morse Trainer stats client (`AmtClient`): RFC 7636 PKCE helpers, email-link `start_sign_in`/`poll`, `refresh`/`logout`, `me`, `stats` → `AmtStats` (totals, streak, per-mode/character, activity calendar) + `AmtError` |
| `qrz.rs` | QRZ XML callbook client (`QrzClient` session auth + `lookup` → `QrzLookup`) + `QrzError`, port of the QRZ-XML half of `CallsignLookupService+QRZ.swift` |
| `hamdb.rs` | HamDB.org callbook client (`HamdbClient` → `HamdbLookup`) — free US fill-nil fallback (name/grid/QTH/state/country/class), `NOT_FOUND`-by-body, port of `HamDBClient.swift` |
| `kiwisdr.rs` | KiwiSDR transport: directory fetch + daily disk cache (`KiwiSdrDirectoryClient`), bounded-concurrency `/status` enrichment (`KiwiSdrStatusClient`), tokio-tungstenite websocket audio client (`connect_following_redirects` → `KiwiSdrConnection` + `KiwiSdrEvent`: auth, sample-rate wait, compression, tune, AGC, 5s keepalive, ADPCM resets) — transport halves of `WebSDRDirectory`/`KiwiSDRStatusFetcher`/`KiwiSDRClient` |
| `enrichment.rs` | Server callsign-enrichment dataset client (`EnrichmentClient` → ETag-conditional `EnrichmentDataset`; compact `c`/`m`/`s`/`n`/`#`/`e`/`t` keys) — port of the dataset half of `ActivitiesClient+CallsignEnrichment.swift` |
| `contests.rs` | Contest-definition endpoints (`ContestsClient`: `GET /v1/contests` list + `/:id` envelope with the raw v0.3 body kept opaque) — port of `ActivitiesClient+ContestDefinitions.swift` |
| `pota.rs` | `PotaSpot` model + parsing helpers, port of `POTASpot.swift` |
| `sota.rs` | `SotaSpot` + `SotaSpotPost` builder + frequency formatter, port of `SOTASpot.swift` + `SOTAClient.swift` (parsing half) |
| `wwff.rs` | `WwffSpot` + `WwffAgendaItem` + HTML table scraper (`data-label` cells), port of `WWFFClient.swift` parsers |
| `reference_data.rs` | External-data downloaders: `fetch_reference_csv` (UA + HTML guard + CRLF normalize), `EquipmentCatalogClient` (ETag + bearer), `FccClient` (metadata sidecar + gzip SQLite download), `SotaZonesClient` (chunked `POST /v1/sota/zones`, GeoJSON features) |
| `boundaries.rs` | GIS boundary GeoJSON clients (map port phase C): `ParkBoundariesClient` (`by_refs`/`by_bbox`/`full_res` on `/v1/parks/boundaries[/{ref}]`, grouped-by-reference, unmerged — server pre-merges), `TrailsClient` (`by_bbox` on `/v1/trails`), `AdminBoundariesClient` (`by_bbox` + `AdminBoundaryKind` on `/v1/admin/boundaries`); shared `BoundingBox`; raw GeoJSON geometry kept verbatim per feature; resilient skip-bad-feature decode (Swift `SafeFeature`/`SafeAdminFeature` behavior) — ports of `ActivitiesClient+ParkBoundaries.swift`/`+Trails.swift`/`+AdminBoundaries.swift` |
| `dxsummit.rs` | `DxSummitSpot` + dual-format timestamp decode, port of `DXSummitClient.swift` decoding half |
| `dxheat.rs` | `DxHeatSpot` (PascalCase JSON) + split date/time + HTML-entity decode, port of `DXHeatClient.swift` decoding half |
| `dxwatch.rs` | `DxWatchResponse` compact-array decoder (`s`/`ci` maps, band-code table, yearless timestamps), port of `DXWatchResponseDecoder` |
| `unified.rs` | Source-spot → `cw_domain::spots::UnifiedSpot` mappings for all 9 sources (RBN/POTA/SOTA/WWFF/DX-web trio/cluster/PSKR), ports `UnifiedSpot` factory extensions |
| `cluster.rs` | Telnet DX cluster transport (tokio TCP, auto-login, line framing → `ClusterEvent::{Line,Spot}`), port of `TelnetClusterClient.swift`; reconnect + SH/WWV cycle live in the engine layer |
| `pskreporter.rs` | `PskReporterSpot` + quick-xml SAX-style parser, port of `PSKReporterXMLParser` |
| `rbn.rs` | `RbnSpot` + 3 response shapes + derived band/MHz/formatted/epoch, port of `RBNSpot.swift` |
| `donki.rs` | NASA DONKI models + unified `DonkiEvent` enum + radio-impact ranking + mixed-format date parser, port of `DONKIClient.swift` |
| `hamqsl.rs` | `HamQslSolarData` + `HamQslBandCondition` + solarxml parser, port of `HamQSLClient.swift` |
| `lofi.rs` | Ham2K LoFi JSON wire models (registration, accounts, operations, QSOs, sync flags), port of `LoFiModels*.swift` |
| `wsjtx.rs` | WSJT-X UDP Network Protocol decoder (`QDataStream` reader → `Heartbeat`/`Status`/`Decode`/`QsoLogged`/`LoggedAdif`/`Close`/`Other`; Status/Decode trailing fields decoded best-effort as `Option`) + async `WsjtxListener` over `tokio::net::UdpSocket`; greenfield (CAR-277 + CAR-283, no Swift port). `QsoLogged`/`LoggedAdif` are defined in `cw-domain/src/wsjtx.rs` and re-exported here (CAR-280) |
| `friends.rs` | `FriendsClient` + wire models for the activities-server friends + activity-feed endpoints (search/friends/pending/request/accept/decline/remove/suggestions/invite-link/feed/report/delete-activity); port of iOS `ActivitiesClient+Friends`/`+Activities` |
| `satnogs.rs` | `SatnogsClient` — bulk TLE + transmitter fetches from db.satnogs.org (wire structs → `cw_domain::satellite` conversions); network half of `SatNOGSClient.swift` |
| `amsat.rs` | `AmsatStatusClient` — activities-server `/v1/satellites/amsat-status` (camelCase wire → `AmsatStatus`) and `/activity?hours=` (`AmsatActivityResponse` hourly buckets → `ActivityBucket`) and `/reports?norad=&hours=` (`AmsatReportsResponse` → `AmsatReport`); network half of `AmsatStatusService.swift`. `AmsatSubmitClient` — the one write, `POST status.amsat.org/api/v1/reports.php` (`AmsatReportSubmission` snake_case body with AMSAT's `…Z` time layout, descriptive User-Agent, `AmsatSubmitError::Rejected` carrying AMSAT's error-envelope message); `AMSAT_REPORT_VALUES`, `AMSAT_ATTRIBUTION` |

## cw-sync (`cw-sync/src/`)

| File | Purpose |
|------|---------|
| `lib.rs` | Crate root, re-exports |
| `error.rs` | `SyncError` |
| `conflict.rs` | Merge primitives + `merge_qso` + LWW — port of `CloudSyncConflictResolver.swift` |
| `journal.rs` | `JournalOperation`/`JournalPayload` — port of `CloudSyncJournalEntry.swift` |
| `transport.rs` | `SyncTransport` trait + `InMemoryTransport` (CloudKit→server swap point) |

## cw-ffi (`cw-ffi/src/`)

| File | Purpose |
|------|---------|
| `lib.rs` | UniFFI surface root: `analyze_query`, `validate_query`, maidenhead fns, `callsign_flag` (prefix→flag), the `FieldStore` object + QSO methods (`worked_before_count`, `duplicate_status` + `FfiDuplicateStatus` — port of iOS `classifyDuplicateStatus`); declares `mod entities`, `mod observation`, `mod quick_entry`; QSO upsert fires `notify` |
| `quick_entry.rs` | UniFFI surface for `cw_domain::quick_entry`: `parse_quick_entry`(`_multi`/`_tokens`), the `Ffi*` DTOs, and `quick_entry_is_*` predicates — shared by Swift + Kotlin |
| `scp.rs` | UniFFI surface for `cw_domain::scp`: the `ScpDatabase` object (`partial_match`/`contains`/`merging`/`near_matches`) |
| `skcc.rs` | UniFFI surface for `cw_domain::skcc`: `parse_skcc_roster`/`parse_skcc_member_line`/`build_skcc_index` + `FfiSkccMember`/`FfiSkccAward` |
| `polo_notes.rs` | UniFFI surface for `cw_domain::polo_notes`: `parse_polo_notes`/`parse_polo_note_line`/`polo_note_from_text` + `FfiPoloNotesEntry` |
| `rbn.rs` | UniFFI surface for `cw_net::rbn`: `decode_rbn_response` + `FfiRbnSpot` (with derived fields) |
| `cat.rs` | UniFFI surface for `cw_domain::civ`/`kenwood`/`yaesu`: CI-V/Kenwood/Yaesu command builders + response parsers + mode mappings + frame parsing (`civ_*`/`kenwood_*`/`yaesu_*` fns; `FfiCivFrame`/`FfiYaesuInformation`). Backs the Swift `CIVProtocol`/`KenwoodProtocol`/`YaesuProtocol` facades |
| `pota.rs` | UniFFI surface for `cw_net::pota`: `decode_pota_response` + `FfiPotaSpot` (with derived fields) |
| `sota.rs` | UniFFI surface for `cw_net::sota`: `decode_sota_response` + `FfiSotaSpot` (with derived fields) |
| `wwff.rs` | UniFFI surface for `cw_net::wwff`: `decode_wwff_spots_html` + `FfiWwffSpot` (with derived fields) |
| `pskreporter.rs` | UniFFI surface for `cw_net::pskreporter`: `decode_psk_reporter_xml` + `FfiPskReporterSpot` (with derived fields) |
| `adif.rs` | UniFFI surface for `cw_domain::adif`/`adif_validator`/`adif_catalog`: `adif_parse`/`adif_extract_*`, the `adif_validate_*` family + `adif_validate_for_upload`, and the mode/band/submode catalog accessors. Backs the Swift `ADIFParser`/`ADIFFieldValidator`/`ADIFCatalog` facades |
| `band_mode.rs` | UniFFI surface for `cw_domain::band`/`mode`/`band_plan`: `band_derive`/`band_range`/boundaries, the `mode_*` classification/equivalence/dedup family, and `band_plan_segments`. Backs the Swift `BandUtilities`/`ModeEquivalence`/`BandPlan` facades |
| `callsign.rs` | UniFFI surface for `cw_domain::callsign_detector` + `callsign_edit_distance`: `callsign_extract_callsigns`/`callsign_detect_primary`/`callsign_distance`/`callsign_find_near_matches` + `FfiDetectedCallsign`/`FfiNearMatch`/`FfiCallsignContext`. Backs the Swift `CallsignDetector`/`CallsignEditDistance`/`DetectedCallsign` facades (the `CWTextElement` rendering path stays Swift-side) |
| `cty.rs` | UniFFI surface for `cw_domain::cty`: the `CtyDatabase` object (`parse`/`lookup`/`entities`/`prefix_map`) + `FfiDxccEntity`. Backs the Swift `CTYParser`/`CTYDatabase`/`DXCCEntity` facades |
| `spots_api.rs` | Async `SpotsApi` object (tokio): `fetch_pota`/`fetch_rbn`/`fetch_sota`/`fetch_wwff` wrapping the `cw_net` spot clients, returning the `Ffi*Spot` records. Consumed by Android's Spots tab |
| `amt_api.rs` | Async `AmtApi` object: Another Morse Trainer email-link sign-in (`start_sign_in` / `poll_for_completion`), single-flight refresh rotation, `refresh_stats` → `FfiAmtStats` (streak + activity days + per-mode), `sign_out`. Tokens, account and the offline stats snapshot live in the host `SecureStore` under `cw.amt.*`. Wraps `cw_net::AmtClient` |
| `qrz_api.rs` | Async `QrzApi` object: QRZ callbook `lookup` → `FfiQrzLookup`, credentials via the host `SecureStore`, in-memory session-key cache + single-flight re-auth. Wraps `cw_net::QrzClient`. `lookup_callbook` merges QRZ over a credential-free HamDB fallback (`cw_net::HamdbClient`), QRZ-priority/HamDB-fill-nil |
| `enrichment_api.rs` | `EnrichmentApi` object: combined callsign enrichment (`lookup` → `FfiCallsignEnrichment`: DXCC via `cw_domain::cty` + SKCC via `cw_domain::skcc` + store club membership + server `FfiMembership` rows), async `refresh` fetches+caches CTY.dat/SKCC roster, async `refresh_memberships` (ETag + 12h TTL) fetches+caches the server membership dataset, all in the store kv |
| `activity_log_api.rs` | `ActivityLogApi` object — port of iOS `ActivityLogManager` (hunter/chaser workflow): single-active-log lifecycle (create/activate/deactivate/delete/switch-profile/grid), `log_qso` enrichment + upload routing (QRZ presence only, never POTA, skip metadata modes) + today stats + one-shot daily-goal, `worked_today` dedup map. Active log = store `is_active=1` row |
| `session_api.rs` | `SessionApi` object — port of iOS `LoggingSessionManager` activation kernel: lifecycle (`pause`/`resume`/`end`/`reopen`, resume pauses other active), session-stamped `log_qso` (band-from-freq, operator park, WWFF ref, `sotaRef` nil, count increment, QRZ+POTA upload routing, optional contest-field stamping), `merge_sessions` (reassign QSOs/spots/recordings + time-bound expand + count fold + photo concat), `delete_session` (hide QSOs). POTA-split / conditions-merge / WPM deferred |
| `friends_api.rs` | Async `FriendsApi` object (tokio) — port of iOS `FriendsSyncService` + `ActivitiesClient`: `sync_friends` (fetch friends + pending, reconcile the `friendship` cache delete-not-returned), search/request/accept/decline/remove/suggestions/invite-link, on-demand `fetch_feed` (+ report/delete activity). Wraps `cw_net::FriendsClient` |
| `hunter_log.rs` | UniFFI surface for `cw_domain::hunter_log` + `quick_entry::extract_primary`: `hunter_extract_primary`, `hunter_band_mode_park_key`, `hunter_derive_dxcc` + `FfiDxccDerivation` |
| `sdr_api.rs` | Async `SdrApi` object (tokio) — `Services/WebSDR/` port: directory search, `/status` enrichment via `SdrStatusListener`, three Tune-In strategies (RBN + HamDB in Rust; park/summit coords host-resolved), live audio (`connect` → `SdrConnection` + `SdrAudioListener` PCM callback), QSY + receiver-quality monitors (stoppable `SdrMonitorHandle`), `kiwi_mode_info` free fn |
| `panadapter_api.rs` | SDR panadapter / waterfall surface over `cw_sdr`: `PanadapterHandle` (start/`set_tuning`/`set_tuning_mode`/`set_display`/stop) + host-implemented `PanadapterListener` (VFO-centered 0..1 lines), `FfiPanadapterSource` (rtl_tcp / Soapy / tone), `FfiTuningMode` (IF tap / direct RF), `panadapter_enumerate_soapy_devices` |
| `wsjtx_api.rs` | WSJT-X surface (CAR-281): `WsjtxApi` object (async `start(host, port, delegate)` → bound port, `stop`, `is_running`, `local_port`; receive loop on the UniFFI tokio runtime, `select!` on shutdown) + host-implemented `WsjtxListenerDelegate` (`on_message(FfiWsjtxMessage, from)` / `on_error` / `on_stopped`); `FfiWsjtx{Heartbeat,Status,Decode,QsoLogged,LoggedAdif}` records + `FfiWsjtxMessage` enum (`Close{id}`/`Other{kind,id}`) mirroring `cw_net::wsjtx` with `QDateTime`→Unix seconds and `QTime`→ms-since-midnight; `WsjtxError` (bind / already-running / decode / the `cw_store::WsjtxImportError` variants); free `wsjtx_map_qso_logged` / `wsjtx_map_logged_adif` (→ `FfiQso` via `cw_store::wsjtx_import`), `wsjtx_dedup_key`, `wsjtx_decode_datagram`, `wsjtx_default_port`. App wiring is CAR-282 |
| `equipment_api.rs` | `EquipmentApi` object — fuzzy catalog search (parse-once cache over `KV_EQUIPMENT_JSON`) + equipment construction (`add_custom_item`/`add_catalog_item`, persisted via `FieldStore`) |
| `reference_data_api.rs` | Async `ReferenceDataApi` object (tokio) — External Data downloads: POTA parks / SOTA summits / WWFF directory (CSV → store tables, iOS TTLs), equipment catalog (ETag → kv), FCC callsign SQLite (sha256 short-circuit, gunzip to `data_dir`, `fcc_lookup`), SOTA zones (chunked, pending-aware), `status()` snapshot for the UI |
| `contest_api.rs` | Contest surface (2026-07-04 port): async `ContestApi` (refresh → `contest_definition` cache, offline `summaries`/`definition` display DTO w/ `raw_json`), stateful `ContestEngineApi` scorer (by contest id or raw JSON; injected `now`), stateless `contest_*` fns (exchange parse, Cabrillo, schedule occurrences, off-time, band-change, normalize/WPX, enrichment prefill) |
| `brag_sheet_api.rs` | `BragSheetApi` object — Brag Sheet facade: catalog/categories/presets accessors, load/save `BragConfiguration` to cw-store kv, `compute_brag` (delegates to `cw_store::compute_configured_brag`, overlays club stats from the store's own `club`/`club_member` tables), config-mutation transforms, `import_legacy_config` (one-time migration from the iOS UserDefaults blob) |
| `map_api/` | `MapApi` object + records (`mod.rs`/`records.rs`/`aggregate.rs`/`cards.rs`/`filter.rs`): one-call QSO map view-model (`qso_map` → annotations/clusters/arcs/bounds/stats), embedded map cards, plus free geo exports (`great_circle_arc`, `map_bounds_for`, `maidenhead_tile_bounds`/`maidenhead_grid_bounds`, timeline curves, `compute_map_statistics`) |
| `park_map_api/` | `ParkMapApi` object + records (`mod.rs`/`records.rs`) — reference-map core (map port phase C): sync `pins_in_box`/`search`/`sota_zones_for`; async cache-through GIS fetch `park_boundaries`/`park_boundaries_in_box`/`park_boundary_full`/`trails_in_box`/`admin_boundaries_in_box` (read→fetch-miss→upsert→evict on `gis_boundary_cache`; warm-cache network failure degrades to cache, cold throws); `wwff_borrowed_boundaries` (KFF-####→US-#### POTA-polygon loan, chunked ≤20, cache-first); `find_multipliers` rosette (rings from cache → `cw_domain::multiplier` → per-location merge, score-desc/title-asc); free `tota_tiles_in_region`/`point_in_ring`. Fetch defaults parks/trails 50, admin 500 |
| `propagation_api/` | `PropagationApi` object + records (`mod.rs`/`records.rs`/`tests.rs`) — shared "How's my antenna?" session engine (map port phase D): `start_session`/`poll`/`stop`/`results`, state behind a `Mutex` (spot_engine pattern). `poll()` runs one RBN (`cw_net::RbnClient` activities proxy) + rate-limited PSK Reporter (`cw_net::PskReporterClient`) round, ingests/dedups (`source-CALL-freqHz-secondBucket`)/band-filters/callsign-suffix-matches, enriches missing skimmer grids (reported grid → `callbook_location` cache → `QrzApi::locate` QRZ→HamDB fill, NOT HamDB-only), projects distance/bearing via `cw_domain::maidenhead`. Cadence/window consts ported verbatim (`RBN_POLL_INTERVAL_SECS=30`, `PSKR_POLL_INTERVAL_SECS=305`, `PSKR_LOOKBACK_SECS=-1800`, RBN `hours:1,limit:200`); PSK 5-min floor enforced in `poll`. Fetch behind a `SpotFeed`/`GridResolver` enum with `cfg(test)` canned variants for network-free windowing/enrichment/results tests. Free `propagation_poll_cadence()` |
| `satellite_api/` | `SatelliteApi` object + records (`mod.rs`/`records.rs`/`tests.rs`) — cache-through `refresh` (single-flight via an async gate; a forced call reuses a fresh refresh that completed while it waited; 15 min stale-serving backoff after a failed fetch; SatNOGS on a 120 s `HttpClient::with_timeout` client), `load_cached` (catalog from the cache at any age, no network — hosts render first, refresh in the background); the refresh itself caches SatNOGS TLEs/transmitters via `satellite_data_cache` (6 h TTL, stale-degrade; AMSAT soft-fail→empty), `catalog`/`search_items`, stateless `positions(epoch, observer?)` tick (host-polled, scrub = now+offset), `ground_track`, `look` (rates + Doppler factor), async `pass_forecast`/`upcoming_passes`/`mutual_passes`/`mutual_profile`/`plan_alerts` (blocking-pool sweeps), async `community_activity` (AMSAT grid: cache-through `/activity` histogram at 20 min TTL, each row joined to the catalog name + best SatNOGS transmitter by NORAD, the observer's next pass (24 h), and own `SAT_NAME` QSO counts from the store; hourly buckets merged to the requested cell width), async `community_reports` (one bird's raw 24 h reports at 10 min TTL, each placed at the reporter's grid via maidenhead, plus the previous-orbit summary from the catalog propagator's period), async `submit_community_report` (validates name/callsign/verdict/not-future, canonicalises the verdict, files with AMSAT via the feed; `amsat_report_values()` / `amsat_attribution()` free functions for hosts), `coastline_continents()` for host-drawn charts, `create_pass_session` (born-completed quick-log session row built Rust-side so hosts never hand-construct `LoggingSession`). Feed behind a `SatFeed` enum with `cfg(test)` canned variants; favorites are host-side and passed per call |
| `share_render_api.rs` | Free `render_share_map(FfiShareMapStyle, FfiShareMapInput) -> FfiShareMapImage{png_bytes, ring_labels}` (map port phase D) — store-less passthrough onto `cw_domain::share_render` flat/azimuthal renderers by style; `FfiSharePin` two-mode color (`Count` ramp / `Rgba` arbitrary, mirrors Swift cluster vs RST-marker paths), `FfiShareTrace`, optional grid-center resolution, `lon_span` clamped ≤360°; azimuthal returns `FfiRingLabel` anchors, flat returns none. Also `compute_flat_share_viewport(Vec<FfiCoordinate>, w, h) -> FfiShareViewport{center_lat/lon, lat/lon_span}` — free export wrapping `cw_domain::share_render::compute_flat_share_viewport` (recovered `FlatMapRenderer.computeViewport` framing); Swift feeds its center+spans into `FfiShareMapInput` for the flat styles |
| `adif_api.rs` | `AdifApi` object (store-backed): `export_activation(park_reference, park_name?, callsign, date yyyy-MM-dd, program_version) -> String` (map port phase D) — the iOS `ADIFExportSheet`/`ADIFExportService.generateADIF` single-activation path; scopes `qso` rows by `(park, my_callsign, UTC-day)` non-metadata/visible via `Store::fetch_activation_qsos`, maps rows→`AdifWriteRecord` (freq kHz→MHz, UTC date/time formats), renders via `cw_domain::adif_writer::write_adif`. Empty activation → `first_qso_date="unknown"`. `export_bulk(activations, program_version)` (combined multi-activation file), `fetch_activation_qsos`. `export_session(session_id, park_name?, program_version) -> FfiAdifSessionExport{adif, qso_count, first_qso_date}?` — whole-session export scoped by `logging_session_id` (merged days/parks, roves, park-less QSOs): QSO's own park else the session's, session `sota_reference` as `MY_SOTA_REF`, activator = `station_callsign` ?? `my_callsign`; `None` for an unknown session. `import_adif(content, FfiAdifImportOptions{my_callsign, upload_qrz, upload_pota}) -> FfiAdifImportResult{total_records, imported, duplicates, errors}` — the shared ADIF-file importer (port of iOS `ImportService.importADIF`): parse → `cw_store::filter_for_multi_op` → `qso_from_adif_record` (`"adifFile"` provenance, fresh v4 ids) → skip records whose `deduplication_key` is in `Store::deduplication_keys()` or earlier in the file → one-transaction insert + QRZ/POTA `mark_needs_upload` → one observer notification per touched table |
| `upload.rs` | Shared `mark_needs_upload` (port of `QSO.markNeedsUpload`) used by the activity-log + session APIs; no-op for non-upload services |
| `sync.rs` | UniFFI surface for `cw_store::sync_dirty`: `FieldStore::mark_all_dirty`/`clear_dirty` keyed by `JournalEntityType` raw value, with entity_type→`FfiStoreTable` notify mapping. Backs the Phase-1 journal-seam re-point (`dirty_only` filters live on the per-entity fetch methods) |
| `entities/mod.rs` | Declares the per-entity FFI modules |
| `entities/*.rs` | One module per synced entity (logging_session, service_presence, session_spot, activation_metadata, activity_log, equipment_item, loadout, radio_macro, websdr_recording, websdr_favorite, upload_destination, cloud_sync_metadata): `Ffi<Entity>` record + `From` conversions + `#[uniffi::export] impl FieldStore` CRUD block; each upsert fires `notify` with the entity's `FfiStoreTable` |
| `entities/pota_park.rs` | `FfiPotaPark` + batched `upsert_pota_parks`/`pota_park_count`/`fetch_pota_park`. Reference data (pota.app download write-through), **not** synced — no observation `notify`. Backs the POTA-awards `statesActivated` port |
| `observation.rs` | `@Query`-replacement callback bridge: `FfiStoreTable`/`FfiChangeKind`/`FfiStoreChange`, foreign `StoreObserver` trait, `ObserverRegistry`, `add_observer`/`remove_observer`, `notify` (fires with DB lock released — reentrancy-safe). 3 tests incl. no-deadlock re-entry |
| `bin/uniffi-bindgen.rs` | Library-mode bindgen launcher (`cargo run -p cw-ffi --bin uniffi-bindgen`) |

## cw-sdr (`cw-sdr/src/`)

SDR IQ capture + spectrum pipeline for the CW Sweep waterfall (no FFI; surfaced via `cw-ffi/panadapter_api.rs`).

| File | Purpose |
|------|---------|
| `lib.rs` | Crate root, re-exports |
| `error.rs` | `SdrError` (SoapyUnavailable / Device / Io / Config) |
| `source.rs` | `IqSource` trait (blocking pull reader), `SourceSpec`, `SourceConfig`, `open()` factory |
| `rtl_tcp.rs` | rtl_tcp protocol client (RTL-SDR `rtl_tcp`, SDRplay `rsp_tcp`): header check, 5-byte commands, u8 IQ conversion |
| `soapy.rs` | macOS-only SoapySDR 0.8 backend via runtime `dlopen` (libloading) — no link-time dependency; `enumerate()` |
| `tone.rs` | Synthetic carriers + noise `IqSource` for tests / hardware-free dev |
| `spectrum.rs` | `SpectrumEngine`: Blackman-Harris windowed FFT (rustfft), averaging, dBFS, DC notch, FFT-size planning |
| `normalize.rs` | dB → 0..1 with auto-tracked noise floor (20th percentile EMA) |
| `mapping.rs` | `RigTuning`, `TuningMode` (IF tap w/ inversion + per-mode cal, direct RF w/ retune hysteresis), affine `FrequencyMap`, `project()` onto VFO-centered RF bins (max-pool) |
| `pipeline.rs` | `Panadapter` worker thread (source → engine → mapping → normalizer → `LineSink`), TX blanking, live retune / settings updates |

## scripts (`scripts/`)

| File | Purpose |
|------|---------|
| `generate-swift-bindings.sh` | Build cdylib + run uniffi-bindgen → `target/generated/swift/` |
| `build-xcframework.sh` | Cross-compile 4 Apple slices, lipo macOS, assemble `CwFfi.xcframework`, stage into `swift/packages/CarrierWaveCore/{Vendored,Sources/CarrierWaveCwFfi}` |
