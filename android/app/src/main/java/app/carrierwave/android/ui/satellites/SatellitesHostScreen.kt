package app.carrierwave.android.ui.satellites

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.carrierwave.android.data.FavoriteSatellites
import app.carrierwave.android.sensors.AntennaMotionService
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.carrierwave.android.data.SatelliteModeFilter
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Host for the satellites feature (opened from More, propagation-check
 * overlay pattern): the live chart is home, with search / upcoming passes /
 * per-satellite passes as internal sub-screens under one [BackHandler].
 */
private enum class SatelliteScreen {
    CHART, SEARCH, UPCOMING, PASSES, QUICK_LOG, ALERT_SETTINGS, SKY_DOME, POINTING,
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SatellitesHostScreen(
    initialNorad: UInt? = null,
    onBack: () -> Unit,
    vm: SatelliteViewModel = viewModel(factory = SatelliteViewModel.factory()),
) {
    val ui by vm.state.collectAsStateWithLifecycle()
    var screen by rememberSaveable { mutableStateOf(SatelliteScreen.CHART) }
    var notice by rememberSaveable { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    // Notification-tap deep link: land selected on the bird.
    LaunchedEffect(initialNorad) {
        if (initialNorad != null) vm.select(initialNorad)
    }

    // The 5 s SGP4 sync loop (iOS cadence). Composition-scoped: leaving the
    // satellites overlay cancels it.
    LaunchedEffect(Unit) {
        while (isActive) {
            vm.tick()
            delay(5_000)
        }
    }

    BackHandler {
        if (screen == SatelliteScreen.CHART) onBack() else screen = SatelliteScreen.CHART
    }

    when (screen) {
        SatelliteScreen.CHART -> Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Satellites") },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                        }
                    },
                    actions = {
                        SatelliteModeFilterMenuButton()
                        IconButton(onClick = { screen = SatelliteScreen.ALERT_SETTINGS }) {
                            Icon(Icons.Filled.NotificationsNone, contentDescription = "Pass alerts")
                        }
                        IconButton(onClick = { screen = SatelliteScreen.UPCOMING }) {
                            Icon(Icons.Filled.CalendarMonth, contentDescription = "Upcoming passes")
                        }
                        IconButton(onClick = { screen = SatelliteScreen.SEARCH }) {
                            Icon(Icons.Filled.Search, contentDescription = "Search satellites")
                        }
                        IconButton(onClick = { scope.launch { vm.refresh(force = true) } }) {
                            Icon(Icons.Filled.Refresh, contentDescription = "Refresh orbital data")
                        }
                    },
                )
            },
        ) { padding ->
            SatelliteChartHome(
                vm = vm,
                ui = ui,
                modifier = Modifier.padding(padding),
                onOpenPasses = { screen = SatelliteScreen.PASSES },
                onQuickLog = { screen = SatelliteScreen.QUICK_LOG },
                onOpenSkyDome = { screen = SatelliteScreen.SKY_DOME },
                onOpenPointing = { screen = SatelliteScreen.POINTING },
                notice = notice,
            )
        }

        SatelliteScreen.SEARCH -> SatelliteSearchScreen(
            items = ui.searchItems,
            onSelect = { norad ->
                vm.select(norad)
                screen = SatelliteScreen.CHART
            },
            onBack = { screen = SatelliteScreen.CHART },
        )

        SatelliteScreen.UPCOMING -> SatelliteUpcomingScreen(
            vm = vm,
            onSelect = { norad ->
                vm.select(norad)
                screen = SatelliteScreen.CHART
            },
            onBack = { screen = SatelliteScreen.CHART },
        )

        SatelliteScreen.PASSES -> {
            val selected = ui.selectedNoradId
            if (selected != null) {
                SatellitePassListScreen(
                    vm = vm,
                    noradId = selected,
                    onBack = { screen = SatelliteScreen.CHART },
                )
            } else {
                screen = SatelliteScreen.CHART
            }
        }

        SatelliteScreen.ALERT_SETTINGS -> SatelliteAlertSettingsScreen(
            onBack = { screen = SatelliteScreen.CHART },
        )

        SatelliteScreen.SKY_DOME -> {
            val context = LocalContext.current
            val motion = remember {
                AntennaMotionService(context, vm.observer?.latDeg, vm.observer?.lonDeg)
            }
            SatelliteSkyDomeScreen(
                vm = vm,
                motion = motion,
                onClose = { screen = SatelliteScreen.CHART },
            )
        }

        SatelliteScreen.POINTING -> {
            val selected = ui.selectedNoradId
            if (selected != null) {
                val context = LocalContext.current
                val motion = remember {
                    AntennaMotionService(context, vm.observer?.latDeg, vm.observer?.lonDeg)
                }
                AntennaPointingScreen(
                    vm = vm,
                    motion = motion,
                    noradId = selected,
                    onQuickLog = { screen = SatelliteScreen.QUICK_LOG },
                    onDismiss = { screen = SatelliteScreen.CHART },
                )
            } else {
                screen = SatelliteScreen.CHART
            }
        }

        SatelliteScreen.QUICK_LOG -> {
            val selected = ui.selectedNoradId
            if (selected != null) {
                SatelliteQuickLogScreen(
                    vm = vm,
                    noradId = selected,
                    onBack = { screen = SatelliteScreen.CHART },
                    onLogged = { count ->
                        notice = "Logged $count QSO${if (count == 1) "" else "s"}"
                        screen = SatelliteScreen.CHART
                    },
                )
            } else {
                screen = SatelliteScreen.CHART
            }
        }
    }
}

