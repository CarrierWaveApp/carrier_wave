package app.carrierwave.android.ui.common

import uniffi.cw_ffi.ScpApi

private const val SUGGESTION_LIMIT = 8u
private val WHITESPACE = Regex("\\s+")

/**
 * SCP suggestions for a command bar: only while the operator is typing the
 * first (callsign) token — a single fragment of 3+ chars with no trailing
 * space. Sync in-memory prefix/substring match over MASTER.SCP (the shared
 * Rust [ScpApi]); returns empty until the database has downloaded once.
 */
fun scpSuggestions(text: String, scp: ScpApi): List<String> {
    if (text.isEmpty() || text.last().isWhitespace()) return emptyList()
    val fragment = text.trim()
        .split(WHITESPACE)
        .filter { it.isNotEmpty() }
        .singleOrNull()
        ?.uppercase()
        ?: return emptyList()
    if (fragment.length < 3) return emptyList()
    val db = scp.database() ?: return emptyList()
    return db.partialMatch(fragment, SUGGESTION_LIMIT).filterNot { it == fragment }
}
