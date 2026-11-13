package app.carrierwave.android.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.SessionApi

/**
 * Position-local prefix hot-key suggestions (CAR-290), computed by shared
 * Rust (`SessionApi.suggestedPrefixes`). Android has no live location
 * integration, so `currentGrid` is passed as null and Rust anchors on the
 * most recently logged operating position — the closest thing to "where
 * the operator is right now" that the logbook knows.
 */
object PrefixSuggestions {
    private val _suggested = MutableStateFlow<List<String>>(emptyList())
    val suggested: StateFlow<List<String>> = _suggested.asStateFlow()

    suspend fun refresh(sessionApi: SessionApi) {
        val list = withContext(Dispatchers.IO) {
            runCatching { sessionApi.suggestedPrefixes(currentGrid = null, limit = 0u) }
                .getOrDefault(emptyList())
        }
        _suggested.value = list
    }
}
