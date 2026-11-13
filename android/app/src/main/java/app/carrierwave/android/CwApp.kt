package app.carrierwave.android

import android.app.Application
import android.content.Context
import android.net.Uri
import android.os.Build
import app.carrierwave.android.auth.AndroidSecureStore
import app.carrierwave.android.data.FavoriteSatellites
import app.carrierwave.android.data.SatelliteModeFilter
import app.carrierwave.android.data.LogbookRepository
import app.carrierwave.android.notifications.SatelliteAlertScheduler
import app.carrierwave.android.notifications.SatelliteRefreshWorker
import app.carrierwave.android.data.LoggerKeyboardConfig
import app.carrierwave.android.data.ServerConfig
import app.carrierwave.android.data.SpotEngineProvider
import app.carrierwave.android.data.SyncConfig
import app.carrierwave.android.data.TuneInManager
import app.carrierwave.android.data.UserProfile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import uniffi.cw_ffi.ActivityLogApi
import uniffi.cw_ffi.AmtApi
import uniffi.cw_ffi.AuthApi
import uniffi.cw_ffi.FfiLinkOutcome
import uniffi.cw_ffi.ClubsApi
import uniffi.cw_ffi.AdifApi
import uniffi.cw_ffi.ContestApi
import uniffi.cw_ffi.EnrichmentApi
import uniffi.cw_ffi.FfiClubSyncSummary
import uniffi.cw_ffi.FfiFriendsSummary
import uniffi.cw_ffi.FfiQsoFilter
import uniffi.cw_ffi.FieldStore
import uniffi.cw_ffi.LoggerCommandApi
import uniffi.cw_ffi.MapApi
import uniffi.cw_ffi.ParkMapApi
import uniffi.cw_ffi.SessionApi
import uniffi.cw_ffi.SessionWizardApi
import uniffi.cw_ffi.FriendsApi
import uniffi.cw_ffi.QrzApi
import uniffi.cw_ffi.ReferenceDataApi
import uniffi.cw_ffi.SatelliteApi
import uniffi.cw_ffi.ScpApi
import uniffi.cw_ffi.SdrApi
import uniffi.cw_ffi.syncRunOnce
import java.io.File
import java.security.SecureRandom

/**
 * Opens the encrypted SQLCipher-backed store (the same Rust `cw-store` the iOS
 * app uses) once, at process start, and exposes it to the UI as a shared
 * [LogbookRepository].
 */
class CwApp : Application() {

    lateinit var repository: LogbookRepository
        private set

    /** The shared encrypted store, exposed for club reads (clubs/members lookups). */
    lateinit var store: FieldStore
        private set

    /** Shared OAuth client (Rust `cw_net::AuthClient`), secrets in the Keystore. */
    lateinit var authApi: AuthApi
        private set

    /**
     * Another Morse Trainer stats client (Rust `cw_net::AmtClient`): email-link
     * sign-in, token rotation and the cached `/v1/me/stats` snapshot, tokens in
     * the Keystore-backed secure store.
     */
    lateinit var amtApi: AmtApi
        private set

    /**
     * Fires after an AMT sign-in, sign-out or stats refresh so the Home screen
     * re-reads the streak/practice days without owning the AMT flow.
     */
    val amtChanged = MutableSharedFlow<Unit>(extraBufferCapacity = 1)

    /** Shared clubs API (Rust `cw_net::ClubsClient`) writing into the local store. */
    lateinit var clubsApi: ClubsApi
        private set

    /** Shared friends + activity-feed API (Rust `cw_net::FriendsClient`). */
    lateinit var friendsApi: FriendsApi
        private set

    /** Shared live-spot engine (Rust poll loop + merge/enrich/needs pipeline). */
    lateinit var spotEngine: SpotEngineProvider
        private set

    /**
     * Shared QRZ callbook enrichment (Rust `cw_net::QrzClient`), creds in the
     * Keystore. Store-backed ([QrzApi.withStore]) so [QrzApi.locate] can
     * read-through against the `callbook_location` cache for map refinement.
     */
    lateinit var qrzApi: QrzApi
        private set

    /** Shared callsign enrichment (DXCC/SKCC/clubs), datasets cached in the store. */
    lateinit var enrichmentApi: EnrichmentApi
        private set

    /** Super Check Partial suggestions (MASTER.SCP, kv-cached in the store). */
    lateinit var scpApi: ScpApi
        private set

