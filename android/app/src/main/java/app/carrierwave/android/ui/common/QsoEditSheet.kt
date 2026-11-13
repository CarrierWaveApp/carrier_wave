package app.carrierwave.android.ui.common

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.bandDerive
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

private val EditTimeFmt: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")

/**
 * Shared editor for a logged QSO — the Android analog of iOS `QSOEditSheet`,
 * used by the Hunter log, the live session Logger, the Session detail, and the
 * Logbook. Collapsible sections mirror the iOS sheet: Contact, My Station,
 * Their Location, Activity References, Contest, Notes.
 *
 * [onSave] receives the edited record; the caller stamps `modifiedAt`/`dirty`
 * and persists via the shared store. [onDelete] receives the record for a
 * sync-safe soft delete (`isHidden = true` + `dirty = true` upsert — never
 * `FieldStore.deleteQso`, which is a local-only hard delete the sync journal
 * won't propagate).
 *
 * [mapContent], when provided, renders below the Notes section — used by the
 * Logbook to embed the QSO detail map card + callsign map section (map port
 * phase B). Other hosts leave it null and get no map UI.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QsoEditSheet(
    qso: FfiQso,
    onSave: (FfiQso) -> Unit,
    onDelete: (FfiQso) -> Unit,
    onDismiss: () -> Unit,
    mapContent: (@Composable (FfiQso) -> Unit)? = null,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        QsoEditForm(qso, onSave, onDelete, onDismiss, mapContent)
    }
}

@Composable
private fun QsoEditForm(
    qso: FfiQso,
    onSave: (FfiQso) -> Unit,
    onDelete: (FfiQso) -> Unit,
    onDismiss: () -> Unit,
    mapContent: (@Composable (FfiQso) -> Unit)? = null,
) {
    // Keyed on the QSO id so re-opening a different row re-seeds the fields.
    var callsign by rememberSaveable(qso.id) { mutableStateOf(qso.callsign) }
    var band by rememberSaveable(qso.id) { mutableStateOf(qso.band ?: "") }
    var mode by rememberSaveable(qso.id) { mutableStateOf(qso.mode ?: "") }
    var freq by rememberSaveable(qso.id) {
        mutableStateOf(qso.freqKhz?.let { "%.3f".format(it / 1000.0) } ?: "")
    }
    var time by rememberSaveable(qso.id) {
        mutableStateOf(EditTimeFmt.format(LocalDateTime.ofInstant(Instant.ofEpochSecond(qso.qsoDate), ZoneOffset.UTC)))
    }
    var name by rememberSaveable(qso.id) { mutableStateOf(qso.name ?: "") }
    var rstSent by rememberSaveable(qso.id) { mutableStateOf(qso.rstSent ?: "") }
    var rstRcvd by rememberSaveable(qso.id) { mutableStateOf(qso.rstRcvd ?: "") }

    // My Station
    var myCallsign by rememberSaveable(qso.id) { mutableStateOf(qso.myCallsign ?: "") }
    var stationCallsign by rememberSaveable(qso.id) { mutableStateOf(qso.stationCallsign ?: "") }
    var myRig by rememberSaveable(qso.id) { mutableStateOf(qso.myRig ?: "") }
    var myGrid by rememberSaveable(qso.id) { mutableStateOf(qso.myGrid ?: "") }
    var power by rememberSaveable(qso.id) { mutableStateOf(qso.power?.toString() ?: "") }

    // Their Location
    var theirGrid by rememberSaveable(qso.id) { mutableStateOf(qso.theirGrid ?: "") }
    var qth by rememberSaveable(qso.id) { mutableStateOf(qso.qth ?: "") }
    var state by rememberSaveable(qso.id) { mutableStateOf(qso.state ?: "") }
    var country by rememberSaveable(qso.id) { mutableStateOf(qso.country ?: "") }

    // Activity references
    var myPark by rememberSaveable(qso.id) { mutableStateOf(qso.park ?: "") }
    var theirPark by rememberSaveable(qso.id) { mutableStateOf(qso.theirPark ?: "") }
    var sotaRef by rememberSaveable(qso.id) { mutableStateOf(qso.sotaRef ?: "") }
    var wwffRef by rememberSaveable(qso.id) { mutableStateOf(qso.wwffRef ?: "") }
    var aoaCode by rememberSaveable(qso.id) { mutableStateOf(qso.aoaCode ?: "") }

    // Contest
    var serialSent by rememberSaveable(qso.id) { mutableStateOf(qso.contestSerialSent?.toString() ?: "") }
    var serialRcvd by rememberSaveable(qso.id) { mutableStateOf(qso.contestSerialReceived?.toString() ?: "") }
    var exchSent by rememberSaveable(qso.id) { mutableStateOf(qso.contestExchangeSent ?: "") }
    var exchRcvd by rememberSaveable(qso.id) { mutableStateOf(qso.contestExchangeReceived ?: "") }

    var notes by rememberSaveable(qso.id) { mutableStateOf(qso.notes ?: "") }

    var confirmDelete by remember { mutableStateOf(false) }

    fun parsedTime(): Long? = runCatching {
        LocalDateTime.parse(time.trim(), EditTimeFmt).toEpochSecond(ZoneOffset.UTC)
    }.getOrNull()

    val freqKhz = freq.trim().toDoubleOrNull()?.let { it * 1000.0 }
    // Band falls back to derivation from the typed frequency, like iOS.
    val resolvedBand = band.trim().ifBlank { freqKhz?.let { runCatching { bandDerive(it) }.getOrNull() } ?: "" }
    val isValid = callsign.isNotBlank() &&
        resolvedBand.isNotBlank() &&
        mode.isNotBlank() &&
        parsedTime() != null &&
        // iOS requires a my-callsign; only enforce when the row had one, so
        // legacy imports without it stay editable.
        (qso.myCallsign.isNullOrBlank() || myCallsign.isNotBlank())

    fun edited(): FfiQso {
        val newCallsign = callsign.trim().uppercase()
        return qso.copy(
            callsign = newCallsign,
            // First manual callsign change preserves the original for
            // download-merge matching (CAR-245), mirroring iOS.
            originalCallsign = if (newCallsign != qso.callsign && qso.originalCallsign == null) {
                qso.callsign
            } else {
                qso.originalCallsign
            },
            band = resolvedBand.ifBlank { null },
            mode = mode.trim().uppercase().ifBlank { null },
            freqKhz = freqKhz,
            qsoDate = parsedTime() ?: qso.qsoDate,
            name = name.trim().ifBlank { null },
            rstSent = rstSent.trim().ifBlank { null },
            rstRcvd = rstRcvd.trim().ifBlank { null },
            myCallsign = myCallsign.trim().uppercase().ifBlank { null },
            stationCallsign = stationCallsign.trim().uppercase().ifBlank { null },
            myRig = myRig.trim().ifBlank { null },
            myGrid = myGrid.trim().ifBlank { null },
            power = power.trim().toLongOrNull(),
            theirGrid = theirGrid.trim().uppercase().ifBlank { null },
            qth = qth.trim().ifBlank { null },
            state = state.trim().uppercase().ifBlank { null },
            country = country.trim().ifBlank { null },
            park = myPark.trim().uppercase().ifBlank { null },
            theirPark = theirPark.trim().uppercase().ifBlank { null },
            sotaRef = sotaRef.trim().uppercase().ifBlank { null },
            wwffRef = wwffRef.trim().uppercase().ifBlank { null },
            aoaCode = aoaCode.trim().uppercase().ifBlank { null },
            contestSerialSent = serialSent.trim().toLongOrNull(),
            contestSerialReceived = serialRcvd.trim().toLongOrNull(),
            contestExchangeSent = exchSent.trim().uppercase().ifBlank { null },
            contestExchangeReceived = exchRcvd.trim().uppercase().ifBlank { null },
            notes = notes.trim().ifBlank { null },
            // Manual notes edits are user-authored (CAR-243) — exporters push COMMENT.
            notesUserAuthored = notes.isNotBlank() || qso.notesUserAuthored,
        )
    }

    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .imePadding()
            .padding(horizontal = 20.dp)
            .padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = onDismiss) { Text("Cancel") }
            Text("Edit QSO", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            TextButton(onClick = { onSave(edited()) }, enabled = isValid) { Text("Save") }
        }

        EditSectionLabel("Contact")
        EditField("Callsign", callsign, cap = KeyboardCapitalization.Characters, mono = true) { callsign = it }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            EditField("Band", band, Modifier.weight(1f), cap = KeyboardCapitalization.None, mono = true) { band = it }
            EditField("Mode", mode, Modifier.weight(1f), cap = KeyboardCapitalization.Characters, mono = true) { mode = it }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            EditField("Frequency (MHz)", freq, Modifier.weight(1f), keyboard = KeyboardType.Decimal, mono = true) { freq = it }
            EditField("Time (UTC)", time, Modifier.weight(1f), cap = KeyboardCapitalization.None, mono = true) { time = it }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            EditField("RST Sent", rstSent, Modifier.weight(1f), keyboard = KeyboardType.Number, mono = true) { rstSent = it }
            EditField("RST Rcvd", rstRcvd, Modifier.weight(1f), keyboard = KeyboardType.Number, mono = true) { rstRcvd = it }
        }
        EditField("Name", name) { name = it }

        CollapsibleSection("My Station", initiallyExpanded = false) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                EditField("My Callsign", myCallsign, Modifier.weight(1f), cap = KeyboardCapitalization.Characters, mono = true) {
                    myCallsign = it
                }
                EditField("Station Call", stationCallsign, Modifier.weight(1f), cap = KeyboardCapitalization.Characters, mono = true) {
                    stationCallsign = it
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                EditField("My Grid", myGrid, Modifier.weight(1f), cap = KeyboardCapitalization.Characters, mono = true) {
                    myGrid = it
                }
                EditField("Power (W)", power, Modifier.weight(1f), keyboard = KeyboardType.Number, mono = true) { power = it }
            }
            EditField("My Rig", myRig) { myRig = it }
        }

        CollapsibleSection("Their Location", initiallyExpanded = false) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                EditField("Grid", theirGrid, Modifier.weight(1f), cap = KeyboardCapitalization.Characters, mono = true) {
                    theirGrid = it
                }
                EditField("State", state, Modifier.weight(1f), cap = KeyboardCapitalization.Characters, mono = true) {
                    state = it
                }
            }
            EditField("QTH", qth) { qth = it }
            EditField("Country", country) { country = it }
        }

        CollapsibleSection(
            "Activity References",
            initiallyExpanded = listOf(myPark, theirPark, sotaRef, wwffRef, aoaCode).any { it.isNotBlank() },
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                EditField("My Park", myPark, Modifier.weight(1f), cap = KeyboardCapitalization.Characters, mono = true) {
                    myPark = it
                }
                EditField("Their Park", theirPark, Modifier.weight(1f), cap = KeyboardCapitalization.Characters, mono = true) {
                    theirPark = it
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                EditField("SOTA Ref", sotaRef, Modifier.weight(1f), cap = KeyboardCapitalization.Characters, mono = true) {
                    sotaRef = it
                }
                EditField("WWFF Ref", wwffRef, Modifier.weight(1f), cap = KeyboardCapitalization.Characters, mono = true) {
                    wwffRef = it
                }
            }
            EditField("AoA Code", aoaCode, cap = KeyboardCapitalization.Characters, mono = true) { aoaCode = it }
        }

        if (qso.contestName != null || listOf(serialSent, serialRcvd, exchSent, exchRcvd).any { it.isNotBlank() }) {
            CollapsibleSection("Contest", initiallyExpanded = true) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    EditField("Serial Sent", serialSent, Modifier.weight(1f), keyboard = KeyboardType.Number, mono = true) {
                        serialSent = it
                    }
                    EditField("Serial Rcvd", serialRcvd, Modifier.weight(1f), keyboard = KeyboardType.Number, mono = true) {
                        serialRcvd = it
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    EditField("Exch Sent", exchSent, Modifier.weight(1f), cap = KeyboardCapitalization.Characters, mono = true) {
                        exchSent = it
                    }
                    EditField("Exch Rcvd", exchRcvd, Modifier.weight(1f), cap = KeyboardCapitalization.Characters, mono = true) {
                        exchRcvd = it
                    }
                }
            }
        }

        EditSectionLabel("Notes")
        EditField("Notes", notes, singleLine = false) { notes = it }

        mapContent?.let { content ->
            Spacer(Modifier.height(4.dp))
            content(qso)
        }

        Spacer(Modifier.height(4.dp))
        TextButton(
            onClick = { confirmDelete = true },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            Spacer(Modifier.width(6.dp))
            Text("Delete QSO", color = MaterialTheme.colorScheme.error)
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete QSO") },
            text = { Text("Delete QSO with ${qso.callsign}?") },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    onDelete(qso)
                }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("Cancel") }
            },
        )
    }
}

/** Section header with a chevron disclosure — the iOS collapsible-section analog. */
@Composable
private fun CollapsibleSection(
    title: String,
    initiallyExpanded: Boolean,
    content: @Composable () -> Unit,
) {
    var expanded by rememberSaveable(title) { mutableStateOf(initiallyExpanded) }
    Row(
        Modifier.fillMaxWidth().clickable { expanded = !expanded }.padding(top = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            title,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary,
        )
        Icon(
            if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
    }
    AnimatedVisibility(visible = expanded) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { content() }
    }
}

@Composable
private fun EditSectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 6.dp),
    )
}

@Composable
private fun EditField(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    cap: KeyboardCapitalization = KeyboardCapitalization.Sentences,
    keyboard: KeyboardType = KeyboardType.Text,
    mono: Boolean = false,
    singleLine: Boolean = true,
    onChange: (String) -> Unit,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        modifier = modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = singleLine,
        keyboardOptions = KeyboardOptions(capitalization = cap, keyboardType = keyboard),
        textStyle = if (mono) {
            MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace)
        } else {
            MaterialTheme.typography.bodyLarge
        },
    )
}
