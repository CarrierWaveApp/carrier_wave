package app.carrierwave.android.notifications

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import app.carrierwave.android.MainActivity
import app.carrierwave.android.R

/**
 * Fires at AOS − lead: posts the pass notification planned by the shared
 * Rust `alert_planner` (title/body arrive verbatim in the alarm extras).
 * Tapping deep-links into the satellites overlay with the bird selected.
 */
class SatelliteAlertReceiver : BroadcastReceiver() {
    // POST_NOTIFICATIONS is checked via areNotificationsEnabled (canPost).
    @SuppressLint("MissingPermission")
    override fun onReceive(context: Context, intent: Intent) {
        val identifier =
            intent.getStringExtra(SatelliteAlertScheduler.EXTRA_IDENTIFIER) ?: return
        val title = intent.getStringExtra(SatelliteAlertScheduler.EXTRA_TITLE) ?: return
        val body = intent.getStringExtra(SatelliteAlertScheduler.EXTRA_BODY) ?: ""
        val norad = intent.getIntExtra(SatelliteAlertScheduler.EXTRA_NORAD, 0)

        SatelliteNotifications.ensureChannel(context)
        if (!SatelliteNotifications.canPost(context)) return

        val tap = Intent(context, MainActivity::class.java).apply {
            putExtra(SatelliteAlertScheduler.EXTRA_NORAD, norad)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            norad,
            tap,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, SatelliteNotifications.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_satellite_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .build()
        NotificationManagerCompat.from(context).notify(identifier.hashCode(), notification)
    }
}