    /** Hunter-log lifecycle + QSO logging (Rust `ActivityLogManager` port). */
    lateinit var activityLogApi: ActivityLogApi
        private set

    /** Shared KiwiSDR API (directory, Tune-In receiver selection, audio). */
    lateinit var sdrApi: SdrApi
        private set

    /** External Data downloads (POTA/SOTA/WWFF/FCC/equipment/zones). */
    lateinit var referenceDataApi: ReferenceDataApi
        private set

    /** Contest definitions cache (`/v1/contests`), shared Rust ContestApi. */
    lateinit var contestApi: ContestApi
        private set

    /** Session-start wizard kernel (Rust `SessionWizardApi`): assembly, defaults,
     * frequency/park suggestions, pack checklist, TOTA derivations. */
    lateinit var sessionWizardApi: SessionWizardApi
        private set

    /** Activation-session lifecycle (Rust `SessionApi`): pause/resume/end/log. */
    lateinit var sessionApi: SessionApi
        private set

    /** Map tab view-model kernel (Rust `MapApi`): filtered annotations/arcs/stats. */
    lateinit var mapApi: MapApi
        private set

    /** POTA activation ADIF export + activation QSO fetch (Rust `AdifApi`). */
    lateinit var adifApi: AdifApi
        private set

    /** Park/summit search + viewport pins (Rust `ParkMapApi`), same GIS-cache
     * pattern as [referenceDataApi]. */
    lateinit var parkMapApi: ParkMapApi
        private set

    /** Logger command handler (Rust `LoggerCommandApi`): executes FREQ/MODE/NOTE/
     * MYCALL/session-metadata + returns intents for spot/panels. */
    lateinit var loggerCommandApi: LoggerCommandApi
        private set

    /** Shared satellite engine: catalog/positions/passes/alert planning. */
    lateinit var satelliteApi: SatelliteApi
        private set

    /** Tune-In playback controller for the hunter log's spot feed. */
    lateinit var tuneIn: TuneInManager
        private set

    /** Activities-server base URL currently in use (clubs + OAuth + RBN proxy). */
    var baseUrl: String = ServerConfig.DEFAULT_BASE_URL
        private set

    /** Operator callsign, stamped on logged QSOs. Editable from Account. */
    @Volatile
    var userCallsign: String = ""
        private set

    /** Operator home grid — live distance/bearing + map centering. Editable from Account. */
    @Volatile
    var userHomeGrid: String = ""
        private set

    /** App-lifetime scope for fire-and-forget warm-ups (enrichment datasets). */
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Results of magic-link deep-link completions, observed by the UI so it can
     * surface "Signed in" and jump to Account. Buffered so an event emitted
     * before a collector attaches (cold launch via link) isn't lost. */
    private val _authDeepLink = MutableSharedFlow<AuthDeepLinkResult>(replay = 1, extraBufferCapacity = 4)
    val authDeepLink: SharedFlow<AuthDeepLinkResult> = _authDeepLink.asSharedFlow()

    /** NORAD ids from tapped pass-alert notifications; replay=1 so a tap that
     * cold-launches the app is delivered once the UI collects. The collector
     * clears the replay cache after handling so recreation doesn't re-open. */
    private val _satelliteOpenRequests = MutableSharedFlow<UInt>(replay = 1, extraBufferCapacity = 4)
    val satelliteOpenRequests: SharedFlow<UInt> = _satelliteOpenRequests.asSharedFlow()

    fun requestOpenSatellite(noradId: UInt) {
        _satelliteOpenRequests.tryEmit(noradId)
    }

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    fun consumeSatelliteOpenRequest() {
        _satelliteOpenRequests.resetReplayCache()
    }

