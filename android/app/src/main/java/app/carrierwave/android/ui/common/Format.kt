package app.carrierwave.android.ui.common

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

private fun utc(pattern: String) = SimpleDateFormat(pattern, Locale.US).apply {
    timeZone = TimeZone.getTimeZone("UTC")
}

private val TS_FULL = utc("MMM d HH:mm'Z'")
private val TS_TIME = utc("HH:mm'Z'")
private val TS_DAY = utc("EEE, MMM d yyyy")
private val TS_DAY_KEY = utc("yyyy-MM-dd")

// All timestamp formatters take **Unix seconds** — the cw-store contract for
// qso_date/imported_at/modified_at that iOS and the shared Rust APIs use.

/** "Jun 26 14:35Z" — list rows. */
fun formatTimestamp(epochSeconds: Long): String = TS_FULL.format(Date(epochSeconds * 1_000L))

/** "14:35Z" — session-relative time. */
fun formatTime(epochSeconds: Long): String = TS_TIME.format(Date(epochSeconds * 1_000L))

/** "Thu, Jun 26 2026" — date section headers. */
fun formatDay(epochSeconds: Long): String = TS_DAY.format(Date(epochSeconds * 1_000L))

/** "2026-06-26" — stable grouping key for a UTC day. */
fun utcDayKey(epochSeconds: Long): String = TS_DAY_KEY.format(Date(epochSeconds * 1_000L))

/** kHz → "14.074 MHz". */
fun formatFreq(freqKhz: Double?): String? =
    freqKhz?.let { "%.3f MHz".format(it / 1000.0) }

/** Compact human duration: "1h 23m", "12m", "—". */
fun formatDuration(millis: Long): String {
    if (millis <= 0) return "—"
    val totalMin = millis / 60_000
    val h = totalMin / 60
    val m = totalMin % 60
    return when {
        h > 0 -> "${h}h ${m}m"
        else -> "${m}m"
    }
}

/** Eight-point compass arrow for a bearing in degrees. */
fun bearingArrow(bearing: Double): String = when (((bearing + 22.5).mod(360.0)).toInt() / 45) {
    0 -> "↑"
    1 -> "↗"
    2 -> "→"
    3 -> "↘"
    4 -> "↓"
    5 -> "↙"
    6 -> "←"
    7 -> "↖"
    else -> "·"
}

/** UniFFI maps the Rust error's `reason` field into `message`. Strip the prefix. */
fun Throwable.cwMessage(): String = (message ?: "error").substringAfter("=")
