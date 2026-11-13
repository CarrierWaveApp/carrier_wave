package app.carrierwave.android.ui.satellites

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import app.carrierwave.android.CwApp
import app.carrierwave.android.data.SatellitePassRecorder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.CwException
import uniffi.cw_ffi.FfiPassSessionInput
import uniffi.cw_ffi.FfiSatTransmitter
import uniffi.cw_ffi.FfiSessionLogInput
import java.util.Calendar
import java.util.TimeZone

/**
 * Post-LOS satellite quick log (mirror of the iOS `SatelliteQuickLogSheet`):
 * satellite, transmitter, mode, and time are prefilled — the operator only
 * types callsign + grid per contact. Rows are written through the shared
 * Rust `SessionApi.logQso` under a **born-completed** session created by
 * `SatelliteApi.createPassSession`, so an active activation is never paused
 * and every QSO is forced to SAT_NAME + PROP_MODE=SAT (LoTW satellite
 * credit requires the prop mode).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SatelliteQuickLogScreen(
    vm: SatelliteViewModel,
    noradId: UInt,
    onBack: () -> Unit,
    onLogged: (Int) -> Unit,
) {
    val summary = vm.summary(noradId)
    if (summary == null) {
        onBack()
        return
    }
    val context = LocalContext.current
    val app = context.applicationContext as CwApp
    val scope = rememberCoroutineScope()

    // Fresh pass recording (ended < 45 min ago): played back inline, and its
    // tap marks pre-seed one contact row each at the marked time. Stops a
    // still-running recording for this bird first.
    val recording = remember(noradId) {
        SatellitePassRecorder.recentRecording(context, noradId.toInt())
    }

    // Transmitters worth logging against: anything with a downlink.
    val candidates = remember(summary) { summary.transmitters.filter { it.downlinkLowHz != null } }
    var transmitterIndex by remember {
        // Preselect the primary: active with both links, else first candidate.
        mutableIntStateOf(
            candidates.indexOfFirst { it.isActive && it.uplinkLowHz != null && it.downlinkLowHz != null }
                .takeIf { it >= 0 } ?: 0,
        )
    }
    var mode by remember {
        mutableStateOf(candidates.getOrNull(transmitterIndex)?.mode?.let(::normalizedMode) ?: "FM")
    }
    var defaultTime by remember { mutableStateOf(utcHhmmNow()) }
    val rows = remember {
        val seeded = recording?.markEpochsMs.orEmpty().map { epochMs ->
            QuickLogRow(time = utcHhmm(epochMs))
        }
        mutableStateListOf(*(seeded + QuickLogRow()).toTypedArray())
    }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    val filledCount = rows.count { it.callsign.isNotBlank() }

    fun save() {
        val transmitter = candidates.getOrNull(transmitterIndex)
        // ADIF FREQ/BAND are your TX side = the uplink; beacon-only
        // transmitters fall back to the downlink so the QSO gets a band.
        val frequencyMhz = (transmitter?.uplinkLowHz ?: transmitter?.downlinkLowHz)
            ?.let { it / 1_000_000.0 }
        val nowEpoch = System.currentTimeMillis() / 1_000
        val defaultEpoch = parseUtcTime(defaultTime, nowEpoch) ?: nowEpoch
        val contacts = rows.mapNotNull { row ->
            val callsign = row.callsign.trim().uppercase()
            if (callsign.isEmpty()) return@mapNotNull null
            QuickLogContact(
                callsign = callsign,
                grid = row.grid.trim().uppercase().ifEmpty { null },
                epoch = row.time.takeIf { it.isNotBlank() }?.let { parseUtcTime(it, nowEpoch) }
                    ?: defaultEpoch,
            )
        }
        if (contacts.isEmpty()) return
        saving = true
        error = null
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val sessionId = app.satelliteApi.createPassSession(
                        FfiPassSessionInput(
                            myCallsign = app.userCallsign,
                            myGrid = app.userHomeGrid.ifBlank { null },
                            mode = mode,
                            frequencyMhz = frequencyMhz,
                            satName = summary.name,
                            startedAtEpoch = contacts.minOf { it.epoch },
                            endedAtEpoch = contacts.maxOf { it.epoch },
                        ),
                    )
                    var logged = 0
                    for (contact in contacts) {
                        try {
                            // null result = session row missing from cw-store;
                            // don't count the row as logged.
                            val logResult = app.sessionApi.logQso(
                                FfiSessionLogInput(
                                    sessionId = sessionId,
                                    callsign = contact.callsign,
                                    rstSent = "",
                                    rstReceived = "",
                                    theirGrid = contact.grid,
                                    theirPark = null,
                                    notes = null,
                                    name = null,
                                    qth = null,
                                    state = null,
                                    country = null,
                                    theirLicenseClass = null,
                                    aoaCode = null,
                                    callsignChangeNote = null,
                                    frequencyOverrideMhz = null,
                                    modeOverride = null,
                                    timestampOverride = contact.epoch,
                                    satName = summary.name,
                                    propMode = "SAT",
                                    // Android has no upload pipeline wired yet.
                                    uploadQrz = false,
                                    uploadPota = false,
                                    uploadLofi = false,
                                    uploadClublog = false,
                                ),
                            )
                            if (logResult != null) logged += 1
                        } catch (_: CwException) {
                            // Row failed — keep going so the rest of the pass logs.
                        }
                    }
                    logged
                }
            }
            saving = false
            result
                .onSuccess { logged ->
                    if (logged > 0) onLogged(logged) else error = "No contacts could be logged"
                }
                .onFailure { err -> error = err.message ?: "Logging failed" }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("${summary.name} Pass Log") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(onClick = { save() }, enabled = filledCount > 0 && !saving) {
                        Text(if (filledCount > 1) "Log $filledCount" else "Log")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Text(
                    "Logged with SAT_NAME ${summary.name} and PROP_MODE SAT " +
                        "for LoTW satellite credit.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (recording != null) {
                item {
                    Text("Pass recording", style = MaterialTheme.typography.titleSmall)
                }
                item {
                    SatellitePassPlaybackView(recording)
                }
            }
            if (candidates.isNotEmpty()) {
                item {
                    Text("Transmitter", style = MaterialTheme.typography.titleSmall)
                }
                items(count = candidates.size) { index ->
                    TransmitterChoiceRow(
                        transmitter = candidates[index],
                        selected = index == transmitterIndex,
                        onSelect = {
                            transmitterIndex = index
                            candidates[index].mode?.let { mode = normalizedMode(it) }
                        },
                    )
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (option in listOf("FM", "SSB", "CW", "DATA")) {
                        FilterChip(
                            selected = mode == option,
                            onClick = { mode = option },
                            label = { Text(option) },
                        )
                    }
                }
            }
            item {
                OutlinedTextField(
                    value = defaultTime,
                    onValueChange = { defaultTime = it },
                    label = { Text("QSO time (UTC HH:MM)") },
                    singleLine = true,
                    modifier = Modifier.width(200.dp),
                )
            }
            item {
                Text("Contacts", style = MaterialTheme.typography.titleSmall)
            }
            items(count = rows.size) { index ->
                ContactRow(
                    row = rows[index],
                    onChange = { updated ->
                        rows[index] = updated
                        // Auto-append: always keep one empty callsign row.
                        if (rows.none { it.callsign.isBlank() }) rows.add(QuickLogRow())
                    },
                )
            }
            val message = error
            if (message != null) {
                item {
                    Text(
                        message,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        }
    }
}

/** One copied contact being entered: callsign + grid, optional own time. */
private data class QuickLogRow(
    val callsign: String = "",
    val grid: String = "",
    /** Optional per-row UTC HH:MM; blank = the shared default time. */
    val time: String = "",
)

