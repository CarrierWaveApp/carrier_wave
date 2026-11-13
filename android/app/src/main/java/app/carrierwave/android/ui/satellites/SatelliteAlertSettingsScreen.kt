package app.carrierwave.android.ui.satellites

import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.data.FavoriteSatellites
import app.carrierwave.android.notifications.SatelliteAlertScheduler
import kotlinx.coroutines.launch

/**
 * Pass alert settings (mirror of the iOS `SatelliteAlertSettingsSheet`):
 * enable toggle (requests POST_NOTIFICATIONS on 33+), lead-time picker,
 * marginal-pass opt-in, and an exact-alarm status row — Android exact
 * alarms are revocable, so when they're off we say so instead of silently
 * firing up to 10 minutes late.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SatelliteAlertSettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val favorites by FavoriteSatellites.state.collectAsStateWithLifecycle()

    var enabled by remember { mutableStateOf(SatelliteAlertScheduler.isEnabled(context)) }
    var leadSecs by remember { mutableLongStateOf(SatelliteAlertScheduler.leadSecs(context)) }
    var marginal by remember { mutableStateOf(SatelliteAlertScheduler.includeMarginal(context)) }
    var scheduled by remember { mutableIntStateOf(SatelliteAlertScheduler.scheduledCount(context)) }
    val exactAvailable = remember { SatelliteAlertScheduler.exactAlarmsAvailable(context) }

    fun replan() {
        scope.launch {
            SatelliteAlertScheduler.reschedule(context)
            scheduled = SatelliteAlertScheduler.scheduledCount(context)
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        // Alerts stay enabled either way; without the permission the posts
        // are dropped by the OS and the user re-grants from app settings.
        if (granted) replan()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Pass Alerts") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Notify before passes", style = MaterialTheme.typography.bodyLarge)
                    Text(
                        "Favorited satellites only",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(
                    checked = enabled,
                    onCheckedChange = { on ->
                        enabled = on
                        SatelliteAlertScheduler.setEnabled(context, on)
                        if (on && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        }
                        replan()
                    },
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Lead time", style = MaterialTheme.typography.titleSmall)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (minutes in listOf(5L, 10L, 15L, 30L)) {
                        FilterChip(
                            selected = leadSecs == minutes * 60,
                            onClick = {
                                leadSecs = minutes * 60
                                SatelliteAlertScheduler.setLeadSecs(context, minutes * 60)
                                replan()
                            },
                            label = { Text("$minutes min") },
                        )
                    }
                }
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Include marginal passes", style = MaterialTheme.typography.bodyLarge)
                    Text(
                        "Peaks between 10° and 20° elevation",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(
                    checked = marginal,
                    onCheckedChange = { on ->
                        marginal = on
                        SatelliteAlertScheduler.setIncludeMarginal(context, on)
                        replan()
                    },
                )
            }

            if (!exactAvailable) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        "Exact alarms are off — alerts may arrive up to " +
                            "10 minutes late.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        TextButton(onClick = {
                            context.startActivity(
                                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM),
                            )
                        }) {
                            Text("Allow exact alarms")
                        }
                    }
                }
            }

            val status = when {
                !enabled -> "Alerts off"
                favorites.isEmpty() -> "No favorites — star satellites to get alerts"
                else -> "$scheduled alert${if (scheduled == 1) "" else "s"} scheduled " +
                    "for ${favorites.size} favorite${if (favorites.size == 1) "" else "s"}"
            }
            Text(
                status,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
