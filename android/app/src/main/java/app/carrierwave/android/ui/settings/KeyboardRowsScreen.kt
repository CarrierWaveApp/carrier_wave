package app.carrierwave.android.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import app.carrierwave.android.data.KeyboardRow
import app.carrierwave.android.data.KeyboardRowsState
import app.carrierwave.android.data.LoggerKeyboardConfig
import app.carrierwave.android.data.PrefixSuggestions

/**
 * Keyboard Rows settings (CAR-290): one screen for the logger's accessory
 * rows — inline enable switches, reorder, and the prefix hot-key source
 * (position-local Suggested vs. Custom). A live preview of the stack is
 * pinned at the bottom, where the rows sit above the real keyboard.
 */
@Composable
fun KeyboardRowsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val state by LoggerKeyboardConfig.state.collectAsState()
    val suggested by PrefixSuggestions.suggested.collectAsState()
    val update = { transform: (KeyboardRowsState) -> KeyboardRowsState ->
        LoggerKeyboardConfig.update(context, transform)
    }

    Column(Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
                Text("Keyboard Rows", style = MaterialTheme.typography.headlineSmall)
            }

            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                Column(Modifier.padding(vertical = 4.dp)) {
                    state.order.forEachIndexed { index, row ->
                        RowEntry(
                            row = row,
                            state = state,
                            suggested = suggested,
                            canMoveUp = index > 0,
                            canMoveDown = index < state.order.lastIndex,
                            onToggle = { enabled ->
                                update { current ->
                                    when (row) {
                                        KeyboardRow.NUMBERS -> current.copy(numbersEnabled = enabled)
                                        KeyboardRow.PREFIXES -> current.copy(prefixesEnabled = enabled)
                                        KeyboardRow.COMMANDS -> current.copy(commandsEnabled = enabled)
                                    }
                                }
                            },
                            onMove = { delta ->
                                update { current ->
                                    val order = current.order.toMutableList()
                                    val target = index + delta
                                    if (target in order.indices) {
                                        order[index] = order[target].also { order[target] = order[index] }
                                    }
                                    current.copy(order = order)
                                }
                            },
                        )
                        if (index < state.order.lastIndex) {
                            HorizontalDivider(Modifier.padding(horizontal = 16.dp))
                        }
                    }
                }
            }
            Text(
                "Rows stack above the keyboard in this order while entering a QSO.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            PrefixSourceCard(state = state, suggested = suggested, update = update)
        }

        StackPreviewBar(state = state, suggested = suggested)
    }
}

@Composable
private fun RowEntry(
    row: KeyboardRow,
    state: KeyboardRowsState,
    suggested: List<String>,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onToggle: (Boolean) -> Unit,
    onMove: (Int) -> Unit,
) {
    val enabled = when (row) {
        KeyboardRow.NUMBERS -> state.numbersEnabled
        KeyboardRow.PREFIXES -> state.prefixesEnabled
        KeyboardRow.COMMANDS -> state.commandsEnabled
    }
    val summary = when (row) {
        KeyboardRow.NUMBERS -> "1–9 0 /"
        KeyboardRow.PREFIXES -> {
            val chips = if (state.prefixMode == KeyboardRowsState.MODE_CUSTOM) state.customPrefixes else suggested
            if (chips.isEmpty()) "None yet" else chips.take(3).joinToString(" ") + if (chips.size > 3) " …" else ""
        }

        KeyboardRow.COMMANDS -> "FREQ MODE SPOT …"
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(row.label, style = MaterialTheme.typography.titleSmall)
            Text(
                summary,
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        IconButton(onClick = { onMove(-1) }, enabled = canMoveUp) {
            Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "Move ${row.label} up")
        }
        IconButton(onClick = { onMove(1) }, enabled = canMoveDown) {
            Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "Move ${row.label} down")
        }
        Switch(checked = enabled, onCheckedChange = onToggle)
    }
}

