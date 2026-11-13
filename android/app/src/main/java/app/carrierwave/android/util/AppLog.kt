package app.carrierwave.android.util

import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * In-app diagnostics sink — Android's analog to iOS's `RadioService.shared.addLog`.
 * Since users can't attach a debugger, diagnostics need to be visible and
 * shareable from inside the app itself. A tiny in-memory ring buffer, capped
 * at [MAX_ENTRIES], exposed as a [StateFlow] so Compose can observe it
 * directly. Every entry is also forwarded to `android.util.Log` so logcat
 * still works during development; nothing is lost by calling this instead.
 *
 * Thread-safe: [add] may be called from IO coroutines as well as Main.
 */
object AppLog {
    enum class Level { INFO, ERROR }

    data class Entry(val timestampMs: Long, val level: Level, val message: String)

    private const val MAX_ENTRIES = 500
    private const val TAG = "CarrierWave"

    private val _entries = MutableStateFlow<List<Entry>>(emptyList())
    val entries: StateFlow<List<Entry>> = _entries.asStateFlow()

    @Synchronized
    fun add(level: Level, message: String) {
        val entry = Entry(System.currentTimeMillis(), level, message)
        _entries.update { current ->
            val updated = current + entry
            if (updated.size > MAX_ENTRIES) updated.subList(updated.size - MAX_ENTRIES, updated.size) else updated
        }
        when (level) {
            Level.INFO -> Log.i(TAG, message)
            Level.ERROR -> Log.w(TAG, message)
        }
    }

    @Synchronized
    fun clear() {
        _entries.value = emptyList()
    }
}
