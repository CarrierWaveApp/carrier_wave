package app.carrierwave.android.ui.sessions

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import uniffi.cw_ffi.FfiActiveStation
import uniffi.cw_ffi.FfiLicenseClass
import uniffi.cw_ffi.FfiScopeRow
import uniffi.cw_ffi.FfiScopeSpot
import uniffi.cw_ffi.frequencyScopeBandRange
import uniffi.cw_ffi.frequencyScopeDefaultHz
import uniffi.cw_ffi.frequencyScopeEvaluate
import uniffi.cw_ffi.frequencyScopeRows

/**
 * The interactive frequency selector — collapsed to a readout summary; tapping
 * opens a scroll-to-tune ruler. Scrolling moves the centered frequency under the
 * reticle, colored green/orange by the band-plan verdict, with live spots as
 * rows, a band/step strip, a Set field, and Find-clear.
 *
 * All band-plan and row/verdict logic is computed by the shared Rust
 * `cw_domain::frequency_scope` (via [frequencyScopeRows] / [frequencyScopeEvaluate]);
 * this composable is pure rendering + scroll geometry.
 */
private const val ROW_HEIGHT_DP = 34
private const val SCOPE_HEIGHT_DP = 260
private val TUNING_STEPS = listOf(100L, 1_000L, 10_000L)
private val SCOPE_LICENSE = FfiLicenseClass.GENERAL

