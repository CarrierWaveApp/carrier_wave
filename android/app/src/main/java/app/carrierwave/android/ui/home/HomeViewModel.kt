package app.carrierwave.android.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import app.carrierwave.android.data.LogbookRepository
import app.carrierwave.android.ui.common.utcDayKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.AmtApi
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FieldStore
import uniffi.cw_ffi.maidenheadDistanceKm
import uniffi.cw_ffi.maidenheadIsValid
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.TextStyle
import java.time.temporal.TemporalAdjusters
import java.util.Locale

/** A single best-DX contact for the dashboard hero. */
data class BestDx(val callsign: String, val grid: String, val km: Double)

/**
 * One heatmap cell: QSO count for a UTC day + its 0–4 intensity level, plus the
 * Another Morse Trainer practice level for that calendar day (0 = none, 1–4 =
 * AMT's own tile shade) and the practice seconds behind it.
 */
data class HeatCell(
    val count: Int,
    val level: Int,
    val amtLevel: Int = 0,
    val amtSeconds: Int = 0,
)

/**
 * 53 week-columns × 7 weekday-rows (Sunday-first), oldest week first, matching
 * the iOS activity grid. `null` cells are days after today. `monthLabels` maps
 * week-column index → short month name, set on the column where a month starts.
 */
data class HeatmapData(
    val weeks: List<List<HeatCell?>> = emptyList(),
    val monthLabels: Map<Int, String> = emptyMap(),
    val total: Int = 0,
    /** Days with Another Morse Trainer practice inside the grid's range. */
    val amtDays: Int = 0,
)

/**
 * Another Morse Trainer practice stats for the Home screen, read from the Rust
 * `AmtApi` snapshot (cached offline) and refreshed on open.
 */
data class AmtHome(
    val signedIn: Boolean = false,
    val streakCurrent: Long = 0L,
    val streakLongest: Long = 0L,
    /** `yyyy-MM-dd` (local calendar) → practice level 1–4. */
    val levels: Map<String, Int> = emptyMap(),
    /** `yyyy-MM-dd` (local calendar) → practice seconds. */
    val seconds: Map<String, Int> = emptyMap(),
    val loaded: Boolean = false,
)

/**
 * Award-progress stats from the shared Rust store aggregates (the same SQL
 * the iOS dashboard's Rust overlay runs): on-air streak, WAS states, DXCC
 * entities worked.
 */
data class AwardsStats(
    val streakCurrent: Long = 0L,
    val streakLongest: Long = 0L,
    /** Distinct US states worked (WAS progress, /50). */
    val wasCount: Int = 0,
    /** Distinct DXCC entities worked. */
    val dxccCount: Int = 0,
    val loaded: Boolean = false,
)

data class HomeStats(
    val total: Int = 0,
    val today: Int = 0,
    val uniqueCalls: Int = 0,
    val uniqueGrids: Int = 0,
    /** band → count, sorted by count desc. */
    val bands: List<Pair<String, Int>> = emptyList(),
    /** mode → count, sorted by count desc. */
    val modes: List<Pair<String, Int>> = emptyList(),
    /** Bands worked today (for the "On Air today" strip). */
    val bandsToday: List<String> = emptyList(),
    val bestDx: BestDx? = null,
    val recent: List<FfiQso> = emptyList(),
)

