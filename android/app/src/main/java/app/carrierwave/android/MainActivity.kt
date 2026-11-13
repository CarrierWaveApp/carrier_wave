package app.carrierwave.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Radio
import androidx.compose.material.icons.filled.RadioButtonChecked
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.ui.CwTheme
import app.carrierwave.android.ui.account.AccountScreen
import app.carrierwave.android.ui.account.AccountViewModel
import app.carrierwave.android.ui.activations.ActivationsScreen
import app.carrierwave.android.ui.brag.BragSheetCustomizeScreen
import app.carrierwave.android.ui.brag.BragSheetScreen
import app.carrierwave.android.ui.brag.BragSheetShareScreen
import app.carrierwave.android.ui.brag.BragSheetShareViewModel
import app.carrierwave.android.ui.brag.BragSheetViewModel
import app.carrierwave.android.ui.clubs.ClubDetailScreen
import app.carrierwave.android.ui.clubs.ClubDetailViewModel
import app.carrierwave.android.ui.clubs.ClubsViewModel
import app.carrierwave.android.ui.common.CountBadge
import app.carrierwave.android.ui.friends.FriendsContainerScreen
import app.carrierwave.android.ui.home.HomeScreen
import app.carrierwave.android.ui.home.HomeViewModel
import app.carrierwave.android.ui.logbook.LogbookScreen
import app.carrierwave.android.ui.logbook.LogbookViewModel
import app.carrierwave.android.ui.hunter.HunterLogScreen
import app.carrierwave.android.ui.hunter.HunterLogViewModel
import app.carrierwave.android.ui.map.MapScreen
import app.carrierwave.android.ui.map.MapViewModel
import app.carrierwave.android.ui.propagation.PropagationCheckHostScreen
import app.carrierwave.android.notifications.SatelliteAlertScheduler
import app.carrierwave.android.ui.satellites.SatellitesHostScreen
import app.carrierwave.android.ui.sessions.LoggerViewModel
import app.carrierwave.android.ui.sessions.SessionsContainerScreen
import app.carrierwave.android.ui.sessions.SessionWizardScreen
import app.carrierwave.android.ui.sessions.SessionWizardViewModel
import app.carrierwave.android.ui.settings.AmtSettingsScreen
import app.carrierwave.android.ui.settings.DebugLogScreen
import app.carrierwave.android.ui.settings.KeyboardRowsScreen
import app.carrierwave.android.ui.spots.Spot
import app.carrierwave.android.ui.spots.SpotsViewModel
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.FloatingActionButton
import uniffi.cw_ffi.FfiActiveStation
import uniffi.cw_ffi.FfiBragPeriod
import uniffi.cw_ffi.FfiBragPeriodConfig

/**
 * Primary navigation. Android is a hunting-focused app for now: the Hunter
 * tab IS the hunter log (live spot feed + quick-entry command bar); the iOS
 * Sessions activation surface was removed 2026-07-04 (git history has it).
 * Friends folds the social graph, activity feed, and Clubs into one tab.
 *
 * The bar shows up to [MAX_PRIMARY_TABS] primaries followed by a More overflow,
 * matching the iOS "first N stick, the rest move to More" rule.
 */
private enum class Tab(val label: String, val icon: ImageVector) {
    HOME("Home", Icons.Filled.Home),
    SESSIONS("Sessions", Icons.Filled.RadioButtonChecked),
    HUNTER("Hunter", Icons.Filled.GraphicEq),
    LOGBOOK("Logbook", Icons.AutoMirrored.Filled.MenuBook),
    MAP("Map", Icons.Filled.Map),
    FRIENDS("Friends", Icons.Filled.People),
    MORE("More", Icons.Filled.MoreHoriz),
}

/** Primary tabs shown directly in the bottom bar; the rest collapse into More.
 * Six so the new Sessions tab doesn't push Friends out (More maps straight to
 * Account, so a dropped tab would be unreachable). */
private const val MAX_PRIMARY_TABS = 6