@Composable
fun FrequencyScopeField(
    frequency: String,
    onFrequency: (String) -> Unit,
    mode: String,
    stations: List<FfiActiveStation>,
    determining: Boolean,
) {
    var expanded by remember { mutableStateOf(false) }
    var band by remember { mutableStateOf("20m") }
    var centerHz by remember { mutableLongStateOf(14_074_000L) }
    var stepHz by remember { mutableLongStateOf(1_000L) }
    var touched by remember { mutableStateOf(false) }
    var programmatic by remember { mutableStateOf(false) }

    val spots = remember(stations, band) {
        stations.filter { it.band == band }.map {
            FfiScopeSpot(
                frequencyHz = (it.frequencyMhz * 1_000_000).roundToLong(),
                callsign = it.callsign,
                tier = 0,
                wpm = null,
                ageSeconds = maxOf(0L, nowEpochSeconds() - it.timestamp),
            )
        }
    }
    val rows = remember(band, mode, stepHz, spots) {
        frequencyScopeRows(band, mode, SCOPE_LICENSE, stepHz, spots)
    }
    val verdict = remember(centerHz, band, mode, spots) {
        frequencyScopeEvaluate(centerHz, band, mode, SCOPE_LICENSE, spots)
    }

    // Keep the ruler in sync with the wizard's frequency string.
    LaunchedEffect(frequency) {
        val mhz = parseFreqMhz(frequency)
        if (mhz != null) {
            bandForMhz(mhz)?.let { band = it }
            val hz = snapToStep(band, (mhz * 1_000_000).roundToLong(), stepHz)
            if (hz != centerHz) {
                programmatic = true
                centerHz = hz
            }
        }
    }

    Column(Modifier.fillMaxWidth()) {
        if (determining && frequency.isBlank() && !touched) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CircularProgressIndicator(Modifier.width(18.dp), strokeWidth = 2.dp)
                Text(
                    "Finding an open frequency…",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.secondary,
                )
            }
            return
        }

        FrequencyScopeSummary(centerHz, band, verdict.isGood, verdict.message, expanded) { expanded = !expanded }

        AnimatedVisibility(visible = expanded) {
            Column {
                BandStepStrip(
                    band = band,
                    stepHz = stepHz,
                    onBand = { newBand ->
                        band = newBand
                        touched = true
                        frequencyScopeDefaultHz(newBand, mode)?.let { centerHz = snapToStep(newBand, it, stepHz) }
                    },
                    onCycleStep = {
                        val next = TUNING_STEPS[(TUNING_STEPS.indexOf(stepHz) + 1) % TUNING_STEPS.size]
                        stepHz = next
                        centerHz = snapToStep(band, centerHz, next)
                    },
                )
                FrequencyScopeRuler(
                    rows = rows,
                    centerHz = centerHz,
                    isGood = verdict.isGood,
                    programmatic = programmatic,
                    onProgrammaticConsumed = { programmatic = false },
                    onTuned = { hz ->
                        centerHz = hz
                        touched = true
                        onFrequency(formatMhz(hz / 1_000_000.0))
                    },
                )
                FrequencyScopeFooter(
                    onSet = { mhz ->
                        bandForMhz(mhz)?.let { band = it }
                        stepHz = 100
                        val hz = snapToStep(band, (mhz * 1_000_000).roundToLong(), 100)
                        touched = true
                        centerHz = hz
                        onFrequency(formatMhz(hz / 1_000_000.0))
                    },
                    onFindClear = {
                        findClearHz(rows, centerHz)?.let { hz ->
                            touched = true
                            centerHz = hz
                            onFrequency(formatMhz(hz / 1_000_000.0))
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun FrequencyScopeSummary(
    centerHz: Long,
    band: String,
    isGood: Boolean,
    advisory: String,
    expanded: Boolean,
    onToggle: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onToggle)
            .padding(vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                formatMhz(centerHz / 1_000_000.0),
                style = MaterialTheme.typography.titleMedium,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.SemiBold,
            )
            Text("MHz", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.secondary)
            BandPill(band)
            Spacer(Modifier.weight(1f))
            Text(
                if (expanded) "Done" else "Change",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary,
            )
            Icon(
                if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
        }
        Text(
            advisory.replace("*", ""),
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
            color = if (isGood) ScopeGreen else ScopeOrange,
        )
    }
}

@Composable
private fun BandPill(band: String) {
    Text(
        band,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.secondary,
        modifier = Modifier
            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(50))
            .padding(horizontal = 9.dp, vertical = 3.dp),
    )
}

@Composable
private fun BandStepStrip(band: String, stepHz: Long, onBand: (String) -> Unit, onCycleStep: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            Modifier
                .weight(1f)
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            uniffi.cw_ffi.frequencyScopeAvailableBands().forEach { option ->
                val selected = option == band
                Text(
                    option,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.secondary,
                    modifier = Modifier
                        .clickable { onBand(option) }
                        .background(
                            if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
                            RoundedCornerShape(9.dp),
                        )
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }
        Text(
            stepLabel(stepHz),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier
                .clickable(onClick = onCycleStep)
                .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(9.dp))
                .padding(horizontal = 10.dp, vertical = 6.dp),
        )
    }
}

@Composable
private fun FrequencyScopeRuler(
    rows: List<FfiScopeRow>,
    centerHz: Long,
    isGood: Boolean,
    programmatic: Boolean,
    onProgrammaticConsumed: () -> Unit,
    onTuned: (Long) -> Unit,
) {
    val listState = rememberLazyListState()
    val density = LocalDensity.current
    val rowPx = with(density) { ROW_HEIGHT_DP.dp.toPx() }

    val centeredHz by remember {
        derivedStateOf {
            val info = listState.layoutInfo
            if (info.visibleItemsInfo.isEmpty()) {
                null
            } else {
                val mid = (info.viewportStartOffset + info.viewportEndOffset) / 2
                info.visibleItemsInfo
                    .filter { it.key is Long }
                    .minByOrNull { abs((it.offset + it.size / 2) - mid) }
                    ?.key as? Long
            }
        }
    }

    LaunchedEffect(centerHz, rows) {
        val index = rows.indexOfFirst { it.hz == centerHz }
        if (index >= 0) {
            listState.scrollToItem(0, (index * rowPx).roundToInt())
            if (programmatic) onProgrammaticConsumed()
        }
    }

    LaunchedEffect(listState.isScrollInProgress) {
        if (!listState.isScrollInProgress && !programmatic) {
            centeredHz?.let { if (it != centerHz) onTuned(it) }
        }
    }

    val reticleColor = if (isGood) ScopeGreen else ScopeOrange
    val bg = MaterialTheme.colorScheme.surface
    Box(
        Modifier
            .fillMaxWidth()
            .height(SCOPE_HEIGHT_DP.dp),
    ) {
        LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
            item(key = "padTop") { Spacer(Modifier.height(((SCOPE_HEIGHT_DP - ROW_HEIGHT_DP) / 2).dp)) }
            items(rows, key = { it.hz }) { row -> ScopeRowView(row) }
            item(key = "padBottom") { Spacer(Modifier.height(((SCOPE_HEIGHT_DP - ROW_HEIGHT_DP) / 2).dp)) }
        }
        Column(
            Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .height(ROW_HEIGHT_DP.dp),
        ) {
            Box(Modifier.fillMaxWidth().height(1.5.dp).background(reticleColor))
            Spacer(Modifier.weight(1f))
            Box(Modifier.fillMaxWidth().height(1.5.dp).background(reticleColor))
        }
        Box(
            Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .height(52.dp)
                .background(Brush.verticalGradient(listOf(bg, Color.Transparent))),
        )
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(52.dp)
                .background(Brush.verticalGradient(listOf(Color.Transparent, bg))),
        )
    }
}