class HomeViewModel(
    private val repo: LogbookRepository,
    private val store: FieldStore,
    private val amtApi: AmtApi,
    private val amtChanged: Flow<Unit> = emptyFlow(),
) : ViewModel() {

    val homeGrid: String = repo.homeGrid

    val stats: StateFlow<HomeStats> = repo.qsos
        .map { computeStats(it, repo.homeGrid) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HomeStats())

    private val _heatmap = MutableStateFlow(HeatmapData())
    val heatmap: StateFlow<HeatmapData> = _heatmap.asStateFlow()

    private val _awards = MutableStateFlow(AwardsStats())
    val awards: StateFlow<AwardsStats> = _awards.asStateFlow()

    private val _amt = MutableStateFlow(AmtHome())
    val amt: StateFlow<AmtHome> = _amt.asStateFlow()

    /** The last per-day QSO counts, kept so an AMT update can rebuild the grid alone. */
    private var lastDayCounts: Map<String, Int> = emptyMap()

    init {
        viewModelScope.launch { repo.refresh() }
        // Recompute the activity grid whenever the shared snapshot changes (the
        // day counts come from their own uncapped paged fetch, not the snapshot).
        viewModelScope.launch {
            repo.qsos.collect {
                runCatching {
                    lastDayCounts = repo.dayCounts()
                    _heatmap.value = buildHeatmap(lastDayCounts, _amt.value)
                }
                runCatching { _awards.value = computeAwards() }
            }
        }
        // Another Morse Trainer: show the cached snapshot at once, then refresh
        // (throttled by the stats' own fetch time), and re-read after sign-in /
        // sign-out / a manual refresh elsewhere.
        viewModelScope.launch {
            loadAmt(refresh = true)
            amtChanged.collect { loadAmt(refresh = false) }
        }
    }

    /** Home came back to the foreground: re-fetch AMT stats if they're stale. */
    fun refreshAmt() {
        viewModelScope.launch { loadAmt(refresh = true) }
    }

    /** Re-read the AMT snapshot (and optionally fetch fresh stats), off-main. */
    private suspend fun loadAmt(refresh: Boolean) {
        val next = withContext(Dispatchers.IO) {
            val signedIn = amtApi.hasSession()
            val cached = amtApi.cachedStats()
            val stale = cached?.let {
                System.currentTimeMillis() / 1_000L - it.fetchedAt > AMT_REFRESH_SECS
            } ?: true
            val stats = if (signedIn && refresh && stale) {
                runCatching { amtApi.refreshStats(LocalDate.now().toString()) }.getOrNull() ?: cached
            } else {
                cached
            }
            AmtHome(
                signedIn = amtApi.hasSession(),
                streakCurrent = stats?.streak?.current ?: 0L,
                streakLongest = stats?.streak?.longest ?: 0L,
                levels = stats?.activity?.associate { it.day to it.level.toInt() } ?: emptyMap(),
                seconds = stats?.activity?.associate { it.day to it.seconds.toInt() } ?: emptyMap(),
                loaded = true,
            )
        }
        _amt.value = next
        runCatching { _heatmap.value = buildHeatmap(lastDayCounts, next) }
    }

    /** SQL aggregates over the whole store (empty query = match-all), off-main. */
    private suspend fun computeAwards(): AwardsStats = withContext(Dispatchers.IO) {
        val today = LocalDate.now(ZoneOffset.UTC).toString()
        val streaks = store.bragStreaks("", today, null, null)
        val was = store.wasSummary("")
        val dxcc = store.dxccWorked("")
        AwardsStats(
            streakCurrent = streaks.onAir.current,
            streakLongest = streaks.onAir.longest,
            wasCount = was.allStates.size,
            dxccCount = dxcc.size,
            loaded = true,
        )
    }

    /**
     * Fold per-day counts into the 53×7 Sunday-first grid the card renders.
     * AMT practice days are keyed by the user's local calendar date; they land
     * on the grid cell carrying the same `yyyy-MM-dd` label.
     */
    private fun buildHeatmap(counts: Map<String, Int>, amt: AmtHome = AmtHome()): HeatmapData {
        val today = LocalDate.now(ZoneOffset.UTC)
        val thisWeekStart = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.SUNDAY))
        val firstWeekStart = thisWeekStart.minusWeeks(52)
        val max = counts.values.maxOrNull() ?: 0
        var total = 0
        var amtDays = 0
        val monthLabels = mutableMapOf<Int, String>()
        val weeks = (0..52).map { week ->
            val weekStart = firstWeekStart.plusWeeks(week.toLong())
            if (weekStart.month != weekStart.minusWeeks(1).month) {
                monthLabels[week] = weekStart.month.getDisplayName(TextStyle.SHORT, Locale.US)
            }
            (0..6).map { day ->
                val date = weekStart.plusDays(day.toLong())
                if (date.isAfter(today)) return@map null
                val key = date.toString()
                val count = counts[key] ?: 0
                total += count
                val amtLevel = (amt.levels[key] ?: 0).coerceIn(0, 4)
                if (amtLevel > 0) amtDays += 1
                HeatCell(count, level(count, max), amtLevel, amt.seconds[key] ?: 0)
            }
        }
        return HeatmapData(weeks, monthLabels, total, amtDays)
    }

    /** 0 for empty days; else the count's quartile of the busiest day, 1–4. */
    private fun level(count: Int, max: Int): Int = when {
        count <= 0 || max <= 0 -> 0
        else -> ((4 * count + max - 1) / max).coerceIn(1, 4)
    }

    private fun computeStats(qsos: List<FfiQso>, homeGrid: String): HomeStats {
        if (qsos.isEmpty()) return HomeStats()
        val todayKey = utcDayKey(System.currentTimeMillis() / 1_000L)
        val todayQsos = qsos.filter { utcDayKey(it.qsoDate) == todayKey }

        val bands = qsos.mapNotNull { it.band }
            .groupingBy { it }.eachCount()
            .entries.sortedByDescending { it.value }
            .map { it.key to it.value }

        val modes = qsos.mapNotNull { it.mode }
            .groupingBy { it }.eachCount()
            .entries.sortedByDescending { it.value }
            .map { it.key to it.value }

        val bestDx = qsos
            .mapNotNull { q ->
                val g = q.theirGrid
                if (g != null && maidenheadIsValid(g) && maidenheadIsValid(homeGrid)) {
                    maidenheadDistanceKm(homeGrid, g)?.let { BestDx(q.callsign, g, it) }
                } else {
                    null
                }
            }
            .maxByOrNull { it.km }

        return HomeStats(
            total = qsos.size,
            today = todayQsos.size,
            uniqueCalls = qsos.map { it.callsign }.toSet().size,
            uniqueGrids = qsos.mapNotNull { it.theirGrid?.take(4)?.uppercase() }.toSet().size,
            bands = bands,
            modes = modes,
            bandsToday = todayQsos.mapNotNull { it.band }.distinct(),
            bestDx = bestDx,
            recent = qsos.take(5),
        )
    }

    companion object {
        /** Don't re-fetch `/v1/me/stats` more often than this on Home opens / resumes. */
        private const val AMT_REFRESH_SECS = 60L

        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                HomeViewModel(app.repository, app.store, app.amtApi, app.amtChanged)
            }
        }
    }
}
