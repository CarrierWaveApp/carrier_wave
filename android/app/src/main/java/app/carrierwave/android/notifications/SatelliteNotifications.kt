package app.carrierwave.android.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationManagerCompat

/** Channel + permission helpers for satellite pass alert notifications. */
object SatelliteNotifications {
    const val CHANNEL_ID = "satellite_passes"

    /** Idempotent channel registration (no-op below API 26). */
    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Satellite passes",
            // High: a pass alert is time-critical — the bird is up in minutes.
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Upcoming passes of favorited satellites"
        }
        manager.createNotificationChannel(channel)
    }

    /** True when notifications can actually be posted (permission + channel). */
    fun canPost(context: Context): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled()
}
