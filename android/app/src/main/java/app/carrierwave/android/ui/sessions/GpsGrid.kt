package app.carrierwave.android.ui.sessions

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import uniffi.cw_ffi.FfiCoordinate
import uniffi.cw_ffi.FfiMaidenheadPrecision
import uniffi.cw_ffi.maidenheadGrid
import kotlin.coroutines.resume

/** Location permissions the wizard asks for to fill the grid from GPS. */
val GPS_GRID_PERMISSIONS = arrayOf(
    Manifest.permission.ACCESS_FINE_LOCATION,
    Manifest.permission.ACCESS_COARSE_LOCATION,
)

/** True when either location permission has been granted. */
fun hasLocationPermission(context: Context): Boolean = GPS_GRID_PERMISSIONS.any {
    ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
}

/** A last-known fix older than this is ignored in favour of a fresh one. */
private const val MAX_FIX_AGE_MS = 2 * 60_000L

/** How long to wait for a fresh fix before giving up. */
private const val FIX_TIMEOUT_MS = 20_000L

/**
 * The device's current 6-character Maidenhead grid, or null when there is no
 * permission, no enabled provider, or no fix within [FIX_TIMEOUT_MS]. Uses the
 * platform [LocationManager] (no Play Services dependency): a recent
 * last-known fix if there is one, otherwise a single fresh update. The grid
 * itself comes from the shared Rust `maidenheadGrid`, the same encoder iOS
 * uses.
 */
@SuppressLint("MissingPermission") // guarded by hasLocationPermission
suspend fun currentGpsGrid(context: Context): String? {
    if (!hasLocationPermission(context)) return null
    val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
    val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
        .filter { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) }
    if (providers.isEmpty()) return null

    val nowNanos = SystemClock.elapsedRealtimeNanos()
    val recent = providers
        .mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
        .filter { (nowNanos - it.elapsedRealtimeNanos) / 1_000_000 <= MAX_FIX_AGE_MS }
        .minByOrNull { it.accuracy }
    val fix = recent ?: withTimeoutOrNull(FIX_TIMEOUT_MS) { freshFix(manager, providers) } ?: return null
    return maidenheadGrid(FfiCoordinate(fix.latitude, fix.longitude), FfiMaidenheadPrecision.SIX)
}

/** Wait for the first fix from any of [providers]. */
@SuppressLint("MissingPermission")
private suspend fun freshFix(manager: LocationManager, providers: List<String>): Location? =
    suspendCancellableCoroutine { continuation ->
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                manager.removeUpdates(this)
                if (continuation.isActive) continuation.resume(location)
            }

            // Required on API < 30, where these are abstract.
            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) = Unit
            override fun onProviderEnabled(provider: String) = Unit
            override fun onProviderDisabled(provider: String) = Unit
        }
        providers.forEach { provider ->
            runCatching { manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper()) }
        }
        continuation.invokeOnCancellation { manager.removeUpdates(listener) }
    }
