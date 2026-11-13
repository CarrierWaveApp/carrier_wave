package app.carrierwave.android.ui.common

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import app.carrierwave.android.CwApp
import app.carrierwave.android.data.CallsignPrefixer
import app.carrierwave.android.data.KeyboardRow
import app.carrierwave.android.data.KeyboardRowsState
import app.carrierwave.android.data.LoggerKeyboardConfig
import app.carrierwave.android.data.PrefixSuggestions
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import uniffi.cw_ffi.FfiDuplicateStatus
import uniffi.cw_ffi.FfiQuickToken
import uniffi.cw_ffi.FfiSessionMetadataEntry
import uniffi.cw_ffi.loggerCommandRowCatalog

/**
 * The shared quick-entry command bar — one monospace input parsed by the shared
 * Rust grammar (`parseQuickEntry`), with token chips, a day-scoped dupe badge,
 * enrichment badges, SCP suggestions, and a send button. Used by both the hunter
 * log and the activation logger so the two entry surfaces stay identical.
 *
 * A callsign-less "field line" (e.g. `14.046 CW`) surfaces `sessionMeta`; the
 * send button then applies it as defaults for future QSOs instead of logging one.
 */
@Composable
fun QuickEntryCommandBar(
    tokens: List<FfiQuickToken>,
    callsign: String?,
    dupeStatus: FfiDuplicateStatus?,
    suggestions: List<String>,
    canLog: Boolean,
    isLogging: Boolean,
    error: String?,
    sessionMeta: FfiSessionMetadataEntry?,
    onChanged: (String) -> Unit,
    onLog: (onSuccess: () -> Unit) -> Unit,
    onApplyMeta: () -> Unit,
    seedText: String? = null,
    onSeedConsumed: () -> Unit = {},
) {
    // TextFieldValue (not a plain String) so accessory-key inserts land at the
    // caret and can replace a selection, instead of always appending at the end.
    var value by rememberSaveable(stateSaver = TextFieldValue.Saver) { mutableStateOf(TextFieldValue("")) }
    var focused by remember { mutableStateOf(false) }
    // The shared command-row catalog (Rust `cw_domain::logger_command`).
    val commandRow = remember { runCatching { loggerCommandRowCatalog() }.getOrDefault(emptyList()) }
    // Insert `fragment` at the caret (replacing any selection) and leave the caret
    // after it — the number/command keys behave like typing.
    val insertAtCursor = { fragment: String ->
        val sel = value.selection
        val next = value.text.substring(0, sel.start) + fragment + value.text.substring(sel.end)
        value = TextFieldValue(next, TextRange(sel.start + fragment.length))
        onChanged(next)
    }
    val setText = { new: String ->
        value = TextFieldValue(new, TextRange(new.length))
        onChanged(new)
    }
    // A spot/recall tap seeds the field (then the seed is cleared so re-taps re-fire).
    LaunchedEffect(seedText) {
        if (!seedText.isNullOrEmpty()) {
            setText(seedText)
            onSeedConsumed()
        }
    }
    val canSubmit = canLog || sessionMeta != null
    val submit = {
        if (sessionMeta != null) {
            onApplyMeta()
            value = TextFieldValue("")
        } else {
            onLog { value = TextFieldValue("") }
        }
    }
    Surface(color = MaterialTheme.colorScheme.surface, tonalElevation = 3.dp) {
        Column(
            Modifier
                .fillMaxWidth()
                .imePadding()
                .padding(horizontal = 12.dp, vertical = 8.dp),
        ) {
            if (!callsign.isNullOrEmpty()) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier.padding(bottom = 6.dp),
                ) {
                    dupeStatus?.let { DupeBadge(it) }
                    EnrichmentBadges(callsign = callsign, includeQrz = true)
                }
            }
            ScpSuggestionRow(
                suggestions = suggestions,
                onPick = { picked -> setText("$picked ") },
                modifier = Modifier.padding(bottom = 6.dp),
            )
            if (tokens.isNotEmpty()) {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(tokens, key = { it.index.toInt() }) { TokenText(it) }
                }
                Spacer(Modifier.height(6.dp))
            }
            error?.let {
                Text(
                    "⚠ $it",
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.padding(bottom = 4.dp),
                )
            }
            sessionMeta?.let { meta ->
                Text(
                    sessionMetaHint(meta),
                    color = MaterialTheme.colorScheme.tertiary,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.padding(bottom = 4.dp),
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = value,
                    onValueChange = {
                        value = it
                        onChanged(it.text)
                    },
                    modifier = Modifier.weight(1f).onFocusChanged { focused = it.isFocused },
                    placeholder = { Text("W1AW 599 20m US-1234 …", fontFamily = FontFamily.Monospace) },
                    textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Characters,
                        imeAction = ImeAction.Send,
                    ),
                    keyboardActions = KeyboardActions(onSend = { if (canSubmit) submit() }),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = MaterialTheme.colorScheme.primary,
                        unfocusedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f),
                    ),
                )
                FilledIconButton(
                    onClick = submit,
                    enabled = canSubmit && !isLogging,
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = if (sessionMeta != null) {
                            MaterialTheme.colorScheme.tertiary
                        } else {
                            MaterialTheme.colorScheme.primary
                        },
                    ),
                ) {
                    if (isLogging) {
                        CircularProgressIndicator(Modifier.size(20.dp), color = MaterialTheme.colorScheme.onPrimary)
                    } else if (sessionMeta != null) {
                        Icon(Icons.Filled.CheckCircle, contentDescription = "Apply to future QSOs")
                    } else {
                        Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Log contact")
                    }
                }
            }
            // Accessory rows stacked directly above the keyboard (below the entry
            // box), shown while typing. Which rows appear, and in what order, is
            // user-configurable (Keyboard Rows settings, CAR-290).
            if (focused) {
                val rowsConfig by LoggerKeyboardConfig.state.collectAsState()
                val suggestedPrefixes by PrefixSuggestions.suggested.collectAsState()
                val sessionApi = (LocalContext.current.applicationContext as CwApp).sessionApi
                LaunchedEffect(Unit) { PrefixSuggestions.refresh(sessionApi) }
                val prefixChips = if (rowsConfig.prefixMode == KeyboardRowsState.MODE_CUSTOM) {
                    rowsConfig.customPrefixes
                } else {
                    suggestedPrefixes
                }
                rowsConfig.order.forEach { row ->
                    when (row) {
                        KeyboardRow.NUMBERS -> if (rowsConfig.numbersEnabled) {
                            Spacer(Modifier.height(6.dp))
                            Row(
                                Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                NumberKeys.forEach { key ->
                                    AccessoryKey(key, Modifier.weight(1f)) { insertAtCursor(key) }
                                }
                            }
                        }

                        KeyboardRow.PREFIXES -> if (rowsConfig.prefixesEnabled && prefixChips.isNotEmpty()) {
                            Spacer(Modifier.height(6.dp))
                            LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                items(prefixChips, key = { it }) { prefix ->
                                    AccessoryKey(prefix) {
                                        val next = CallsignPrefixer.apply(prefix, value.text, prefixChips)
                                        value = TextFieldValue(next, TextRange(next.length))
                                        onChanged(next)
                                    }
                                }
                            }
                        }

                        KeyboardRow.COMMANDS -> if (rowsConfig.commandsEnabled && commandRow.isNotEmpty()) {
                            Spacer(Modifier.height(6.dp))
                            LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                items(commandRow, key = { it.key }) { item ->
                                    AccessoryKey(item.label) { insertAtCursor("${item.insert} ") }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Keyboard-accessory keys — the iOS number row (digits + "/"). */
private val NumberKeys = listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "/")

/** A single flat accessory key that inserts [label] into the command bar. */
@Composable
private fun AccessoryKey(label: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        modifier = modifier.height(40.dp),
        shape = RoundedCornerShape(6.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                label,
                modifier = Modifier.padding(horizontal = 10.dp),
                style = MaterialTheme.typography.titleMedium,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Hint for a pending session-metadata line — says what will apply to future
 *  QSOs and calls out tokens the entry surface can't take. */
private fun sessionMetaHint(meta: FfiSessionMetadataEntry): String {
    val applied = buildList {
        meta.frequency?.let { add("%.3f MHz".format(it) + (meta.band?.let { band -> " ($band)" } ?: "")) }
        meta.mode?.let { add(it) }
    }
    val ignored = buildList {
        meta.grid?.let { add(it) }
        addAll(meta.unsupported)
    }
    return buildString {
        if (applied.isNotEmpty()) append("Sets defaults for future QSOs: ${applied.joinToString(" · ")}")
        if (ignored.isNotEmpty()) {
            if (isNotEmpty()) append(" — ")
            append("can't set here: ${ignored.joinToString(", ")}")
        }
    }
}

@Composable
private fun TokenText(token: FfiQuickToken) {
    Surface(
        shape = RoundedCornerShape(6.dp),
        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
    ) {
        Text(
            token.text,
            Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelMedium,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}
