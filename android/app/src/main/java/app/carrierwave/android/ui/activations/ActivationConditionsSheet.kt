package app.carrierwave.android.ui.activations

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import uniffi.cw_ffi.FfiActivationMetadata
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * True when [meta] carries any solar reading — mirrors iOS `ConditionsData.hasSolarData`.
 */
private fun FfiActivationMetadata.hasSolarData(): Boolean =
    solarKIndex != null || solarFlux != null || solarSunspots != null ||
        solarConditions != null || solarPropagationRating != null || solarBandConditions != null

/**
 * True when [meta] carries any weather reading — mirrors iOS `ConditionsData.hasWeatherData`.
 */
private fun FfiActivationMetadata.hasWeatherData(): Boolean =
    weatherTemperatureF != null || weatherWindSpeed != null || weatherHumidity != null ||
        weatherDescription != null || weather != null

fun FfiActivationMetadata.hasConditions(): Boolean = hasSolarData() || hasWeatherData()

/**
 * Solar + weather conditions recorded for an activation, the Android analog of
 * iOS `ActivationConditionsSheet`. The source is the same PoLo activation
 * metadata (`FieldStore.fetchActivationMetadata`), so this reads straight off
 * [FfiActivationMetadata] — no new Rust surface. The iOS sheet renders elaborate
 * gauge cards; Android shows the same readings as labeled rating rows (the
 * gauge boundary tables aren't ported — value + qualitative rating is the parity
 * bar here).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivationConditionsSheet(meta: FfiActivationMetadata, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Conditions", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)

            if (meta.hasSolarData()) SolarSection(meta)
            if (meta.hasWeatherData()) WeatherSection(meta)
            TimestampFooter(meta.solarTimestamp ?: meta.weatherTimestamp)
        }
    }
}

@Composable
private fun SolarSection(meta: FfiActivationMetadata) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Solar Conditions", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        meta.solarKIndex?.let {
            ConditionRow("K-Index", String.format(Locale.US, "%.1f", it), kIndexRating(it))
        }
        meta.solarFlux?.let {
            ConditionRow("Solar Flux (SFI)", it.toInt().toString(), sfiRating(it))
        }
        meta.solarSunspots?.let {
            ConditionRow("Sunspot Number", it.toString(), sunspotRating(it.toInt()))
        }
        meta.solarPropagationRating?.let { ConditionRow("Propagation", it, null) }
        meta.solarBandConditions?.let { ConditionRow("Band Conditions", it, null) }
        // Free-text fallback when no structured solar numbers were captured.
        if (meta.solarKIndex == null && meta.solarFlux == null && meta.solarSunspots == null) {
            meta.solarConditions?.let { ConditionRow("Solar", it, null) }
        }
    }
}

@Composable
private fun WeatherSection(meta: FfiActivationMetadata) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Weather", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        (meta.weatherDescription ?: meta.weather)?.let { ConditionRow("Conditions", it, null) }
        meta.weatherTemperatureF?.let {
            ConditionRow("Temperature", "${it.toInt()}°F", tempRating(it))
        }
        meta.weatherWindSpeed?.let {
            val dir = meta.weatherWindDirection?.takeIf { d -> d.isNotBlank() }
            val value = if (dir != null) "${it.toInt()} mph $dir" else "${it.toInt()} mph"
            ConditionRow("Wind", value, windRating(it))
        }
        meta.weatherHumidity?.let {
            ConditionRow("Humidity", "$it%", humidityRating(it.toInt()))
        }
    }
}

@Composable
private fun ConditionRow(label: String, value: String, rating: String?) {
    Surface(
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Column(horizontalAlignment = Alignment.End) {
                Text(value, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                if (rating != null) {
                    Text(
                        rating,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun TimestampFooter(epochSeconds: Long?) {
    if (epochSeconds == null) return
    val text = runCatching {
        Instant.ofEpochSecond(epochSeconds)
            .atZone(ZoneId.systemDefault())
            .format(DateTimeFormatter.ofPattern("MMM d, yyyy h:mm a", Locale.US))
    }.getOrNull() ?: return
    Text(
        "Recorded: $text",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
    )
}

// Rating helpers — verbatim ports of iOS `ConditionsConstants` rating switches.

private fun kIndexRating(kIndex: Double): String = when {
    kIndex < 2 -> "Quiet"
    kIndex < 4 -> "Unsettled"
    kIndex < 5 -> "Active"
    else -> "Storm"
}

private fun sfiRating(sfi: Double): String = when {
    sfi < 71 -> "Poor"
    sfi < 101 -> "Fair"
    sfi < 151 -> "Good"
    else -> "Excellent"
}

private fun sunspotRating(ssn: Int): String = when {
    ssn < 51 -> "Poor"
    ssn < 101 -> "Fair"
    ssn < 151 -> "Good"
    else -> "Ideal"
}

private fun tempRating(temp: Double): String = when {
    temp < 33 -> "Cold"
    temp < 56 -> "Cool"
    temp < 76 -> "Comfortable"
    temp < 91 -> "Warm"
    else -> "Hot"
}

private fun windRating(wind: Double): String = when {
    wind < 11 -> "Calm"
    wind < 21 -> "Moderate"
    wind < 31 -> "Strong"
    else -> "Dangerous"
}

private fun humidityRating(humidity: Int): String = when {
    humidity < 31 -> "Dry"
    humidity < 61 -> "Comfortable"
    humidity < 81 -> "Humid"
    else -> "Oppressive"
}
