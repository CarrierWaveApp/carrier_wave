package app.carrierwave.android.ui.sessions

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.carrierwave.android.BuildConfig
import uniffi.cw_ffi.FfiBkgExport
import uniffi.cw_ffi.FfiLoggingSession
import uniffi.cw_ffi.bkgCheckGrid
import uniffi.cw_ffi.bkgRules

/**
 * BKG log type controls, shown above the command bar in a BKG session: the two
 * "sent in CW" switches, the linear V/U satellite toggle, the 4-grid corner
 * toggle, and the check-and-export action. Grids are typed in the command bar
 * like any other contact ("K6ABC CM97AB"). Every rule and field mapping comes
 * from the shared Rust core (`bkgRules`, `bkgBuildQso`, `BkgApi`) — the same
 * kernel iOS uses.
 */
@Composable
fun BkgCard(
    session: FfiLoggingSession,
    form: BkgFormState,
    theirGrid: String?,
    onSent: (Boolean) -> Unit,
    onReceived: (Boolean) -> Unit,
    onSatellite: (Boolean) -> Unit,
    onSatName: (String) -> Unit,
    onCorner: (Boolean) -> Unit,
    onLoadCorner: () -> Unit,
    onCheck: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val rules = bkgRules()
    val myGrid = bkgCheckGrid(session.myGrid.orEmpty())
    val theirCheck = theirGrid?.takeIf { it.isNotBlank() }?.let { bkgCheckGrid(it) }
    val context = LocalContext.current
    LaunchedEffect(session.id) { onLoadCorner() }

    Card(modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("BKG", fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(end = 8.dp))
                Text(
                    "${rules.mode} · ${rules.band}" +
                        if (form.viaSatellite) " ↑ ${rules.satBandRx} ↓" else "",
                    style = MaterialTheme.typography.labelMedium,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                OutlinedButton(onClick = { onCheck(BuildConfig.VERSION_NAME) }) { Text("Check & Export") }
            }

            GridLine("My grid", myGrid.grid ?: session.myGrid.orEmpty().ifBlank { "not set" }, myGrid.problem)
            GridLine("Their grid", theirCheck?.grid ?: theirGrid.orEmpty().ifBlank { "type it with the callsign" }, theirCheck?.problem)

            SwitchLine("I sent my grid in CW", form.sentMyGrid, onSent)
            SwitchLine("They sent theirs", form.receivedTheirGrid, onReceived)
            SwitchLine("Linear V/U satellite", form.viaSatellite, onSatellite)
            if (form.viaSatellite) {
                OutlinedTextField(
                    value = form.satName,
                    onValueChange = onSatName,
                    label = { Text("Satellite") },
                    placeholder = { Text("RS-44") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            SwitchLine("At a 4-grid corner", form.cornerGrids.isNotEmpty(), onCorner, enabled = myGrid.grid != null)
            if (form.cornerGrids.isNotEmpty()) {
                Text(
                    form.cornerGrids.joinToString(" · "),
                    style = MaterialTheme.typography.labelMedium,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            form.export?.let { export ->
                ExportSummary(export) {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_SUBJECT, "${session.myCallsign} BKG log")
                        putExtra(Intent.EXTRA_TEXT, export.adif)
                    }
                    context.startActivity(Intent.createChooser(send, "Share BKG ADIF"))
                }
            }
        }
    }
}

@Composable
private fun GridLine(label: String, value: String, problem: String?) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            fontFamily = FontFamily.Monospace,
            color = if (problem == null) {
                MaterialTheme.colorScheme.onSurfaceVariant
            } else {
                MaterialTheme.colorScheme.error
            },
        )
    }
    if (problem != null) {
        Text(problem, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.error)
    }
}

@Composable
private fun SwitchLine(label: String, checked: Boolean, onChange: (Boolean) -> Unit, enabled: Boolean = true) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Switch(checked = checked, onCheckedChange = onChange, enabled = enabled)
    }
}

/** Result of the Rust pre-upload check: counts, the flagged contacts with their
 * reasons, and the share action. Upload to the BKG server is not built yet. */
@Composable
private fun ExportSummary(export: FfiBkgExport, onShare: () -> Unit) {
    val ready = export.qsoCount.toInt() - export.flagged.size
    Text(
        "$ready of ${export.qsoCount} contacts ready",
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
    )
    export.flagged.forEach { check ->
        Text(
            "${check.callsign}: ${check.issues.joinToString("; ")}",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.error,
        )
    }
    if (export.qsoCount > 0u) {
        OutlinedButton(onClick = onShare) { Text("Share ADIF") }
    }
}