private data class QuickLogContact(
    val callsign: String,
    val grid: String?,
    val epoch: Long,
)

@Composable
private fun TransmitterChoiceRow(
    transmitter: FfiSatTransmitter,
    selected: Boolean,
    onSelect: () -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        RadioButton(selected = selected, onClick = onSelect)
        Text(
            transmitterLabel(transmitter),
            style = MaterialTheme.typography.bodySmall,
            color = if (transmitter.isActive) {
                MaterialTheme.colorScheme.onSurface
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
    }
}

@Composable
private fun ContactRow(row: QuickLogRow, onChange: (QuickLogRow) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            OutlinedTextField(
                value = row.callsign,
                onValueChange = { onChange(row.copy(callsign = it)) },
                label = { Text("Callsign") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.weight(1f),
            )
            OutlinedTextField(
                value = row.grid,
                onValueChange = { onChange(row.copy(grid = it)) },
                label = { Text("Grid") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.width(110.dp),
            )
            OutlinedTextField(
                value = row.time,
                onValueChange = { onChange(row.copy(time = it)) },
                label = { Text("HH:MM") },
                singleLine = true,
                modifier = Modifier.width(96.dp),
            )
        }
    }
}

private fun transmitterLabel(transmitter: FfiSatTransmitter): String {
    val parts = buildList {
        transmitter.mode?.takeIf { it.isNotEmpty() }?.let { add(it) }
        transmitter.downlinkLowHz?.let { add("↓ %.3f".format(it / 1_000_000.0)) }
        transmitter.uplinkLowHz?.let { add("↑ %.3f".format(it / 1_000_000.0)) }
        if (!transmitter.isActive) add("(inactive)")
    }
    return if (parts.isEmpty()) transmitter.description else parts.joinToString("  ")
}

/** Collapse SatNOGS mode strings onto the logger's mode set (iOS parity). */
private fun normalizedMode(raw: String): String {
    val upper = raw.uppercase()
    return when {
        upper.contains("FM") -> "FM"
        upper.contains("CW") -> "CW"
        upper.contains("SSB") || upper.contains("USB") || upper.contains("LSB") ||
            upper.contains("LINEAR") || upper.contains("TRANSPONDER") -> "SSB"
        else -> "DATA"
    }
}

private fun utcHhmmNow(): String = utcHhmm(System.currentTimeMillis())

private fun utcHhmm(epochMs: Long): String {
    val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { timeInMillis = epochMs }
    return "%02d:%02d".format(cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE))
}

/** Parse "HH:MM" (or "HHMM") as a UTC time on today's date; null on junk. */
private fun parseUtcTime(text: String, nowEpoch: Long): Long? {
    val cleaned = text.trim().replace(":", "")
    if (cleaned.length !in 3..4 || cleaned.any { !it.isDigit() }) return null
    val hour = cleaned.dropLast(2).toInt()
    val minute = cleaned.takeLast(2).toInt()
    if (hour > 23 || minute > 59) return null
    val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
        timeInMillis = nowEpoch * 1_000
        set(Calendar.HOUR_OF_DAY, hour)
        set(Calendar.MINUTE, minute)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }
    return cal.timeInMillis / 1_000
}