/** Chart home: status line, selected-bird card, and the live catalog. */
@Composable
private fun SatelliteChartHome(
    vm: SatelliteViewModel,
    ui: SatelliteViewModel.UiState,
    modifier: Modifier = Modifier,
    onOpenPasses: () -> Unit,
    onQuickLog: () -> Unit,
    onOpenSkyDome: () -> Unit,
    onOpenPointing: () -> Unit,
    notice: String? = null,
) {
    Column(modifier = modifier.fillMaxSize()) {
        if (notice != null) {
            Text(
                notice,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }
        when {
            ui.loading -> Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalArrangement = Arrangement.Center,
            ) {
                CircularProgressIndicator()
            }

            ui.error != null -> Text(
                "Couldn't load satellites: ${ui.error}",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(16.dp),
            )

            vm.observer == null -> Text(
                "Set your home grid in Account to see the sky from your QTH.",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(16.dp),
            )

            else -> {
                // Mode/band filters: hide birds with no matching transmitter;
                // the explicitly selected bird always stays.
                val modeSelection by SatelliteModeFilter.selection.collectAsStateWithLifecycle()
                val uplinkBands by SatelliteModeFilter.uplinkBands.collectAsStateWithLifecycle()
                val downlinkBands by
                    SatelliteModeFilter.downlinkBands.collectAsStateWithLifecycle()
                val minPeak by SatelliteModeFilter.minPeakElevation.collectAsStateWithLifecycle()
                val heardOnly by
                    SatelliteModeFilter.heardRecentlyOnly.collectAsStateWithLifecycle()
                val favoritesOnly by
                    SatelliteModeFilter.favoritesOnly.collectAsStateWithLifecycle()
                val mask by SatelliteModeFilter.horizonMask.collectAsStateWithLifecycle()
                val favorites by FavoriteSatellites.state.collectAsStateWithLifecycle()
                // Birds with an upcoming pass peaking >= threshold and
                // clearing the horizon mask; null = both gates off or sweep
                // not loaded (never blank the chart on missing data).
                var sweepQualified by remember { mutableStateOf<Set<UInt>?>(null) }
                LaunchedEffect(minPeak, mask) {
                    sweepQualified =
                        if (minPeak <= 0 && !SatelliteModeFilter.horizonActive(mask)) {
                            null
                        } else {
                            vm.upcomingPasses(emptyList())
                                .filter {
                                    it.pass.peakElevationDeg >= minPeak &&
                                        SatelliteModeFilter.horizonAllows(
                                            it.pass.peakAzimuthDeg,
                                            it.pass.peakElevationDeg,
                                            mask,
                                        )
                                }
                                .map { it.noradId }
                                .toSet()
                        }
                }
                val filteredUi = ui.copy(
                    positions = ui.positions.filter { position ->
                        position.noradId == ui.selectedNoradId ||
                            (
                                (!favoritesOnly || position.noradId in favorites) &&
                                    SatelliteModeFilter.matches(
                                        vm.transmitters(position.noradId),
                                        modeSelection,
                                        uplinkBands,
                                        downlinkBands,
                                        heardOnly,
                                    ) && sweepQualified?.contains(position.noradId) != false
                                )
                    },
                )
                SatelliteAzimuthalChart(
                    vm = vm,
                    ui = filteredUi,
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                )
                SatelliteStatusBar(filteredUi, onOpenSkyDome)
                val selected = ui.selectedNoradId
                if (selected != null) {
                    SatelliteInfoCard(
                        vm = vm,
                        noradId = selected,
                        onOpenPasses = onOpenPasses,
                        onQuickLog = onQuickLog,
                        onOpenPointing = onOpenPointing,
                        onDismiss = { vm.select(null) },
                    )
                }
            }
        }
    }
}

@Composable
private fun SatelliteStatusBar(ui: SatelliteViewModel.UiState, onOpenSkyDome: () -> Unit) {
    val tleAge = remember(ui.tlesFetchedAtEpoch) {
        val hours = (System.currentTimeMillis() / 1_000 - ui.tlesFetchedAtEpoch) / 3_600
        if (hours < 1) "<1 h" else "$hours h"
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "${ui.positions.size} ham satellites · QTH ${ui.observerGrid} · TLEs $tleAge ago" +
                if (ui.tlesStale) " (stale)" else "",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        TextButton(onClick = onOpenSkyDome) {
            Text("Sky view")
        }
    }
}
