package app.carrierwave.android.ui.propagation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import app.carrierwave.android.ui.common.bandColor
import uniffi.cw_ffi.maidenheadIsValid
import uniffi.cw_ffi.standardBandsList

/** HF bands only, matching the iOS start sheet's default selection. */
private val HF_BANDS = setOf("160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m")

/**
 * Configuration form for a new propagation check — the Android analog of iOS
 * `PropagationCheckStartSheet`. Auto-CQ transmit modes are iOS-only (they
 * drive the CAT/radio bridge, which Android doesn't have yet); Android is
 * passive-only — the operator CQs from their own logger/radio while this
 * screen watches RBN + PSK Reporter.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PropagationCheckStartScreen(
    defaultCallsign: String,
    defaultGrid: String,
    onBack: () -> Unit,
    onStart: (PropagationCheckConfig) -> Unit,
    modifier: Modifier = Modifier,
) {
    var callsign by rememberSaveable { mutableStateOf(defaultCallsign) }
    var userGrid by rememberSaveable { mutableStateOf(defaultGrid) }
    val allBands = remember { standardBandsList() }
    var selectedBands by rememberSaveable {
        mutableStateOf(allBands.filter { it in HF_BANDS }.toSet())
    }
    var hasDurationCap by rememberSaveable { mutableStateOf(true) }
    var durationMinutes by rememberSaveable { mutableStateOf(15) }

    val gridValid = userGrid.isBlank() || maidenheadIsValid(userGrid.uppercase())
    val canStart = callsign.isNotBlank() && maidenheadIsValid(userGrid.uppercase()) && selectedBands.isNotEmpty()

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("New Propagation Check") },
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
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Your Callsign", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(
                        value = callsign,
                        onValueChange = { callsign = it.uppercase() },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                        textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text(
                        "Suffix variants like /P, /M, /MM, /QRP are matched automatically.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Bands of Interest", style = MaterialTheme.typography.titleMedium)
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(3),
                        modifier = Modifier
                            .fillMaxWidth()
                            .height((((allBands.size + 2) / 3) * 48).dp),
                    ) {
                        items(allBands) { band ->
                            BandToggleChip(
                                band = band,
                                selected = band in selectedBands,
                                onToggle = {
                                    selectedBands = if (band in selectedBands) selectedBands - band else selectedBands + band
                                },
                            )
                        }
                    }
                    Text(
                        "Spots outside these bands are filtered out. Defaults to all HF bands.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Lifecycle", style = MaterialTheme.typography.titleMedium)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Auto-stop after duration")
                        Switch(checked = hasDurationCap, onCheckedChange = { hasDurationCap = it })
                    }
                    if (hasDurationCap) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text("Duration")
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                IconButton(onClick = { durationMinutes = (durationMinutes - 5).coerceAtLeast(5) }) {
                                    Text("−")
                                }
                                Text("$durationMinutes min", style = MaterialTheme.typography.bodyLarge)
                                IconButton(onClick = { durationMinutes = (durationMinutes + 5).coerceAtMost(120) }) {
                                    Text("+")
                                }
                            }
                        }
                    }
                    Text(
                        "PSK Reporter has a 15 min minimum window — shorter FT8 sessions may show no spots.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Your Location", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(
                        value = userGrid,
                        onValueChange = { userGrid = it.uppercase() },
                        singleLine = true,
                        isError = !gridValid,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                        textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (!gridValid) {
                        Text(
                            "Not a valid grid (e.g. CM87, FN42pr)",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                    Text(
                        "Used to compute distance to each skimmer. Stored on the results so they stay" +
                            " accurate even if you move.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Button(
                onClick = {
                    val bands = allBands.filter { it in selectedBands }
                    onStart(
                        PropagationCheckConfig(
                            callsign = callsign.trim().uppercase(),
                            bands = bands,
                            userGrid = userGrid.trim().uppercase(),
                            durationCapSeconds = if (hasDurationCap) durationMinutes * 60L else null,
                        ),
                    )
                },
                enabled = canStart,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Start")
            }
        }
    }
}

@Composable
private fun BandToggleChip(band: String, selected: Boolean, onToggle: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onToggle,
        label = { Text(band) },
        leadingIcon = {
            Box(
                Modifier
                    .size(10.dp)
                    .clip(CircleShape)
                    .background(bandColor(band)),
            )
        },
    )
}