/** Tabs rendered in the bottom bar: the first [MAX_PRIMARY_TABS] primaries + More. */
private val barTabs: List<Tab> =
    Tab.entries.filter { it != Tab.MORE }.take(MAX_PRIMARY_TABS) + Tab.MORE

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Edge-to-edge so Compose receives IME insets: lets the command bar pad
        // above the keyboard and lets us hide the bottom nav while typing.
        enableEdgeToEdge()
        // Process a magic-link deep link that cold-launched the app. Guarded on
        // savedInstanceState so a config-change recreation doesn't re-run it.
        if (savedInstanceState == null) handleDeepLink(intent)
        setContent { CwTheme { CarrierWaveApp() } }
    }

    // The app is singleTop, so a link tapped while it's running arrives here
    // rather than creating a new instance.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
    }

    /** Route an incoming VIEW intent (App Link or carrierwave://auth) to the
     * shared OAuth completion, and a pass-alert notification tap (NORAD id
     * extra) to the satellites overlay. */
    private fun handleDeepLink(intent: Intent?) {
        val norad = intent?.getIntExtra(SatelliteAlertScheduler.EXTRA_NORAD, 0) ?: 0
        if (norad > 0) {
            (application as CwApp).requestOpenSatellite(norad.toUInt())
            return
        }
        val data = intent?.takeIf { it.action == Intent.ACTION_VIEW }?.data ?: return
        (application as CwApp).handleAuthDeepLink(data)
    }

    // Mirror iOS backgrounding: skip spot-engine poll ticks while the app is
    // not visible, resume + refresh when it comes back.
    override fun onStart() {
        super.onStart()
        (application as CwApp).spotEngine.resume()
    }

    override fun onStop() {
        (application as CwApp).spotEngine.pause()
        super.onStop()
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun CarrierWaveApp() {
    val homeVm: HomeViewModel = viewModel(factory = HomeViewModel.factory())
    val accountVm: AccountViewModel = viewModel(factory = AccountViewModel.factory())
    val clubsVm: ClubsViewModel = viewModel(factory = ClubsViewModel.factory())
    val logbookVm: LogbookViewModel = viewModel(factory = LogbookViewModel.factory())
    val mapVm: MapViewModel = viewModel(factory = MapViewModel.factory())
    val hunterVm: HunterLogViewModel = viewModel(factory = HunterLogViewModel.factory())
    val loggerVm: LoggerViewModel = viewModel(factory = LoggerViewModel.factory())
    val loggerUi by loggerVm.ui.collectAsState()
    val spotsVm: SpotsViewModel = viewModel(factory = SpotsViewModel.factory())

    var tab by rememberSaveable { mutableStateOf(Tab.HOME) }
    var openClubId by rememberSaveable { mutableStateOf<String?>(null) }

    // A magic-link sign-in completed via deep link — surface it by jumping to
    // the Account tab (AccountViewModel shows the "Signed in" message).
    val cwApp = LocalContext.current.applicationContext as CwApp
    LaunchedEffect(Unit) {
        cwApp.authDeepLink.collect { result ->
            if (result is AuthDeepLinkResult.SignedIn || result is AuthDeepLinkResult.AttachedToAccount) {
                tab = Tab.MORE
            }
        }
    }
    var showBragSheet by rememberSaveable { mutableStateOf(false) }
    var showKeyboardRows by rememberSaveable { mutableStateOf(false) }
    var showDebugLog by rememberSaveable { mutableStateOf(false) }
    var showAmt by rememberSaveable { mutableStateOf(false) }
    var showActivations by rememberSaveable { mutableStateOf(false) }
    var showPropagationCheck by rememberSaveable { mutableStateOf(false) }
    var showSatellites by rememberSaveable { mutableStateOf(false) }
    // Pass-alert notification tap: open satellites landed on the bird.
    // (Long because rememberSaveable can't hold UInt.)
    var satelliteDeepLinkNorad by rememberSaveable { mutableStateOf<Long?>(null) }
    LaunchedEffect(Unit) {
        cwApp.satelliteOpenRequests.collect { norad ->
            satelliteDeepLinkNorad = norad.toLong()
            showSatellites = true
            cwApp.consumeSatelliteOpenRequest()
        }
    }
    var showBragCustomize by rememberSaveable { mutableStateOf(false) }
    var showBragShare by rememberSaveable { mutableStateOf(false) }
    var showSessionWizard by rememberSaveable { mutableStateOf(false) }
    // Bumped on each open so the wizard gets a fresh (activity-scoped) ViewModel
    // — otherwise a completed session's started=true would re-dismiss instantly.
    var wizardLaunch by rememberSaveable { mutableStateOf(0) }

    if (showKeyboardRows) {
        BackHandler { showKeyboardRows = false }
        KeyboardRowsScreen(onBack = { showKeyboardRows = false })
        return
    }

    if (showDebugLog) {
        BackHandler { showDebugLog = false }
        DebugLogScreen(onBack = { showDebugLog = false })
        return
    }

    if (showAmt) {
        BackHandler { showAmt = false }
        AmtSettingsScreen(onBack = { showAmt = false })
        return
    }

    if (showActivations) {
        BackHandler { showActivations = false }
        ActivationsScreen(onBack = { showActivations = false })
        return
    }

    if (showPropagationCheck) {
        // PropagationCheckHostScreen owns its own BackHandler across its
        // start/live/results sub-states (see its doc), so no BackHandler here.
        PropagationCheckHostScreen(onBack = { showPropagationCheck = false })
        return
    }

    if (showSatellites) {
        // SatellitesHostScreen owns its own BackHandler across its
        // chart/search/passes sub-states, so no BackHandler here.
        SatellitesHostScreen(
            initialNorad = satelliteDeepLinkNorad?.toUInt(),
            onBack = {
                showSatellites = false
                satelliteDeepLinkNorad = null
            },
        )
        return
    }

    if (showSessionWizard) {
        BackHandler { showSessionWizard = false }
        val wizardVm: SessionWizardViewModel =
            viewModel(key = "session-wizard-$wizardLaunch", factory = SessionWizardViewModel.factory())
        SessionWizardScreen(
            wizardVm,
            stationsProvider = { spotsVm.state.value.spots.mapNotNull(Spot::toActiveStation) },
            // Land on the Sessions tab after the wizard closes: if it created a
            // session the container shows the logger, otherwise the start prompt.
            onDismiss = { showSessionWizard = false; tab = Tab.SESSIONS },
        )
        return
    }

    val openClub = openClubId?.let { id -> clubsVm.state.value.clubs.firstOrNull { it.id == id } }
    if (openClub != null) {
        BackHandler { openClubId = null }
        val app = LocalContext.current.applicationContext as CwApp
        val detailVm: ClubDetailViewModel = viewModel(
            key = openClub.id,
            factory = viewModelFactory {
                initializer {
                    ClubDetailViewModel(
                        app.store,
                        app.clubsApi,
                        app.authApi,
                        app.qrzApi,
                        openClub.id,
                        app.userCallsign,
                    )
                }
            },
        )
        ClubDetailScreen(detailVm, openClub, app.userHomeGrid, onBack = { openClubId = null })
        return
    }

    if (showBragSheet) {
        BackHandler {
            when {
                showBragShare -> showBragShare = false
                showBragCustomize -> showBragCustomize = false
                else -> showBragSheet = false
            }
        }
        val bragVm: BragSheetViewModel = viewModel(factory = BragSheetViewModel.factory())
        if (showBragCustomize) {
            val state by bragVm.state.collectAsState()
            BragSheetCustomizeScreen(
                bragVm,
                period = state.period,
                onBack = { showBragCustomize = false },
            )
        } else if (showBragShare) {
            val state by bragVm.state.collectAsState()
            val app = LocalContext.current.applicationContext as CwApp
            val shareVm: BragSheetShareViewModel = viewModel(factory = BragSheetShareViewModel.factory())
            val periodConfig = when (state.period) {
                FfiBragPeriod.WEEKLY -> state.configuration?.weekly
                FfiBragPeriod.MONTHLY -> state.configuration?.monthly
                FfiBragPeriod.ALL_TIME -> state.configuration?.allTime
            } ?: FfiBragPeriodConfig(enabledStats = emptyList(), heroStats = emptyList(), basePreset = null)
            BragSheetShareScreen(
                shareVm,
                callsign = app.userCallsign,
                period = state.period,
                config = periodConfig,
                results = state.results,
                catalog = state.catalog.associateBy { it.statType },
                onBack = { showBragShare = false },
            )
        } else {
            BragSheetScreen(bragVm, onCustomize = { showBragCustomize = true }, onShare = { showBragShare = true })
        }
        return
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = { BrandBar(tab) },
        floatingActionButton = {
            // The + starts a NEW activation — shown only on tabs where "+" means
            // that (Home/Sessions). On the Hunter tab it floated over the command
            // bar's send button and read as "log this hunt", routing hunters into
            // the session wizard. Also hidden whenever a session is already active
            // (starting another would pause the current one, and on the Sessions
            // tab it would overlap the logger's command-bar send button).
            if (loggerUi.session == null && (tab == Tab.HOME || tab == Tab.SESSIONS)) {
                FloatingActionButton(onClick = { wizardLaunch++; showSessionWizard = true }) {
                    Icon(Icons.Filled.Add, contentDescription = "Start session")
                }
            }
        },
        bottomBar = {
            // Hidden while the keyboard is up so the logger's command bar sits
            // directly above it (matches iOS hiding the tab bar when typing).
            if (!WindowInsets.isImeVisible) {
                NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                    barTabs.forEach { entry ->
                        NavigationBarItem(
                            selected = tab == entry,
                            onClick = { tab = entry },
                            icon = { Icon(entry.icon, contentDescription = entry.label) },
                            label = { Text(entry.label) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding)) {
            when (tab) {
                Tab.HOME -> HomeScreen(homeVm, onSeeAll = { tab = Tab.LOGBOOK })
                // Active session -> live logger; idle -> start prompt that opens
                // the session wizard. Mirrors the iOS Sessions tab swap.
                Tab.SESSIONS -> SessionsContainerScreen(
                    loggerVm,
                    spotsVm,
                    onStartSession = { wizardLaunch++; showSessionWizard = true },
                )
                // The hunter log with the live spot feed as its body; tapping
                // a spot seeds the quick-entry command bar.
                Tab.HUNTER -> HunterLogScreen(hunterVm, spotsVm)
                Tab.LOGBOOK -> LogbookScreen(logbookVm)
                Tab.MAP -> MapScreen(mapVm)
                // Folds the social graph + activity feed (Friends) and Clubs into
                // one tab, mirroring the iOS Friends tab.
                Tab.FRIENDS -> FriendsContainerScreen(
                    clubsVm,
                    onOpenClub = { openClubId = it.id },
                )
                Tab.MORE -> AccountScreen(
                    accountVm,
                    onOpenBragSheet = { showBragSheet = true },
                    onOpenKeyboardRows = { showKeyboardRows = true },
                    onOpenDebugLog = { showDebugLog = true },
                    onOpenActivations = { showActivations = true },
                    onOpenPropagationCheck = { showPropagationCheck = true },
                    onOpenSatellites = { showSatellites = true },
                    onOpenAmt = { showAmt = true },
                )
            }
        }
    }
}

/** Map a live spot to the planner's on-air station, dropping spots without a
 * usable frequency/band. Feeds the Rust free-frequency suggestion. */
private fun Spot.toActiveStation(): FfiActiveStation? {
    val khz = freqKhz ?: return null
    val bandName = band ?: return null
    return FfiActiveStation(
        callsign = callsign,
        band = bandName,
        mode = mode,
        frequencyMhz = khz / 1000.0,
        timestamp = (epochSeconds ?: 0.0).toLong(),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BrandBar(tab: Tab) {
    TopAppBar(
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Filled.Radio,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(end = 8.dp),
                )
                Text(
                    "Carrier Wave",
                    style = MaterialTheme.typography.titleLarge,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                )
            }
        },
        actions = {
            CountBadge(tab.label)
            Box(Modifier.padding(end = 12.dp))
        },
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
    )
}
