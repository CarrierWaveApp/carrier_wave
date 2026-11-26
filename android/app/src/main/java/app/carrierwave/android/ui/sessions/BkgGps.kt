package app.carrierwave.android.ui.sessions

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import uniffi.cw_ffi.FfiBkgPosition
import uniffi.cw_ffi.FfiLoggingSession
import uniffi.cw_ffi.bkgCheckGrid

private val GridTeal = Color(0xFF14B8A6)
private val GridOrange = Color(0xFFF97316)

/**
 * BKG Turf Wars session lifecycle: loads the stored corner and live-GPS flag
 * for [sessionId], asks for location permission once, and feeds GPS fixes to
 * [LoggerViewModel.onBkgFix] while the logger is on screen. The grid and corner
 * rules are Rust's (`bkgPosition`), the same kernel iOS uses.
 */
@Composable
fun BkgGpsEffect(vm: LoggerViewModel, sessionId: String) {
    val context = LocalContext.current
    var permitted by remember { mutableStateOf(hasLocationPermission(context)) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
        permitted = granted.values.any { it }
    }
    LaunchedEffect(sessionId) {
        vm.loadBkgSession()
        if (!permitted) launcher.launch(GPS_GRID_PERMISSIONS)
    }
    LaunchedEffect(sessionId, permitted) {
        if (!permitted) return@LaunchedEffect
        currentGpsFix(context.applicationContext)?.let { vm.onBkgFix(it.latitude, it.longitude) }
        gpsFixes(context.applicationContext).collect { vm.onBkgFix(it.latitude, it.longitude) }
    }
}

/**
 * The station's grid — or its 4-grid corner — as a chip in the session
 * header. Tapping it offers "Use GPS now" and "Follow GPS (rove)".
 */
@Composable
fun BkgGridPill(
    session: FfiLoggingSession,
    form: BkgFormState,
    onUseGps: () -> Unit,
    onLiveGps: (Boolean) -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    val grid = bkgCheckGrid(session.myGrid.orEmpty()).grid
    val text = when {
        form.cornerGrids.isNotEmpty() -> form.cornerGrids.joinToString(" ")
        grid != null -> grid
        else -> "NO GRID"
    } + if (form.liveGps) " ⌖" else ""
    val tint = if (grid == null) GridOrange else GridTeal
    Box {
        Surface(
            shape = RoundedCornerShape(50),
            color = tint.copy(alpha = 0.16f),
            modifier = Modifier.clickable { menu = true },
        ) {
            Text(
                text,
                Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                fontFamily = FontFamily.Monospace,
                color = tint,
            )
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text("Use GPS now") },
                enabled = form.position != null,
                onClick = {
                    menu = false
                    onUseGps()
                },
            )
            DropdownMenuItem(
                text = { Text("Follow GPS (rove)") },
                trailingIcon = { Checkbox(checked = form.liveGps, onCheckedChange = null) },
                onClick = {
                    menu = false
                    onLiveGps(!form.liveGps)
                },
            )
        }
    }
}

/** One line for the BKG card: the GPS grid and the distance to the nearest corner. */
fun bkgGpsSummary(position: FfiBkgPosition?): String {
    position ?: return "Waiting for GPS…"
    if (position.cornerDistanceM < 0) return "GPS ${position.grid} · no corner here"
    val meters = position.cornerDistanceM
    val distance = if (meters < 1000) "${meters.toInt()} m" else "%.1f km".format(meters / 1000)
    return "GPS ${position.grid} · ${if (position.atCorner) "at corner" else "corner"} $distance"
}