    override fun onCreate() {
        super.onCreate()
        val dbPath = File(filesDir, "logbook.sqlcipher").absolutePath
        store = FieldStore.open(dbPath, loadOrCreateKey(this))
        userCallsign = UserProfile.callsign(this)
        userHomeGrid = UserProfile.homeGrid(this)
        LoggerKeyboardConfig.load(this)
        repository = LogbookRepository(store, userHomeGrid, appScope)
        baseUrl = ServerConfig.baseUrl(this)
        authApi = AuthApi(AndroidSecureStore(this), baseUrl, "android", Build.MODEL)
        amtApi = AmtApi(AndroidSecureStore(this), "android", Build.MODEL)
        clubsApi = ClubsApi(store, baseUrl)
        friendsApi = FriendsApi(store, baseUrl)
        qrzApi = QrzApi.withStore(AndroidSecureStore(this), store)
        enrichmentApi = EnrichmentApi(store, baseUrl)
        scpApi = ScpApi(store)
        spotEngine = SpotEngineProvider(
            appScope,
            baseUrl,
            userCallsign,
            userHomeGrid,
            File(filesDir, "spot_enrichment_cache.json").absolutePath,
        ) {
            enrichmentApi.ctyContent()
        }
        activityLogApi = ActivityLogApi(store)
        sdrApi = SdrApi(baseUrl, kiwiDirectoryCachePath())
        tuneIn = TuneInManager({ sdrApi }, { userHomeGrid })
        referenceDataApi = ReferenceDataApi(store, baseUrl, referenceDataDir())
        contestApi = ContestApi(store, baseUrl)
        sessionWizardApi = SessionWizardApi(store)
        sessionApi = SessionApi(store)
        mapApi = MapApi(store)
        adifApi = AdifApi(store)
        parkMapApi = ParkMapApi(store, baseUrl)
        loggerCommandApi = LoggerCommandApi(store)
        satelliteApi = SatelliteApi(store, baseUrl)
        FavoriteSatellites.load(this)
        SatelliteModeFilter.load(this)
        // Pass alerts: replan when favorites change, on every app start, and
        // every 6 h via WorkManager (reschedule() no-ops when alerts are off).
        FavoriteSatellites.onChange = {
            appScope.launch { SatelliteAlertScheduler.reschedule(this@CwApp) }
        }
        SatelliteRefreshWorker.schedulePeriodic(this)
        appScope.launch { SatelliteAlertScheduler.reschedule(this@CwApp) }
        // Launched after the clients above exist — autoSyncIfEnabled and
        // autoSyncSocial read authApi.
        appScope.launch {
            runCatching { fixLegacyEpochsIfNeeded() }
            if (!UserProfile.isSet(this@CwApp)) runCatching { seedProfileFromLogbook() }
            runCatching { autoSyncIfEnabled() }
            autoSyncSocial()
        }
        warmEnrichment()
    }

    /** In-flight shared syncs — app-lifetime so leaving a screen can't cancel them mid-apply. */
    @Volatile
    private var clubsSync: Deferred<FfiClubSyncSummary>? = null

    @Volatile
    private var friendsSync: Deferred<FfiFriendsSummary>? = null

    /** The in-flight shared club sync, if one is currently running. */
    val clubsSyncInFlight: Deferred<FfiClubSyncSummary>? get() = clubsSync?.takeIf { it.isActive }

    /** The in-flight shared friends sync, if one is currently running. */
    val friendsSyncInFlight: Deferred<FfiFriendsSummary>? get() = friendsSync?.takeIf { it.isActive }

    /**
     * Club sync shared across screens: joins the in-flight sync if one is
     * running, else starts one on the app scope (IO — the UniFFI future is
     * polled on the caller's dispatcher and its body does blocking SQLCipher
     * writes). Callers `await()` the result; cancelling the caller leaves the
     * sync running.
     */
    @Synchronized
    fun syncClubsShared(): Deferred<FfiClubSyncSummary> =
        clubsSync?.takeIf { it.isActive } ?: appScope.async {
            clubsApi.syncClubs(authApi.validAccessToken(), emptyList())
        }.also { clubsSync = it }

    /** Friends sync shared across screens — same contract as [syncClubsShared]. */
    @Synchronized
    fun syncFriendsShared(): Deferred<FfiFriendsSummary> =
        friendsSync?.takeIf { it.isActive } ?: appScope.async {
            friendsApi.syncFriends(authApi.validAccessToken())
        }.also { friendsSync = it }

    /**
     * Fire-and-forget friends + clubs refresh when signed in — app launch and
     * right after sign-in (mirrors iOS, which syncs clubs at launch/foreground).
     */
    fun autoSyncSocial() {
        appScope.launch {
            if (!authApi.hasSession()) return@launch
            runCatching { syncFriendsShared().await() }
            runCatching { syncClubsShared().await() }
        }
    }

