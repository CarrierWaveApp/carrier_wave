package app.carrierwave.android.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.ui.AmtPractice
import app.carrierwave.android.ui.common.BandPill
import app.carrierwave.android.ui.common.ModePill
import app.carrierwave.android.ui.common.StatCell
import app.carrierwave.android.ui.common.bandColor
import app.carrierwave.android.ui.common.formatTimestamp

@Composable
fun HomeScreen(vm: HomeViewModel, onSeeAll: () -> Unit) {
    val stats by vm.stats.collectAsStateWithLifecycle()
    val heatmap by vm.heatmap.collectAsStateWithLifecycle()
    val awards by vm.awards.collectAsStateWithLifecycle()
    val amt by vm.amt.collectAsStateWithLifecycle()

    // AMT syncs in another app; re-check whenever Home comes back to the front.
    LifecycleResumeEffect(Unit) {
        vm.refreshAmt()
        onPauseOrDispose {}
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item { TodayCard(stats) }
        if (heatmap.total > 0 || heatmap.amtDays > 0) item { HeatmapCard(heatmap) }
        item { TotalsCard(stats) }
        if ((awards.loaded && stats.total > 0) || amt.signedIn) item { AwardsCard(awards, amt) }
        if (stats.bestDx != null) item { BestDxCard(stats, vm.homeGrid) }
        if (stats.bands.isNotEmpty()) item { BandsCard(stats) }
        if (stats.modes.isNotEmpty()) item { ModesCard(stats) }
        if (stats.recent.isNotEmpty()) item { RecentCard(stats, onSeeAll) }
        if (stats.total == 0) item { EmptyState() }
    }
}

@Composable
private fun DashCard(title: String, trailing: @Composable (() -> Unit)? = null, body: @Composable () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    title.uppercase(),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                trailing?.invoke()
            }
            androidx.compose.foundation.layout.Spacer(Modifier.height(12.dp))
            body()
        }
    }
}

@Composable
private fun TodayCard(stats: HomeStats) {
    DashCard(title = "On the air today") {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stats.today.toString(),
                style = MaterialTheme.typography.displaySmall,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
            )
            androidx.compose.foundation.layout.Spacer(Modifier.width(10.dp))
            Text(
                if (stats.today == 1) "QSO logged today" else "QSOs logged today",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (stats.bandsToday.isNotEmpty()) {
            androidx.compose.foundation.layout.Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                stats.bandsToday.forEach { BandPill(it) }
            }
        }
    }
}

private val HEAT_CELL = 11.dp
private val HEAT_GAP = 3.dp

/**
 * GitHub-style 52-week activity grid, mirroring the iOS Home activity card.
 * Oldest week on the left; auto-scrolls to the current week on first show.
 * Another Morse Trainer practice days are purple: a practice-only day is a
 * solid purple cell shaded by AMT's level, a day with QSOs *and* practice keeps
 * the QSO shade and gains a purple corner dot.
 */
