package app.carrierwave.android.ui.brag

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Forest
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Numbers
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SettingsInputAntenna
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import uniffi.cw_ffi.FfiBragCategory
import uniffi.cw_ffi.FfiBragPeriod
import uniffi.cw_ffi.FfiBragStatMeta
import uniffi.cw_ffi.FfiBragStatResult
import uniffi.cw_ffi.FfiBragStatType
import uniffi.cw_ffi.FfiBragStatValue

/**
 * Maps a stat's semantic `iconKey` (set by `BragStatType::icon_key` in Rust,
 * one per category — see `cw-domain/src/brag_sheet.rs`) to a Material icon.
 * Falls back to a question-mark glyph for any key added on the Rust side
 * without an Android mapping update.
 */
fun iconForKey(key: String): ImageVector = when (key) {
    "number" -> Icons.Filled.Numbers
    "gauge" -> Icons.Filled.Speed
    "bearing" -> Icons.Filled.Explore
    "bolt" -> Icons.Filled.Bolt
    "globe" -> Icons.Filled.Public
    "trophy" -> Icons.Filled.EmojiEvents
    "flame" -> Icons.Filled.LocalFireDepartment
    "tree" -> Icons.Filled.Forest
    "waveform" -> Icons.Filled.GraphicEq
    "antenna" -> Icons.Filled.SettingsInputAntenna
    "sparkles" -> Icons.Filled.AutoAwesome
    else -> Icons.AutoMirrored.Filled.HelpOutline
}

private fun FfiBragPeriod.label(): String = when (this) {
    FfiBragPeriod.WEEKLY -> "Weekly"
    FfiBragPeriod.MONTHLY -> "Monthly"
    FfiBragPeriod.ALL_TIME -> "All-Time"
}

private fun FfiBragCategory.fallbackLabel(): String = name.lowercase()
    .split("_")
    .joinToString(" ") { it.replaceFirstChar(Char::uppercase) }

/**
 * Brag sheet dashboard: a period selector, up to 4 hero stats shown large,
 * then the remaining enabled stats grouped by category. Mirrors the iOS
 * Brag Sheet card, sourced from the same shared `BragSheetApi.compute_brag`.
 */
@Composable
fun BragSheetScreen(vm: BragSheetViewModel, onCustomize: () -> Unit, onShare: () -> Unit = {}) {
    val state by vm.state.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Brag Sheet", style = MaterialTheme.typography.headlineSmall)
            Row {
                IconButton(onClick = onShare) {
                    Icon(Icons.Filled.Share, contentDescription = "Share brag sheet")
                }
                IconButton(onClick = onCustomize) {
                    Icon(Icons.Filled.Settings, contentDescription = "Customize brag sheet")
                }
            }
        }

        PeriodSelector(selected = state.period, onSelect = vm::selectPeriod)

        state.error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }

        if (state.loading) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                CircularProgressIndicator()
            }
            return@Column
        }

        val config = state.configuration?.let {
            when (state.period) {
                FfiBragPeriod.WEEKLY -> it.weekly
                FfiBragPeriod.MONTHLY -> it.monthly
                FfiBragPeriod.ALL_TIME -> it.allTime
            }
        }
        val heroStats = config?.heroStats.orEmpty().toSet()
        val results = state.results
        val heroResults = results.filter { it.statType in heroStats }
        val restResults = results.filter { it.statType !in heroStats }

        val catalogByStat = state.catalog.associateBy { it.statType }

        if (heroResults.isNotEmpty()) {
            HeroRow(heroResults, catalogByStat)
        }

        val categories = state.categories
        categories.forEach { categoryMeta ->
            val statsInCategory = restResults.filter {
                catalogByStat[it.statType]?.category == categoryMeta.category
            }
            if (statsInCategory.isNotEmpty()) {
                CategorySection(
                    categoryMeta.displayName.ifBlank { categoryMeta.category.fallbackLabel() },
                    statsInCategory,
                    catalogByStat,
                )
            }
        }

        if (results.isEmpty() && !state.loading) {
            Text(
                "No stats enabled for this period. Tap the gear to customize.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun PeriodSelector(selected: FfiBragPeriod, onSelect: (FfiBragPeriod) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf(FfiBragPeriod.WEEKLY, FfiBragPeriod.MONTHLY, FfiBragPeriod.ALL_TIME).forEach { period ->
            FilterChip(
                selected = selected == period,
                onClick = { onSelect(period) },
                label = { Text(period.label()) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                ),
            )
        }
    }
}

@Composable
private fun HeroRow(heroes: List<FfiBragStatResult>, catalogByStat: Map<FfiBragStatType, FfiBragStatMeta>) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        modifier = Modifier
            .fillMaxWidth()
            .height((160 * ((heroes.size + 1) / 2)).dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(heroes) { result -> HeroCard(result, statName(result, catalogByStat)) }
    }
}

@Composable
private fun HeroCard(result: FfiBragStatResult, name: String) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                iconForKey(result.iconKey),
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            Text(
                displayValue(result),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            Text(
                name,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
        }
    }
}

@Composable
private fun CategorySection(
    title: String,
    results: List<FfiBragStatResult>,
    catalogByStat: Map<FfiBragStatType, FfiBragStatMeta>,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
            Column(Modifier.padding(vertical = 4.dp)) {
                results.forEach { result -> StatRow(result, statName(result, catalogByStat)) }
            }
        }
    }
}

@Composable
private fun StatRow(result: FfiBragStatResult, name: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(
                iconForKey(result.iconKey),
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Text(name, style = MaterialTheme.typography.bodyMedium)
        }
        Spacer(Modifier.width(8.dp))
        Text(
            displayValue(result),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

/** Prefers the catalog's short display name (falls back to the full display
 * name, then a derived enum name if the catalog hasn't loaded yet). */
private fun statName(result: FfiBragStatResult, catalogByStat: Map<FfiBragStatType, FfiBragStatMeta>): String {
    val meta = catalogByStat[result.statType]
    return meta?.shortDisplayName?.takeIf { it.isNotBlank() }
        ?: meta?.displayName?.takeIf { it.isNotBlank() }
        ?: result.statType.name.lowercase().split("_").joinToString(" ") { it.replaceFirstChar(Char::uppercase) }
}

/** `NoData` renders as an em-dash rather than an empty/misleading string. */
private fun displayValue(result: FfiBragStatResult): String =
    if (result.value is FfiBragStatValue.NoData) "—" else result.formatted