    /**
     * Complete magic-link sign-in from a tapped deep link (App Link
     * `…/v1/auth/verify/complete?code=…` or `carrierwave://auth?code=…`). Marks
     * the code clicked and, if this device started the sign-in, drives it to
     * completion via the shared Rust [AuthApi.completeFromLink]; emits the result
     * for the UI. Runs on [appScope] (IO) — the UniFFI future is polled on the
     * caller's dispatcher and does blocking network + Keystore writes.
     */
    fun handleAuthDeepLink(uri: Uri) {
        val code = uri.getQueryParameter("code")?.takeIf { it.isNotBlank() } ?: return
        appScope.launch {
            val result = try {
                when (authApi.completeFromLink(code)) {
                    FfiLinkOutcome.SIGNED_IN -> {
                        autoSyncSocial()
                        AuthDeepLinkResult.SignedIn
                    }
                    FfiLinkOutcome.ATTACHED_TO_ACCOUNT -> {
                        autoSyncSocial()
                        AuthDeepLinkResult.AttachedToAccount
                    }
                    FfiLinkOutcome.ACKNOWLEDGED_REMOTELY -> AuthDeepLinkResult.AcknowledgedRemotely
                    FfiLinkOutcome.NOT_COMPLETED ->
                        AuthDeepLinkResult.Failed("That sign-in link has expired or was already used.")
                }
            } catch (e: Exception) {
                AuthDeepLinkResult.Failed(e.message)
            }
            _authDeepLink.emit(result)
        }
    }

    /**
     * Download the CTY/SKCC reference datasets once (if not cached) and refresh
     * the server membership dataset (CWops, etc.; 12h-gated internally). All
     * best-effort.
     */
    private fun warmEnrichment() {
        appScope.launch {
            if (!enrichmentApi.isLoaded()) {
                runCatching { enrichmentApi.refresh() }
                // A fresh CTY download should reach a spot engine that was
                // built before the download finished.
                spotEngine.feedCty()
            }
            runCatching { enrichmentApi.refreshMemberships(false) }
            // MASTER.SCP for command-bar suggestions (7-day TTL inside).
            runCatching { scpApi.refresh(false) }
        }
    }

    /**
     * One-time upgrade path: the old Android logger stamped
     * `qso_date`/`imported_at`/`modified_at` in Unix **milliseconds**; the
     * cw-store contract (iOS + the shared Rust APIs) is Unix **seconds**.
     * Rewrites any millis-scale value back to seconds. Values above the
     * threshold (~year 5138 as seconds) can only be millis.
     */
    private suspend fun fixLegacyEpochsIfNeeded() {
        val prefs = getSharedPreferences("cw", Context.MODE_PRIVATE)
        if (prefs.getBoolean("epoch_fixup_done", false)) return
        var offset = 0L
        while (true) {
            val page = store.fetchQsos(FfiQsoFilter(callsignPrefix = null, band = null, mode = null, since = null, dirtyOnly = false), FIXUP_PAGE, offset)
            for (qso in page) {
                var changed = false
                if (qso.qsoDate > MILLIS_THRESHOLD) {
                    qso.qsoDate /= 1_000L
                    changed = true
                }
                if (qso.importedAt > MILLIS_THRESHOLD) {
                    qso.importedAt /= 1_000L
                    changed = true
                }
                qso.modifiedAt?.let { if (it > MILLIS_THRESHOLD) { qso.modifiedAt = it / 1_000L; changed = true } }
                if (changed) store.upsertQso(qso)
            }
            if (page.size < FIXUP_PAGE) break
            offset += FIXUP_PAGE
        }
        prefs.edit().putBoolean("epoch_fixup_done", true).apply()
        repository.refresh()
    }

    /**
     * One-time upgrade path: installs that logged QSOs before the profile
     * existed keep their identity — pull callsign/grid off the newest QSO.
     */
    private fun seedProfileFromLogbook() {
        val latest = store.fetchQsos(FfiQsoFilter(callsignPrefix = null, band = null, mode = null, since = null, dirtyOnly = false), FIXUP_PAGE, 0L)
            .maxByOrNull { it.qsoDate }
        val callsign = latest?.myCallsign.orEmpty()
        val grid = latest?.myGrid.orEmpty()
        if (callsign.isNotBlank() || grid.isNotBlank()) {
            updateProfile(callsign, grid)
        }
    }

