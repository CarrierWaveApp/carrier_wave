package app.carrierwave.android.ui.brag

import uniffi.cw_ffi.FfiBragPeriod
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Host-side display metadata for [FfiBragPeriod] on the share card. Port of
 * the iOS `BragSheetPeriodDisplay.swift` `headlineText`/`periodLabel` (Monday-
 * 00:00Z week start, month first-day start, UTC calendar) — display-only; all
 * stat values still come from the shared Rust `computeBrag`.
 */
fun FfiBragPeriod.shareHeadline(): String = when (this) {
    FfiBragPeriod.WEEKLY -> "Last 7 Days in Radio"
    FfiBragPeriod.MONTHLY -> "My Month in Radio"
    FfiBragPeriod.ALL_TIME -> "All-Time Stats"
}

/** Formatted period label (e.g. "Feb 17-23, 2026" or "February 2026"), UTC. */
fun FfiBragPeriod.shareSubtitle(now: ZonedDateTime = ZonedDateTime.now(ZoneOffset.UTC)): String {
    val utcNow = now.withZoneSameInstant(ZoneOffset.UTC)
    return when (this) {
        FfiBragPeriod.WEEKLY -> {
            val monday = utcNow.toLocalDate().let { date ->
                val daysFromMonday = (date.dayOfWeek.value - DayOfWeek.MONDAY.value + 7) % 7
                date.minusDays(daysFromMonday.toLong())
            }
            val sunday = monday.plusDays(6)
            val startFmt = DateTimeFormatter.ofPattern("MMM d", Locale.US)
            val endFmt = DateTimeFormatter.ofPattern("d, yyyy", Locale.US)
            "${monday.format(startFmt)}-${sunday.format(endFmt)}"
        }
        FfiBragPeriod.MONTHLY -> {
            val fmt = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.US)
            utcNow.format(fmt)
        }
        FfiBragPeriod.ALL_TIME -> "All Time"
    }
}

/**
 * Unix-seconds lower bound for filtering QSOs into this period's share-card
 * snapshot; null for all-time (no lower bound).
 */
fun FfiBragPeriod.sinceEpochSeconds(now: Instant = Instant.now()): Long? {
    val utcNow = ZonedDateTime.ofInstant(now, ZoneOffset.UTC)
    return when (this) {
        FfiBragPeriod.WEEKLY -> {
            val date = utcNow.toLocalDate()
            val daysFromMonday = (date.dayOfWeek.value - DayOfWeek.MONDAY.value + 7) % 7
            date.minusDays(daysFromMonday.toLong()).atStartOfDay(ZoneOffset.UTC).toEpochSecond()
        }
        FfiBragPeriod.MONTHLY ->
            utcNow.toLocalDate().withDayOfMonth(1).atStartOfDay(ZoneOffset.UTC).toEpochSecond()
        FfiBragPeriod.ALL_TIME -> null
    }
}
