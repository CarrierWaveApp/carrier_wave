package app.carrierwave.android.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * AlarmManager alarms die on reboot: re-register them by enqueueing one
 * refresh-worker run (which replans against the cached TLEs and calls
 * [SatelliteAlertScheduler.reschedule]). WorkManager gives us a legal
 * context for the async replan — receivers can't block.
 */
class SatelliteBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        WorkManager.getInstance(context)
            .enqueue(OneTimeWorkRequestBuilder<SatelliteRefreshWorker>().build())
    }
}
