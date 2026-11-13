package app.carrierwave.android.notifications

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.carrierwave.android.CwApp
import java.util.concurrent.TimeUnit

/**
 * Periodic (6 h — the satellite cache TTL) TLE refresh + alert replan, so
 * alarms stay accurate as orbits drift and new passes enter the 24 h
 * window. Also enqueued one-shot from [SatelliteBootReceiver].
 */
class SatelliteRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val app = applicationContext as CwApp
        // Refresh failure is fine — reschedule() degrades to the cached
        // TLEs (and keeps existing alarms when even those are missing).
        runCatching { app.satelliteApi.refresh(false) }
        SatelliteAlertScheduler.reschedule(applicationContext)
        return Result.success()
    }

    companion object {
        private const val UNIQUE_NAME = "satellite-refresh"

        fun schedulePeriodic(context: Context) {
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<SatelliteRefreshWorker>(6, TimeUnit.HOURS).build(),
            )
        }
    }
}
