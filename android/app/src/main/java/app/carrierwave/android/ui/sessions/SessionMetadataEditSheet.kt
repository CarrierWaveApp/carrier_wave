package app.carrierwave.android.ui.sessions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
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
import uniffi.cw_ffi.FfiLoggingSession

/**
 * Post-session metadata editor — the Android analog of iOS
 * `SessionMetadataEditSheet` ("Edit Info" in the session detail menu). Edits
 * title, my callsign, park reference, equipment, operators, attendees, the
 * per-session QSO comment, and notes. Callsign and park changes cascade to
 * every QSO in the session, so both are gated behind a confirmation dialog
 * (same as iOS). Persistence is fetch-mutate-`upsertLoggingSession` in the
 * caller ([SessionDetailViewModel.saveMetadata]).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionMetadataEditSheet(
    session: FfiLoggingSession,
    onSave: (edited: FfiLoggingSession, cascadeCallsign: Boolean, cascadePark: Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        MetadataEditForm(session, onSave, onDismiss)
    }
}

@Composable
private fun MetadataEditForm(
    session: FfiLoggingSession,
    onSave: (FfiLoggingSession, Boolean, Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    var myCallsign by rememberSaveable(session.id) { mutableStateOf(session.myCallsign) }
    var title by rememberSaveable(session.id) { mutableStateOf(session.customTitle ?: "") }
    var park by rememberSaveable(session.id) { mutableStateOf(session.parkReference ?: "") }
    var watts by rememberSaveable(session.id) { mutableStateOf(session.power?.toString() ?: "") }
    var radio by rememberSaveable(session.id) { mutableStateOf(session.myRig ?: "") }
    var antenna by rememberSaveable(session.id) { mutableStateOf(session.myAntenna ?: "") }
    var key by rememberSaveable(session.id) { mutableStateOf(session.myKey ?: "") }
    var mic by rememberSaveable(session.id) { mutableStateOf(session.myMic ?: "") }
    var extraEquipment by rememberSaveable(session.id) { mutableStateOf(session.extraEquipment ?: "") }
    var operators by rememberSaveable(session.id) { mutableStateOf(session.operatorCallsignsRawValue) }
    var attendees by rememberSaveable(session.id) { mutableStateOf(session.attendees ?: "") }
    var qsoComment by rememberSaveable(session.id) { mutableStateOf(session.qsoComment ?: "") }
    var notes by rememberSaveable(session.id) { mutableStateOf(session.notes ?: "") }

    var confirmCascade by remember { mutableStateOf(false) }

    val isPota = session.parkReference != null
    val callsignChanged = myCallsign.trim().uppercase() != session.myCallsign
    val parkChanged = isPota && park.trim().uppercase() != session.parkReference
    val isValid = myCallsign.isNotBlank() && (!isPota || park.isNotBlank())

    fun edited(): FfiLoggingSession = session.copy(
        myCallsign = myCallsign.trim().uppercase(),
        customTitle = title.trim().ifBlank { null },
        parkReference = if (isPota) park.trim().uppercase() else session.parkReference,
        power = watts.trim().toLongOrNull(),
        myRig = radio.trim().ifBlank { null },
        myAntenna = antenna.trim().ifBlank { null },
        myKey = key.trim().ifBlank { null },
        myMic = mic.trim().ifBlank { null },
        extraEquipment = extraEquipment.trim().ifBlank { null },
        operatorCallsignsRawValue = operators.trim().uppercase(),
        attendees = attendees.trim().ifBlank { null },
        qsoComment = qsoComment.trim().ifBlank { null },
        notes = notes.trim().ifBlank { null },
    )

    fun commit() = onSave(edited(), callsignChanged, parkChanged)

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
            Text("Edit Info", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            TextButton(
                onClick = { if (callsignChanged || parkChanged) confirmCascade = true else commit() },
                enabled = isValid,
            ) { Text("Save") }
        }

        MetaSectionLabel("Session")
        MetaField("Title", title) { title = it }
        MetaField("My Callsign", myCallsign, cap = KeyboardCapitalization.Characters, mono = true) { myCallsign = it }
        if (isPota) {
            MetaField("Park Reference", park, cap = KeyboardCapitalization.Characters, mono = true) { park = it }
        }

        MetaSectionLabel("Equipment")
        MetaField("Power (W)", watts, keyboard = KeyboardType.Number, mono = true) { watts = it }
        MetaField("Radio", radio) { radio = it }
        MetaField("Antenna", antenna) { antenna = it }
        MetaField("Key", key) { key = it }
        MetaField("Mic", mic) { mic = it }
        MetaField("Extra Equipment", extraEquipment) { extraEquipment = it }

        MetaSectionLabel("People")
        MetaField("Additional Operators", operators, cap = KeyboardCapitalization.Characters, mono = true) {
            operators = it
        }
        MetaField("Attendees", attendees) { attendees = it }

        MetaSectionLabel("Notes")
        MetaField("QSO Comment", qsoComment) { qsoComment = it }
        MetaField("Notes", notes, singleLine = false) { notes = it }
    }

    if (confirmCascade) {
        val changes = buildList {
            if (callsignChanged) add("callsign to ${myCallsign.trim().uppercase()}")
            if (parkChanged) add("park to ${park.trim().uppercase()}")
        }
        AlertDialog(
            onDismissRequest = { confirmCascade = false },
            title = { Text("Update all QSOs?") },
            text = {
                Text(
                    "Changing the ${changes.joinToString(" and ")} updates every QSO " +
                        "in this session (${session.qsoCount} QSOs).",
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmCascade = false
                    commit()
                }) { Text("Update") }
            },
            dismissButton = {
                TextButton(onClick = { confirmCascade = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun MetaSectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 6.dp),
    )
}

@Composable
private fun MetaField(
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