@Composable
private fun ScopeRowView(row: FfiScopeRow) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(ROW_HEIGHT_DP.dp)
            .background(if (row.hatched) ScopeOrange.copy(alpha = 0.08f) else Color.Transparent)
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                row.freqText,
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.secondary,
                modifier = Modifier.width(62.dp),
            )
            val spot = row.spot
            when {
                spot != null -> {
                    Box(Modifier.width(6.dp).height(6.dp).background(ScopeGreen, RoundedCornerShape(50)))
                    Text(
                        spot.callsign,
                        style = MaterialTheme.typography.bodyMedium,
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.SemiBold,
                    )
                    if (row.pileupCount > 0) {
                        Text("+${row.pileupCount}", style = MaterialTheme.typography.labelSmall, color = ScopeGreen)
                    }
                    Spacer(Modifier.weight(1f))
                    Text(scopeAge(spot.ageSeconds), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.secondary)
                }
                row.hole != null -> {
                    Text(
                        row.hole ?: "",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.secondary,
                        modifier = Modifier
                            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(50))
                            .padding(horizontal = 6.dp, vertical = 1.dp),
                    )
                }
            }
        }
        row.segLabel?.let {
            Text(
                it.uppercase(),
                style = MaterialTheme.typography.labelSmall.copy(fontSize = 9.sp),
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.TopStart),
            )
        }
    }
}

@Composable
private fun FrequencyScopeFooter(onSet: (Double) -> Unit, onFindClear: () -> Unit) {
    var setText by remember { mutableStateOf("") }
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        OutlinedTextField(
            value = setText,
            onValueChange = { setText = it },
            label = { Text("Set MHz") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.weight(1f),
        )
        TextButton(onClick = {
            parseFreqMhz(setText)?.let { onSet(it) }
            setText = ""
        }) { Text("Set") }
        TextButton(onClick = onFindClear) { Text("Find clear") }
    }
}

// --- Local UI helpers ------------------------------------------------------

private val ScopeGreen = Color(0xFF4CAF83)
private val ScopeOrange = Color(0xFFE8A13A)

private fun scopeAge(ageSeconds: Long): String = when {
    ageSeconds < 60 -> "${ageSeconds}s"
    ageSeconds < 3600 -> "${ageSeconds / 60}m"
    else -> "${ageSeconds / 3600}h"
}

private fun stepLabel(stepHz: Long): String = when (stepHz) {
    100L -> "100 Hz"
    10_000L -> "10 kHz"
    else -> "1 kHz"
}

/** Snap a frequency onto the current step grid so it lands on a ruler row. */
private fun snapToStep(band: String, hz: Long, stepHz: Long): Long {
    val range = frequencyScopeBandRange(band) ?: return hz
    val aligned = range.lowHz + ((hz - range.lowHz).toDouble() / stepHz).roundToLong() * stepHz
    return aligned.coerceIn(range.lowHz, range.highHz)
}

/** Nearest clear, in-plan row to the current frequency (a glide outward). */
private fun findClearHz(rows: List<FfiScopeRow>, centerHz: Long): Long? {
    val index = rows.indexOfFirst { it.hz == centerHz }.takeIf { it >= 0 } ?: return null
    var delta = 0
    while (index - delta >= 0 || index + delta < rows.size) {
        rows.getOrNull(index - delta)?.let { if (it.isGood) return it.hz }
        rows.getOrNull(index + delta)?.let { if (it.isGood) return it.hz }
        delta++
    }
    return null
}