@Composable
private fun PrefixSourceCard(
    state: KeyboardRowsState,
    suggested: List<String>,
    update: ((KeyboardRowsState) -> KeyboardRowsState) -> Unit,
) {
    var newPrefix by rememberSaveable { mutableStateOf("") }

    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Prefix Keys", style = MaterialTheme.typography.titleMedium)

            listOf(
                Triple(KeyboardRowsState.MODE_SUGGESTED, "Suggested", "Prefixes local to your current position"),
                Triple(KeyboardRowsState.MODE_CUSTOM, "Custom", "Your own list, in your order"),
            ).forEach { (mode, title, subtitle) ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { update { it.copy(prefixMode = mode) } },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    RadioButton(selected = state.prefixMode == mode, onClick = null)
                    Column {
                        Text(title, style = MaterialTheme.typography.bodyMedium)
                        Text(
                            subtitle,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            if (state.prefixMode == KeyboardRowsState.MODE_CUSTOM) {
                HorizontalDivider()
                state.customPrefixes.forEach { prefix ->
                    Row(
                        Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(prefix, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodyLarge)
                        IconButton(onClick = {
                            update { it.copy(customPrefixes = it.customPrefixes - prefix) }
                        }) {
                            Icon(Icons.Filled.Close, contentDescription = "Remove $prefix")
                        }
                    }
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedTextField(
                        value = newPrefix,
                        onValueChange = { raw ->
                            newPrefix = raw.uppercase().filter { it.isLetterOrDigit() }.take(4)
                        },
                        modifier = Modifier.weight(1f),
                        placeholder = { Text("Add prefix") },
                        textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                        singleLine = true,
                    )
                    OutlinedButton(
                        onClick = {
                            val prefix = newPrefix
                            newPrefix = ""
                            update { current ->
                                if (prefix.isEmpty() || prefix in current.customPrefixes) {
                                    current
                                } else {
                                    current.copy(customPrefixes = current.customPrefixes + prefix)
                                }
                            }
                        },
                        enabled = newPrefix.isNotEmpty(),
                    ) { Text("Add") }
                }
                val addable = suggested.filter { it !in state.customPrefixes }
                if (addable.isNotEmpty()) {
                    Text(
                        "Common near you — tap to add",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(
                        Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        addable.forEach { prefix ->
                            PreviewChip(prefix, onClick = {
                                update { it.copy(customPrefixes = it.customPrefixes + prefix) }
                            })
                        }
                    }
                }
            } else {
                Text(
                    if (suggested.isEmpty()) {
                        "No suggestions yet — log a few QSOs first."
                    } else {
                        "Always local to where you are operating right now, " +
                            "recomputed from QSOs logged near your latest position. " +
                            "Your logbook never adds prefixes from somewhere else."
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** Pinned live preview: the accessory stack as it will appear above the keyboard. */
@Composable
private fun StackPreviewBar(state: KeyboardRowsState, suggested: List<String>) {
    val prefixChips = if (state.prefixMode == KeyboardRowsState.MODE_CUSTOM) state.customPrefixes else suggested
    Surface(color = MaterialTheme.colorScheme.surface, tonalElevation = 3.dp) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)) {
            state.order.forEach { row ->
                val chips = when (row) {
                    KeyboardRow.NUMBERS -> if (state.numbersEnabled) {
                        listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "/")
                    } else {
                        emptyList()
                    }

                    KeyboardRow.PREFIXES -> if (state.prefixesEnabled) prefixChips else emptyList()
                    KeyboardRow.COMMANDS -> if (state.commandsEnabled) listOf("FREQ", "MODE", "SPOT", "NOTE") else emptyList()
                }
                if (chips.isNotEmpty()) {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState())
                            .padding(vertical = 3.dp),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        chips.forEach { PreviewChip(it) }
                    }
                }
            }
            Text(
                "Keyboard",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 4.dp),
            )
        }
    }
}

@Composable
private fun PreviewChip(label: String, onClick: (() -> Unit)? = null) {
    val base = Modifier.height(30.dp)
    val modifier = if (onClick != null) base.clickable(onClick = onClick) else base
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(6.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                label,
                modifier = Modifier.padding(horizontal = 8.dp),
                style = MaterialTheme.typography.labelMedium,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
