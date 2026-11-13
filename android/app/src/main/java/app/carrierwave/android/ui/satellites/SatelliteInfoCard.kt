package app.carrierwave.android.ui.satellites

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.core.content.ContextCompat
import app.carrierwave.android.data.FavoriteSatellites
import app.carrierwave.android.data.SatellitePassRecorder
import uniffi.cw_ffi.FfiSatellitePass
import uniffi.cw_ffi.FfiSatTransmitter

/**
 * Compact detail card for the selected satellite: identity + star, live
 * az/el when above the horizon, transmitters (active first), pass-list
 * entry. Mirror of the iOS `SatelliteInfoCard`.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SatelliteInfoCard(
    vm: SatelliteViewModel,
    noradId: UInt,
    onOpenPasses: () -> Unit,
    onQuickLog: () -> Unit,
    onOpenPointing: () -> Unit,
    onDismiss: () -> Unit,
) {
    val summary = vm.summary(noradId) ?: return
    val position = vm.selectedPosition()
    val context = LocalContext.current
    val favorites by FavoriteSatellites.state.collectAsStateWithLifecycle()
    val isFavorite = favorites.contains(noradId)

    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(summary.name, style = MaterialTheme.typography.titleMedium)
                    val detail = summary.detailName
                    if (detail != null) {
                        Text(
                            detail,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Text(
                        "NORAD ${summary.noradId}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                IconButton(onClick = { FavoriteSatellites.toggle(context, noradId) }) {
                    Icon(
                        if (isFavorite) Icons.Filled.Star else Icons.Outlined.StarBorder,
                        contentDescription =
                            if (isFavorite) "Remove from favorites" else "Add to favorites",
                        tint = if (isFavorite) Color(0xFFF9A825) else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Filled.Close, contentDescription = "Deselect satellite")
                }
            }
            if (position?.elevationDeg != null) {
                val azimuth = position.azimuthDeg ?: 0.0
                val elevation = position.elevationDeg ?: 0.0
                val range = position.rangeKm ?: 0.0
                Text(
                    "Az %.0f° · El %.0f° · %.0f km · alt %.0f km"
                        .format(azimuth, elevation, range, position.altKm),
                    style = MaterialTheme.typography.bodySmall,
                )
            } else {
                Text(
                    "Below the horizon · alt %.0f km".format(position?.altKm ?: 0.0),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            NextPassLine(vm, noradId)
            for (transmitter in summary.transmitters.take(3)) {
                TransmitterRow(transmitter)
            }
            val extra = summary.transmitters.size - 3
            if (extra > 0) {
                Text(
                    "+ $extra more transmitters",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onOpenPasses) {
                    Icon(Icons.Filled.CalendarMonth, contentDescription = null)
                    Text(" Passes")
                }
                TextButton(onClick = onQuickLog) {
                    Icon(Icons.Filled.EditNote, contentDescription = null)
                    Text(" Log")
                }
                TextButton(onClick = onOpenPointing) {
                    Icon(Icons.Filled.Explore, contentDescription = null)
                    Text(" Point")
                }
                RecordControls(noradId = noradId, satelliteName = summary.name)
            }
        }
    }
}

/**
 * "Next pass in 25m · peaks 34°" (or the in-progress countdown to LOS)
 * for the selected bird — mirror of the iOS info-card line. Recomputes
 * per position tick; hidden until the 48 h forecast loads.
 */
@Composable
private fun NextPassLine(vm: SatelliteViewModel, noradId: UInt) {
    var nextPass by remember(noradId) { mutableStateOf<FfiSatellitePass?>(null) }
    LaunchedEffect(noradId) {
        nextPass = vm.passForecast(noradId)?.passes?.firstOrNull()
    }
    val pass = nextPass ?: return
    val now = System.currentTimeMillis() / 1_000
    if (pass.losEpoch <= now) return
    val timing = if (now >= pass.aosEpoch) {
        "Up now · sets in ${passCountdown(pass.losEpoch - now)}"
    } else {
        "Next pass in ${passCountdown(pass.aosEpoch - now)}"
    }
    val marginal = pass.peakElevationDeg in 10.0..<20.0
    Text(
        "$timing · peaks %.0f°%s".format(
            pass.peakElevationDeg,
            if (marginal) " · marginal" else "",
        ),
        style = MaterialTheme.typography.bodySmall,
        color = when {
            pass.peakElevationDeg >= 45 -> Color(0xFF4CAF50)
            pass.peakElevationDeg >= 20 -> MaterialTheme.colorScheme.onSurface
            else -> MaterialTheme.colorScheme.onSurfaceVariant
        },
    )
}

private fun passCountdown(seconds: Long): String {
    val minutes = (seconds / 60).coerceAtLeast(0)
    return when {
        minutes < 1 -> "under a minute"
        minutes < 60 -> "${minutes}m"
        else -> "${minutes / 60}h %02dm".format(minutes % 60)
    }
}

/**
 * Record-the-pass controls (mirror of the iOS info-card secondary record
 * control — works without any pointing/sensor surface): start/stop plus a
 * "Mark" tap per worked contact; marks pre-seed the quick-log rows.
 */
@Composable
private fun RecordControls(noradId: UInt, satelliteName: String) {
    val context = LocalContext.current
    val recState by SatellitePassRecorder.state.collectAsStateWithLifecycle()
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) SatellitePassRecorder.start(context, noradId.toInt(), satelliteName)
    }

    if (recState.isRecording) {
        TextButton(onClick = { SatellitePassRecorder.mark() }) {
            Icon(Icons.Filled.Flag, contentDescription = null)
            Text(" Mark (${recState.markCount})")
        }
        TextButton(onClick = { SatellitePassRecorder.stop(context) }) {
            Icon(Icons.Filled.Stop, contentDescription = null, tint = Color(0xFFD32F2F))
            Text(" Stop", color = Color(0xFFD32F2F))
        }
    } else {
        TextButton(onClick = {
            val granted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED
            if (granted) {
                SatellitePassRecorder.start(context, noradId.toInt(), satelliteName)
            } else {
                permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
            }
        }) {
            Icon(Icons.Filled.Mic, contentDescription = null)
            Text(" Record")
        }
    }
}

@Composable
private fun TransmitterRow(transmitter: FfiSatTransmitter) {
    val downlink = transmitter.downlinkLowHz?.let { "↓ %.3f".format(it / 1_000_000.0) }
    val uplink = transmitter.uplinkLowHz?.let { "↑ %.3f".format(it / 1_000_000.0) }
    val parts = listOfNotNull(transmitter.mode, downlink, uplink)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        TransmitterHeardDot(transmitter)
        Text(
            parts.joinToString("  ") +
                if (!transmitter.isActive) "  (inactive)" else "",
            style = MaterialTheme.typography.bodySmall,
            color = if (transmitter.isActive) {
                MaterialTheme.colorScheme.onSurface
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
    }
}

/**
 * Per-capability community signal (iOS `TransmitterHeardDot` mirror):
 * green when AMSAT heard this mode in the last 24 h, dim gray when
 * tracked but not reported today, nothing when untracked.
 */
@Composable
fun TransmitterHeardDot(transmitter: FfiSatTransmitter) {
    if (!transmitter.amsatTracked) return
    val heardToday = transmitter.amsatLastHeardEpoch
        ?.let { System.currentTimeMillis() / 1_000 - it < 24 * 3_600 } ?: false
    Box(
        modifier = Modifier
            .size(6.dp)
            .background(
                if (heardToday) Color(0xFF4CAF50) else MaterialTheme.colorScheme.outlineVariant,
                CircleShape,
            ),
    )
}
