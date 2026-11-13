package app.carrierwave.android.data

import android.content.Context

/**
 * Persists the operator profile (callsign + home grid), replacing the old
 * compile-time `CwApp.MY_CALLSIGN` / `CwApp.HOME_GRID` constants. Editable from
 * the Account screen; mirrors the iOS Profile settings.
 *
 * Values default to empty. On first launch after this change, [CwApp] seeds the
 * profile from the most recent QSO's `myCallsign`/`myGrid` so existing logbooks
 * keep working without re-entry.
 *
 * INVARIANT (CAR-287): this is the ONLY persistent store for the operator
 * callsign, and [CwApp.updateProfile] is the only write path (explicit Save,
 * never per-keystroke). iOS accumulated three competing callsign stores with a
 * launch-time overwrite loop that resurrected stale values; do not add derived
 * caches, extra preference keys, or sync channels for the callsign here —
 * consumers read [callsign] (or the [CwApp.userCallsign] in-memory mirror).
 */
object UserProfile {
    private const val PREFS = "cw"
    private const val KEY_CALLSIGN = "user_callsign"
    private const val KEY_HOME_GRID = "user_home_grid"

    fun callsign(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_CALLSIGN, null).orEmpty()

    fun homeGrid(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_HOME_GRID, null).orEmpty()

    /** True once either field has ever been written (even to blank). */
    fun isSet(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).contains(KEY_CALLSIGN)

    fun save(context: Context, callsign: String, homeGrid: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_CALLSIGN, normalizeCallsign(callsign))
            .putString(KEY_HOME_GRID, normalizeGrid(homeGrid))
            .apply()
    }

    fun normalizeCallsign(callsign: String): String = callsign.trim().uppercase()

    /** Maidenhead convention: field/number upper, subsquare lower ("CM87xj"). */
    fun normalizeGrid(grid: String): String {
        val trimmed = grid.trim()
        return trimmed.mapIndexed { i, c ->
            if (i < 4) c.uppercaseChar() else c.lowercaseChar()
        }.joinToString("")
    }
}