    /**
     * One best-effort Carrier Wave Sync pass at launch when enrolled + signed
     * in. Manual runs live in the Account screen's sync card.
     */
    private suspend fun autoSyncIfEnabled() {
        val dataKey = SyncConfig.dataKey(this, baseUrl) ?: return
        if (!authApi.hasSession()) return
        val bearer = authApi.validAccessToken()
        val since = SyncConfig.lastSeq(this, baseUrl)
        val result = syncRunOnce(store, baseUrl, bearer, dataKey, since)
        SyncConfig.storeCursor(this, baseUrl, result.highWater, System.currentTimeMillis() / 1_000L)
        if (result.pulled > 0u) repository.refresh()
    }

    /** Persist a new operator profile and propagate it to live consumers. */
    fun updateProfile(callsign: String, homeGrid: String) {
        UserProfile.save(this, callsign, homeGrid)
        userCallsign = UserProfile.callsign(this)
        userHomeGrid = UserProfile.homeGrid(this)
        repository.homeGrid = userHomeGrid
        spotEngine.updateUserContext(userCallsign, userHomeGrid)
        // Re-emit the snapshot so grid-derived stats (Best DX, distances) recompute.
        appScope.launch { runCatching { repository.refresh() } }
    }

    /**
     * Point the app at a different activities server. Rebuilds the OAuth + clubs
     * clients against [url], persists it, and updates [baseUrl]. Returns `true`
     * on success; on failure (e.g. an unparseable URL) the existing clients are
     * left untouched. Screens pick up the new clients on their next creation.
     */
    fun updateBaseUrl(url: String): Boolean {
        val normalized = ServerConfig.normalize(url)
        return try {
            val newAuth = AuthApi(AndroidSecureStore(this), normalized, "android", Build.MODEL)
            val newClubs = ClubsApi(store, normalized)
            val newFriends = FriendsApi(store, normalized)
            val newEnrichment = EnrichmentApi(store, normalized)
            val newSdr = SdrApi(normalized, kiwiDirectoryCachePath())
            val newReferenceData = ReferenceDataApi(store, normalized, referenceDataDir())
            val newContests = ContestApi(store, normalized)
            val newParkMap = ParkMapApi(store, normalized)
            val newSatellite = SatelliteApi(store, normalized)
            authApi = newAuth
            clubsApi = newClubs
            friendsApi = newFriends
            enrichmentApi = newEnrichment
            sdrApi = newSdr
            referenceDataApi = newReferenceData
            contestApi = newContests
            parkMapApi = newParkMap
            satelliteApi = newSatellite
            baseUrl = normalized
            ServerConfig.setBaseUrl(this, normalized)
            spotEngine.updateBaseUrl(normalized)
            warmEnrichment()
            true
        } catch (_: Exception) {
            false
        }
    }

    private companion object {
        /** Page size for the startup epoch-fixup / profile-seed scans. */
        const val FIXUP_PAGE = 1000L

        /**
         * Epoch values above this are milliseconds: as seconds it's the year
         * ~5138, as millis it's 1973 — no valid QSO date is ambiguous.
         */
        const val MILLIS_THRESHOLD = 100_000_000_000L
    }

    /** JSON cache for the KiwiSDR public directory between launches. */
    private fun kiwiDirectoryCachePath(): String =
        File(cacheDir, "kiwisdr_directory.json").absolutePath

    /**
     * Directory for the FCC callsign SQLite (hundreds of MB) — filesDir,
     * not cacheDir, so the OS can't purge it out from under a lookup.
     */
    private fun referenceDataDir(): String =
        File(filesDir, "refdata").absolutePath

    private fun loadOrCreateKey(ctx: Context): String {
        val prefs = ctx.getSharedPreferences("cw", Context.MODE_PRIVATE)
        prefs.getString("db_key", null)?.let { return it }
        val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val key = bytes.joinToString("") { "%02x".format(it) }
        prefs.edit().putString("db_key", key).apply()
        return key
    }

}

/** Outcome of completing sign-in from a tapped magic link, surfaced to the UI. */
sealed interface AuthDeepLinkResult {
    /** Signed in on this device (new account). */
    data object SignedIn : AuthDeepLinkResult

    /** The callsign was attached to an existing account. */
    data object AttachedToAccount : AuthDeepLinkResult

    /** Marked clicked here, but sign-in started on another device, which finishes it. */
    data object AcknowledgedRemotely : AuthDeepLinkResult

    /** The link was invalid/expired, or completion failed. */
    data class Failed(val message: String?) : AuthDeepLinkResult
}
