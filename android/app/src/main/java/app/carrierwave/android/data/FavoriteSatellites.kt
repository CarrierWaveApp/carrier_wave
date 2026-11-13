package app.carrierwave.android.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The operator's favorited satellites (NORAD IDs), SharedPreferences-backed
 * with a reactive [StateFlow] — the [LoggerKeyboardConfig] pattern, mirror
 * of the iOS `FavoriteSatellitesStore`. Favorites drive pass alerts and
 * sort first in the satellite lists; the shared Rust `SatelliteApi` takes
 * them as parameters (favorites are deliberately host-side).
 */
object FavoriteSatellites {
    private const val PREFS = "cw"
    private const val KEY_IDS = "satellite_favorite_norad_ids"

    private val _state = MutableStateFlow<Set<UInt>>(emptySet())
    val state: StateFlow<Set<UInt>> = _state.asStateFlow()

    /** Called after every change — wired to the alert replan in CwApp. */
    var onChange: (() -> Unit)? = null

    fun load(context: Context) {
        val raw = prefs(context).getString(KEY_IDS, null) ?: return
        _state.value = raw.split(",")
            .mapNotNull { it.trim().toUIntOrNull() }
            .toSet()
    }

    fun isFavorite(noradId: UInt): Boolean = _state.value.contains(noradId)

    fun toggle(context: Context, noradId: UInt) {
        val next = _state.value.toMutableSet()
        if (!next.add(noradId)) next.remove(noradId)
        _state.value = next
        prefs(context).edit()
            .putString(KEY_IDS, next.sorted().joinToString(","))
            .apply()
        onChange?.invoke()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
