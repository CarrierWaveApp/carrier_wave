package app.carrierwave.android.ui.activations

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import uniffi.cw_ffi.FfiNearKiloPark
import uniffi.cw_ffi.FfiPotaAwards

private val AwardGreen = Color(0xFF22C55E)
private val AwardBlue = Color(0xFF3B82F6)
private val AwardOrange = Color(0xFFF97316)

/**
 * POTA activator awards, the Android analog of iOS `POTAAwardsView`. Shows the
 * same Overview / Award Progress / Special Awards sections, computed from the
 * shared Rust [FfiPotaAwards]. Reached from the activation browser list.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivationAwardsScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    vm: ActivationAwardsViewModel = viewModel(factory = ActivationAwardsViewModel.factory()),
) {
    val ui by vm.ui.collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Awards & Certificates", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when {
                !ui.loaded -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                ui.awards == null -> Text(
                    ui.error ?: "No award data yet. Log park QSOs to see progress.",
                    Modifier.align(Alignment.Center).padding(32.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                else -> AwardsList(ui.awards!!)
            }
        }
    }
}

@Composable
private fun AwardsList(awards: FfiPotaAwards) {
    LazyColumn(
        contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { OverviewCard(awards) }
        item { ProgressCard(awards) }
        item { SpecialCard(awards) }
    }
}

@Composable
private fun OverviewCard(awards: FfiPotaAwards) {
    SectionCard("Overview") {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OverviewStat("Parks", awards.uniqueParksCount.toString(), AwardGreen, Modifier.weight(1f))
            OverviewStat("P2P QSOs", awards.parkToParkCount.toString(), AwardBlue, Modifier.weight(1f))
            OverviewStat("Rover Best", awards.roverMaxParks.toString(), AwardOrange, Modifier.weight(1f))
        }
    }
}

@Composable
private fun OverviewStat(label: String, value: String, tint: Color, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(10.dp),
        color = tint.copy(alpha = 0.12f),
    ) {
        Column(
            Modifier.padding(vertical = 10.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = tint)
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ProgressCard(awards: FfiPotaAwards) {
    SectionCard("Award Progress") {
        TierRow(PotaAwardTiers.uniqueParksProgress(awards.uniqueParksCount))
        if (awards.dxEntitiesCount > 0) TierRow(PotaAwardTiers.dxEntitiesProgress(awards.dxEntitiesCount))
        WasRow(awards.statesActivated.size)
        if (awards.roverMaxParks > 0) TierRow(PotaAwardTiers.roverProgress(awards.roverMaxParks))
        if (awards.repeatOffenderMaxCount > 0) TierRow(PotaAwardTiers.repeatOffenderProgress(awards.repeatOffenderMaxCount))
        if (awards.parkToParkCount > 0) TierRow(PotaAwardTiers.parkToParkProgress(awards.parkToParkCount))
    }
}

@Composable
private fun TierRow(progress: AwardTierProgress) {
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(progress.title, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            if (progress.completed) {
                EarnedBadge()
            } else {
                Text(
                    "${progress.current}/${progress.nextThreshold}",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
        if (!progress.completed) {
            Spacer(Modifier.height(4.dp))
            LinearProgressIndicator(
                progress = { progress.fraction },
                modifier = Modifier.fillMaxWidth().height(6.dp),
                color = AwardBlue,
            )
            progress.nextTierLabel?.let { next ->
                Text(
                    buildString {
                        progress.currentTierLabel?.let { append("$it → ") }
                        append(next)
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            progress.currentTierLabel?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = AwardGreen)
            }
        }
    }
}

@Composable
private fun WasRow(stateCount: Int) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("Activator WAS", style = MaterialTheme.typography.bodyMedium)
            Text(
                "Activate a park in all 50 US states",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (stateCount >= 50) {
            EarnedBadge()
        } else {
            Text("$stateCount/50", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun SpecialCard(awards: FfiPotaAwards) {
    SectionCard("Special Awards") {
        KiloRow(awards)
        BinaryRow("LaPorta N1CC", "10 parks on 10 bands", awards.laPortaEarned, awards.laPortaQualifyingParks, 10)
        BinaryRow("Six Pack", "10 QSOs on 6m from 6 parks", awards.sixPackEarned, null, null)
    }
}

@Composable
private fun KiloRow(awards: FfiPotaAwards) {
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Kilo", style = MaterialTheme.typography.bodyMedium)
                Text(
                    "1,000+ QSOs from a single park",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (awards.kiloParks.isNotEmpty()) {
                Text(
                    "${awards.kiloParks.size} park(s)",
                    style = MaterialTheme.typography.labelMedium,
                    color = AwardGreen,
                    fontWeight = FontWeight.Medium,
                )
            } else {
                Text(
                    "${awards.bestSingleParkTotal}/1,000",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
        if (awards.kiloParks.isEmpty() && awards.bestSingleParkTotal > 0) {
            Spacer(Modifier.height(4.dp))
            LinearProgressIndicator(
                progress = { (awards.bestSingleParkTotal.toFloat() / 1_000f).coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth().height(6.dp),
                color = AwardBlue,
            )
        }
        awards.kiloParks.forEach { ref ->
            Text("✓ $ref", style = MaterialTheme.typography.labelSmall, fontFamily = FontFamily.Monospace, color = AwardGreen)
        }
        if (awards.nearKiloParks.isNotEmpty()) {
            Spacer(Modifier.height(6.dp))
            Text("Approaching Kilo", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
            awards.nearKiloParks.forEach { NearKiloRow(it) }
        }
    }
}

@Composable
private fun NearKiloRow(park: FfiNearKiloPark) {
    Column(Modifier.fillMaxWidth().padding(top = 4.dp)) {
        Row(Modifier.fillMaxWidth()) {
            Text(park.reference, style = MaterialTheme.typography.labelSmall, fontFamily = FontFamily.Monospace, modifier = Modifier.weight(1f))
            Text("${park.qsoCount}/1,000", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        LinearProgressIndicator(
            progress = { (park.qsoCount.toFloat() / 1_000f).coerceIn(0f, 1f) },
            modifier = Modifier.fillMaxWidth().height(4.dp),
            color = AwardOrange,
        )
    }
}

@Composable
private fun BinaryRow(title: String, subtitle: String, earned: Boolean, current: Long?, target: Int?) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium)
            Text(subtitle, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        when {
            earned -> EarnedBadge()
            current != null && target != null -> Text(
                "$current/$target",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
            )
            else -> Text("Not earned", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun EarnedBadge() {
    Text("✓ Earned", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Medium, color = AwardGreen)
}

@Composable
private fun SectionCard(title: String, content: @Composable () -> Unit) {
    Card(
        Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
        shape = RoundedCornerShape(12.dp),
    ) {
        Column(Modifier.padding(14.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(8.dp))
            content()
        }
    }
}
