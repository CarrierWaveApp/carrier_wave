package app.carrierwave.android.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import app.carrierwave.android.CwApp
import app.carrierwave.android.data.FavoriteSatellites
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.FfiObserver
import uniffi.cw_ffi.FfiPlannedAlert
import uniffi.cw_ffi.maidenheadCoordinate

/**
 * Schedules AOS-lead pass alarms from the shared Rust planner and reconciles
 * them against what's already registered (mirror of the iOS
 * `SatellitePassAlertScheduler`): Rust `plan_alerts` is the single source of
 * truth for identifiers/fire times/copy; this object only diffs the
 * identifier set kept in prefs and (un)registers `AlarmManager` alarms.
 * Exact alarms are best-effort on Android — when the user revokes
 * SCHEDULE_EXACT_ALARM (31+) we degrade to a `setWindow` around the fire
 * time and surface that in the alert settings screen.
 */
object SatelliteAlertScheduler {
    private const val PREFS = "cw"
    private const val KEY_ENABLED = "satellite_alerts_enabled"
    private const val KEY_LEAD_SECS = "satellite_alert_lead_secs"
    private const val KEY_MARGINAL = "satellite_alerts_marginal"
    private const val KEY_SCHEDULED = "satellite_alert_scheduled_ids"

    const val DEFAULT_LEAD_SECS = 900L
    private const val PLAN_HOURS = 24.0
    private const val WINDOW_SLACK_MS = 5L * 60 * 1_000
    private const val WINDOW_LENGTH_MS = 10L * 60 * 1_000

    const val EXTRA_IDENTIFIER = "satellite_alert_identifier"
    const val EXTRA_TITLE = "satellite_alert_title"
    const val EXTRA_BODY = "satellite_alert_body"
    const val EXTRA_NORAD = "satellite_norad"

    // MARK: prefs

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun leadSecs(context: Context): Long =
        prefs(context).getLong(KEY_LEAD_SECS, DEFAULT_LEAD_SECS)

    fun setLeadSecs(context: Context, secs: Long) {
        prefs(context).edit().putLong(KEY_LEAD_SECS, secs).apply()
    }

    fun includeMarginal(context: Context): Boolean =
        prefs(context).getBoolean(KEY_MARGINAL, false)

    fun setIncludeMarginal(context: Context, include: Boolean) {
        prefs(context).edit().putBoolean(KEY_MARGINAL, include).apply()
    }

    fun scheduledCount(context: Context): Int =
        prefs(context).getStringSet(KEY_SCHEDULED, emptySet())!!.size

    /** True when exact alarms will actually be exact (not revoked). */
    fun exactAlarmsAvailable(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val manager = context.getSystemService(AlarmManager::class.java) ?: return false
        return manager.canScheduleExactAlarms()
    }

    // MARK: reconcile

    /**
     * Recompute the plan and reconcile alarms. Safe to call often (app
     * start, favorites change, settings change, 6 h worker, boot): the
     * refresh is cache-through and re-registering an alarm with the same
     * request code replaces it. A plan failure (e.g. cold + offline) keeps
     * the existing alarms — stale alerts beat missing ones.
     */
    suspend fun reschedule(context: Context) {
        val app = context.applicationContext as CwApp
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val previous = prefs(context).getStringSet(KEY_SCHEDULED, emptySet())!!.toSet()

        val observer = observer(app)
        val favorites = FavoriteSatellites.state.value
        if (!isEnabled(context) || observer == null || favorites.isEmpty()) {
            for (identifier in previous) cancelOne(context, alarmManager, identifier)
            prefs(context).edit().putStringSet(KEY_SCHEDULED, emptySet()).apply()
            return
        }

        val now = System.currentTimeMillis() / 1_000
        val alerts = try {
            withContext(Dispatchers.IO) {
                // plan_alerts needs the catalog loaded; refresh is
                // cache-through (fresh cache = no network).
                runCatching { app.satelliteApi.refresh(false) }
                app.satelliteApi.planAlerts(
                    observer,
                    favorites.toList(),
                    includeMarginal(context),
                    leadSecs(context),
                    now,
                    PLAN_HOURS,
                )
            }
        } catch (_: Exception) {
            return
        }

        val upcoming = alerts.filter { it.fireEpoch > now }
        val newIds = upcoming.map { it.identifier }.toSet()
        for (stale in previous - newIds) cancelOne(context, alarmManager, stale)
        for (alert in upcoming) scheduleOne(context, alarmManager, alert)
        prefs(context).edit().putStringSet(KEY_SCHEDULED, newIds).apply()
    }

    // MARK: private

    private fun observer(app: CwApp): FfiObserver? = app.userHomeGrid
        .takeIf { it.isNotBlank() }
        ?.let { grid -> maidenheadCoordinate(grid.take(6)) }
        ?.let { FfiObserver(latDeg = it.latitude, lonDeg = it.longitude) }

    private fun scheduleOne(
        context: Context,
        alarmManager: AlarmManager,
        alert: FfiPlannedAlert,
    ) {
        val pending = pendingIntent(context, alert.identifier) { intent ->
            intent.putExtra(EXTRA_IDENTIFIER, alert.identifier)
            intent.putExtra(EXTRA_TITLE, alert.title)
            intent.putExtra(EXTRA_BODY, alert.body)
            intent.putExtra(EXTRA_NORAD, alert.noradId.toInt())
        }
        val fireMs = alert.fireEpoch * 1_000
        if (exactAlarmsAvailable(context)) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireMs, pending)
        } else {
            alarmManager.setWindow(
                AlarmManager.RTC_WAKEUP,
                fireMs - WINDOW_SLACK_MS,
                WINDOW_LENGTH_MS,
                pending,
            )
        }
    }

    private fun cancelOne(context: Context, alarmManager: AlarmManager, identifier: String) {
        alarmManager.cancel(pendingIntent(context, identifier) {})
    }

    /**
     * Alarm identity = receiver class + request code (identifier hash);
     * extras don't participate in Intent matching, so cancel needs no
     * payload and re-scheduling updates the payload in place.
     */
    private fun pendingIntent(
        context: Context,
        identifier: String,
        configure: (Intent) -> Unit,
    ): PendingIntent {
        val intent = Intent(context, SatelliteAlertReceiver::class.java)
        configure(intent)
        return PendingIntent.getBroadcast(
            context,
            identifier.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
