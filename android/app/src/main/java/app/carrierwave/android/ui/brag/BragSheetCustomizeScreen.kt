package app.carrierwave.android.ui.brag

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import uniffi.cw_ffi.FfiBragCategoryMeta
import uniffi.cw_ffi.FfiBragConfiguration
import uniffi.cw_ffi.FfiBragPeriod
import uniffi.cw_ffi.FfiBragPeriodConfig
import uniffi.cw_ffi.FfiBragPreset
import uniffi.cw_ffi.FfiBragPresetInfo
import uniffi.cw_ffi.FfiBragStatMeta
import uniffi.cw_ffi.FfiBragStatType

/**
 * Customize screen: preset picker, per-stat enable/hero toggles grouped by
 * category, and the three configuration switches (map / equipment summary /
 * gold record badges). Reorder is NOT implemented in this pass — see the
 * phase report; a plain enable/hero toggle list is the accepted subset for
 * Task 13 per the plan's "nice-to-have" carve-out.
 */
@Composable
fun BragSheetCustomizeScreen(vm: BragSheetViewModel, period: FfiBragPeriod, onBack: () -> Unit) {
    val state by vm.state.collectAsState()
    val config = state.configuration?.configFor(period)

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
            }
            Text(
                "Customize — ${period.label()}",
                style = MaterialTheme.typography.titleLarge,
            )
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            PresetPicker(state.presets, config?.basePreset) { preset ->
                vm.applyPreset(preset, period)
            }

            SwitchesCard(
                includeMap = state.configuration?.includeMap ?: false,
                includeEquipmentSummary = state.configuration?.includeEquipmentSummary ?: false,
                goldRecordBadges = state.configuration?.goldRecordBadges ?: false,
                onIncludeMap = vm::setIncludeMap,
                onIncludeEquipmentSummary = vm::setIncludeEquipmentSummary,
                onGoldRecordBadges = vm::setGoldRecordBadges,
            )

            if (config != null) {
                state.categories.forEach { categoryMeta ->
                    val statsInCategory = state.catalog.filter { it.category == categoryMeta.category }
                    if (statsInCategory.isNotEmpty()) {
                        StatToggleCategory(
                            categoryMeta = categoryMeta,
                            stats = statsInCategory,
                            config = config,
                            onToggleStat = { stat -> vm.toggleStat(stat, period) },
                            onToggleHero = { stat -> vm.toggleHero(stat, period) },
                        )
                    }
                }
            }
        }
    }
}

private fun FfiBragPeriod.label(): String = when (this) {
    FfiBragPeriod.WEEKLY -> "Weekly"
    FfiBragPeriod.MONTHLY -> "Monthly"
    FfiBragPeriod.ALL_TIME -> "All-Time"
}

private fun FfiBragConfiguration.configFor(period: FfiBragPeriod): FfiBragPeriodConfig = when (period) {
    FfiBragPeriod.WEEKLY -> weekly
    FfiBragPeriod.MONTHLY -> monthly
    FfiBragPeriod.ALL_TIME -> allTime
}

@Composable
private fun PresetPicker(
    presets: List<FfiBragPresetInfo>,
    currentPreset: FfiBragPreset?,
    onSelect: (FfiBragPreset) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Presets", style = MaterialTheme.typography.titleMedium)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            presets.forEach { preset ->
                FilterChip(
                    selected = preset.preset == currentPreset,
                    onClick = { onSelect(preset.preset) },
                    label = { Text(preset.displayName) },
                )
            }
        }
    }
}

@Composable
private fun SwitchesCard(
    includeMap: Boolean,
    includeEquipmentSummary: Boolean,
    goldRecordBadges: Boolean,
    onIncludeMap: (Boolean) -> Unit,
    onIncludeEquipmentSummary: (Boolean) -> Unit,
    onGoldRecordBadges: (Boolean) -> Unit,
) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            SwitchRow("Include map", includeMap, onIncludeMap)
            SwitchRow("Include equipment summary", includeEquipmentSummary, onIncludeEquipmentSummary)
            SwitchRow("Gold record badges", goldRecordBadges, onGoldRecordBadges)
        }
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun StatToggleCategory(
    categoryMeta: FfiBragCategoryMeta,
    stats: List<FfiBragStatMeta>,
    config: FfiBragPeriodConfig,
    onToggleStat: (FfiBragStatType) -> Unit,
    onToggleHero: (FfiBragStatType) -> Unit,
) {
    val enabled = config.enabledStats.toSet()
    val hero = config.heroStats.toSet()

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            categoryMeta.displayName,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
            Column(Modifier.padding(vertical = 4.dp)) {
                stats.forEach { stat ->
                    StatToggleRow(
                        stat = stat,
                        isEnabled = stat.statType in enabled,
                        isHero = stat.statType in hero,
                        heroDisabled = hero.size >= 4 && stat.statType !in hero,
                        onToggleStat = { onToggleStat(stat.statType) },
                        onToggleHero = { onToggleHero(stat.statType) },
                    )
                }
            }
        }
    }
}

@Composable
private fun StatToggleRow(
    stat: FfiBragStatMeta,
    isEnabled: Boolean,
    isHero: Boolean,
    heroDisabled: Boolean,
    onToggleStat: () -> Unit,
    onToggleHero: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Checkbox(checked = isEnabled, onCheckedChange = { onToggleStat() })
            Text(stat.displayName, style = MaterialTheme.typography.bodyMedium)
        }
        IconButton(
            onClick = onToggleHero,
            enabled = isEnabled && !heroDisabled,
        ) {
            Icon(
                if (isHero) Icons.Filled.Star else Icons.Filled.StarBorder,
                contentDescription = if (isHero) "Remove from hero stats" else "Mark as hero stat",
                modifier = Modifier.size(20.dp),
                tint = if (isHero) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