@Composable
private fun HeatmapCard(data: HeatmapData) {
    val scroll = rememberScrollState()
    LaunchedEffect(data.weeks.size) { scroll.scrollTo(scroll.maxValue) }

    DashCard(
        title = "Activity",
        trailing = {
            Text(
                if (data.amtDays > 0) "${data.total} QSOs · ${data.amtDays} practice days" else "${data.total} QSOs · year",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
    ) {
        Column(Modifier.horizontalScroll(scroll)) {
            Row {
                data.weeks.forEachIndexed { index, _ ->
                    Box(Modifier.width(HEAT_CELL + HEAT_GAP), contentAlignment = Alignment.CenterStart) {
                        Text(
                            data.monthLabels[index] ?: "",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            softWrap = false,
                            // Labels are wider than a cell; let them spill right
                            // (months are ≥4 columns apart, so they never collide).
                            modifier = Modifier.wrapContentWidth(Alignment.Start, unbounded = true),
                        )
                    }
                }
            }
            Spacer(Modifier.height(2.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(HEAT_GAP)) {
                data.weeks.forEach { week ->
                    Column(verticalArrangement = Arrangement.spacedBy(HEAT_GAP)) {
                        week.forEach { cell ->
                            Box(
                                Modifier
                                    .size(HEAT_CELL)
                                    .background(heatColor(cell), RoundedCornerShape(2.dp)),
                                contentAlignment = Alignment.BottomEnd,
                            ) {
                                if (cell != null && cell.amtLevel > 0 && cell.level > 0) {
                                    Box(
                                        Modifier
                                            .padding(1.dp)
                                            .size(4.dp)
                                            .background(AmtPractice.copy(alpha = amtAlpha(cell.amtLevel)), CircleShape),
                                    )
                                }
                            }
                        }
                    }
                }
            }
            if (data.amtDays > 0) {
                Spacer(Modifier.height(6.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    LegendSwatch(MaterialTheme.colorScheme.primary, "QSOs")
                    LegendSwatch(AmtPractice, "Morse practice")
                }
            }
        }
    }
}

@Composable
private fun LegendSwatch(color: Color, label: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).background(color, RoundedCornerShape(2.dp)))
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Level 1 → 0.4 … level 4 → 1.0, so one short session still reads against an empty cell. */
private fun amtAlpha(level: Int): Float = 0.2f + 0.2f * level.coerceIn(1, 4)

@Composable
private fun heatColor(cell: HeatCell?): Color = when {
    cell == null -> Color.Transparent
    cell.level == 0 && cell.amtLevel > 0 -> AmtPractice.copy(alpha = amtAlpha(cell.amtLevel))
    cell.level == 0 -> MaterialTheme.colorScheme.surfaceVariant
    else -> MaterialTheme.colorScheme.primary.copy(alpha = 0.25f * cell.level)
}

@Composable
private fun TotalsCard(stats: HomeStats) {
    DashCard(title = "Logbook") {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            StatCell(stats.total.toString(), "QSOs", Modifier.weight(1f))
            StatCell(stats.uniqueCalls.toString(), "Calls", Modifier.weight(1f))
            StatCell(stats.uniqueGrids.toString(), "Grids", Modifier.weight(1f))
            StatCell(stats.bands.size.toString(), "Bands", Modifier.weight(1f))
        }
    }
}

/**
 * Award progress from the shared Rust aggregates: on-air day streak (current /
 * longest), WAS states out of 50, DXCC entities worked — plus the Another
 * Morse Trainer practice streak (purple) once the user has connected AMT.
 */
@Composable
private fun AwardsCard(awards: AwardsStats, amt: AmtHome) {
    DashCard(title = "Awards & streaks") {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            StatCell(
                if (awards.streakCurrent > 0) "${awards.streakCurrent}d" else "—",
                "Streak",
                Modifier.weight(1f),
            )
            StatCell("${awards.streakLongest}d", "Best", Modifier.weight(1f))
            if (amt.signedIn) {
                StatCell(
                    if (amt.streakCurrent > 0) "${amt.streakCurrent}d" else "—",
                    "Morse",
                    Modifier.weight(1f),
                    accent = AmtPractice,
                )
            }
            StatCell("${awards.wasCount}/50", "States", Modifier.weight(1f))
            StatCell(awards.dxccCount.toString(), "DXCC", Modifier.weight(1f))
        }
    }
}

@Composable
private fun BestDxCard(stats: HomeStats, homeGrid: String) {
    val dx = stats.bestDx ?: return
    DashCard(title = "Best DX") {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f)) {
                Text(
                    dx.callsign,
                    style = MaterialTheme.typography.titleLarge,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(
                    "${dx.grid} · from $homeGrid",
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                "%,.0f km".format(dx.km),
                style = MaterialTheme.typography.headlineSmall,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.tertiary,
            )
        }
    }
}

@Composable
private fun BandsCard(stats: HomeStats) {
    val max = stats.bands.maxOf { it.second }.coerceAtLeast(1)
    DashCard(title = "Bands") {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            stats.bands.forEach { (band, count) ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.width(52.dp)) { BandPill(band) }
                    ProportionBar(fraction = count.toFloat() / max, color = bandColor(band), modifier = Modifier.weight(1f))
                    Text(
                        count.toString(),
                        style = MaterialTheme.typography.labelMedium,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun ProportionBar(fraction: Float, color: androidx.compose.ui.graphics.Color, modifier: Modifier = Modifier) {
    Box(
        modifier
            .height(8.dp),
    ) {
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(4.dp),
            modifier = Modifier.fillMaxWidth().height(8.dp),
        ) {}
        Surface(
            color = color,
            shape = RoundedCornerShape(4.dp),
            modifier = Modifier.fillMaxWidth(fraction.coerceIn(0.02f, 1f)).height(8.dp),
        ) {}
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ModesCard(stats: HomeStats) {
    DashCard(title = "Modes") {
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            stats.modes.forEach { (mode, count) -> ModePill(mode, count) }
        }
    }
}

@Composable
private fun RecentCard(stats: HomeStats, onSeeAll: () -> Unit) {
    DashCard(
        title = "Recent",
        trailing = {
            Text(
                "See all",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.clickable(onClick = onSeeAll).padding(2.dp),
            )
        },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            stats.recent.forEach { q ->
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        q.callsign,
                        style = MaterialTheme.typography.bodyMedium,
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        q.band?.let { BandPill(it) }
                        Text(
                            formatTimestamp(q.qsoDate),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyState() {
    Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
        Text(
            "Welcome to Carrier Wave.\nLog your first QSO from the Logger tab.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
