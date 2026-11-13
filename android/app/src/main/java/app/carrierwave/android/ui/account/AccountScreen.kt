package app.carrierwave.android.ui.account

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Forest
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.SatelliteAlt
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.SettingsInputAntenna
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import app.carrierwave.android.CwApp
import app.carrierwave.android.data.UserProfile
import app.carrierwave.android.ui.AmtPractice
import app.carrierwave.android.ui.CwThemeChoice
import app.carrierwave.android.ui.ThemeConfig
import app.carrierwave.android.ui.common.formatTimestamp
import app.carrierwave.android.ui.external.ExternalDataCard
import uniffi.cw_ffi.maidenheadIsValid

/**
 * OAuth sign-in surface. Renders three states off the shared Rust auth client:
 * signed-in, a magic-link verification in flight, and the sign-in form.
 */
@Composable
fun AccountScreen(
    vm: AccountViewModel,
    onOpenBragSheet: () -> Unit = {},
    onOpenKeyboardRows: () -> Unit = {},
    onOpenDebugLog: () -> Unit = {},
    onOpenActivations: () -> Unit = {},
    onOpenPropagationCheck: () -> Unit = {},
    onOpenSatellites: () -> Unit = {},
    onOpenAmt: () -> Unit = {},
) {
    val state by vm.state.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Account", style = MaterialTheme.typography.headlineSmall)

        OperatorProfileCard()

        BragSheetEntryCard(onClick = onOpenBragSheet)

        ActivationsEntryCard(onClick = onOpenActivations)

        PropagationCheckEntryCard(onClick = onOpenPropagationCheck)

        SatellitesEntryCard(onClick = onOpenSatellites)

        KeyboardRowsEntryCard(onClick = onOpenKeyboardRows)

        AmtEntryCard(onClick = onOpenAmt)

        when {
            state.signedIn -> SignedIn(state.accountId, busy = state.busy, onSignOut = vm::signOut)
            state.busy || state.pendingCallsign != null ->
                PendingVerification(state.pendingCallsign, onCancel = vm::cancel)
            else -> SignInForm(busy = state.busy, onSend = vm::sendMagicLink)
        }

        state.message?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary)
        }

        SyncCard(signedIn = state.signedIn)

        AppearanceCard()

        ServerSettingsCard(currentUrl = state.serverUrl, busy = state.busy, onSave = vm::updateServerUrl)

        QrzCredentialsCard()

        ExternalDataCard()

        DebugLogEntryCard(onClick = onOpenDebugLog)
    }
}

/**
 * Carrier Wave Sync — E2E-encrypted logbook sync. Passphrase-escrow enrollment
 * plus a manual "Sync now"; state machine lives in [SyncViewModel].
 */
@Composable
private fun SyncCard(signedIn: Boolean) {
    val vm: SyncViewModel = viewModel(factory = SyncViewModel.factory())
    val state by vm.state.collectAsState()
    var passphrase by rememberSaveable { mutableStateOf("") }

    // Sign-in happens on this same screen; keep the card's gate in step.
    LaunchedEffect(signedIn) { vm.refresh() }

    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Carrier Wave Sync", style = MaterialTheme.typography.titleMedium)
            when {
                !state.signedIn -> Text(
                    "Sign in above to sync your logbook, end-to-end encrypted, between devices.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                !state.enabled -> {
                    Text(
                        "Your log is encrypted with a passphrase before it leaves this " +
                            "device — the server can never read it. Use the same passphrase " +
                            "on every device.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedTextField(
                        value = passphrase,
                        onValueChange = { passphrase = it },
                        label = { Text("Sync passphrase") },
                        singleLine = true,
                        enabled = !state.busy,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        visualTransformation = PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Button(
                        onClick = { vm.enable(passphrase) },
                        enabled = !state.busy && passphrase.length >= 8,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(if (state.busy) "Setting up…" else "Enable sync")
                    }
                    SyncPhaseReadout(state)
                }
                else -> {
                    state.lastSyncAt?.let {
                        Text(
                            "Last sync ${formatTimestamp(it)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Button(
                        onClick = vm::syncNow,
                        enabled = !state.busy,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(if (state.busy) "Syncing…" else "Sync now")
                    }
                    SyncPhaseReadout(state)
                    OutlinedButton(
                        onClick = { vm.disable(); passphrase = "" },
                        enabled = !state.busy,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Forget sync key on this device")
                    }
                    Text(
                        "Removes the encryption key from this device only — your " +
                            "passphrase unlocks sync again anytime. Use this if sync " +
                            "reports a key mismatch after a server or passphrase change.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            state.message?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
            }
            state.error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

/**
 * Theme picker. Selection applies instantly (the whole tree recomposes off
 * [ThemeConfig.choice]) and persists across launches.
 */
@Composable
private fun AppearanceCard() {
    val context = LocalContext.current
    val selected by ThemeConfig.choice.collectAsState()

    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Appearance", style = MaterialTheme.typography.titleMedium)
            CwThemeChoice.entries.forEach { choice ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { ThemeConfig.set(context, choice) }
                        .padding(vertical = 4.dp),
                ) {
                    RadioButton(
                        selected = choice == selected,
                        onClick = { ThemeConfig.set(context, choice) },
                    )
                    Column(Modifier.weight(1f)) {
                        Text(choice.displayName, style = MaterialTheme.typography.bodyLarge)
                        Text(
                            choice.tagline,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    ThemeSwatches(choice)
                }
            }
        }
    }
}

/** Primary / tertiary / background dots so a theme is judgeable before switching. */
@Composable
private fun ThemeSwatches(choice: CwThemeChoice) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        listOf(choice.scheme.primary, choice.scheme.tertiary, choice.scheme.background).forEach { color ->
            Box(
                Modifier
                    .size(16.dp)
                    .clip(CircleShape)
                    .background(color)
                    .border(1.dp, MaterialTheme.colorScheme.outline, CircleShape),
            )
        }
    }
}

/**
 * Live step + elapsed readout while a sync/enroll operation runs — the same
 * phase labels and elapsed-seconds display the iOS sync sheet shows.
 */
@Composable
private fun SyncPhaseReadout(state: SyncUiState) {
    val start = state.operationStart
    if (!state.busy || start == null) return
    var nowMs by remember(start) { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(start) {
        while (true) {
            kotlinx.coroutines.delay(1_000)
            nowMs = System.currentTimeMillis()
        }
    }
    val elapsed = ((nowMs - start) / 1_000).coerceAtLeast(0)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
        Text(
            "${state.phase ?: "Working…"} ${elapsed}s",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * Operator identity — callsign + home grid, replacing the old compile-time
 * constants. Stamped on logged QSOs and used for distance/bearing + map centering.
 */
@Composable
private fun OperatorProfileCard() {
    val app = LocalContext.current.applicationContext as CwApp
    var callsign by rememberSaveable { mutableStateOf(app.userCallsign) }
    var grid by rememberSaveable { mutableStateOf(app.userHomeGrid) }
    var saved by remember { mutableStateOf(false) }

    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Operator profile", style = MaterialTheme.typography.titleMedium)
            if (app.userCallsign.isBlank()) {
                Text(
                    "Set your callsign — it's stamped on every QSO you log.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            OutlinedTextField(
                value = callsign,
                onValueChange = { callsign = it; saved = false },
                label = { Text("Callsign") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = grid,
                onValueChange = { grid = it; saved = false },
                label = { Text("Home grid (e.g. CM87)") },
                singleLine = true,
                isError = grid.isNotBlank() && !maidenheadIsValid(UserProfile.normalizeGrid(grid)),
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = {
                    app.updateProfile(callsign, grid)
                    callsign = app.userCallsign
                    grid = app.userHomeGrid
                    saved = true
                },
                enabled = callsign.isNotBlank() &&
                    (callsign != app.userCallsign || grid != app.userHomeGrid),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Save profile")
            }
            if (saved) {
                Text(
                    "Saved.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

/** Entry point into the Brag Sheet — the stats dashboard driven by the
 * shared Rust `BragSheetApi`. Lives on the More/Account tab, matching where
 * the other feature surfaces (sync, external data) are launched from. */
@Composable
private fun BragSheetEntryCard(onClick: () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.EmojiEvents, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Column {
                    Text("Brag Sheet", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Your best stats — weekly, monthly, all-time",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Entry point into the POTA activation browser (map port Phase D) — the
 * activation list + per-activation detail (stats, map, QSO timeline). */
@Composable
private fun ActivationsEntryCard(onClick: () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.Forest, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Column {
                    Text("POTA Activations", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Your park activations — stats, map, and QSO timeline",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Entry point into the Satellites feature — live QTH-centered sky chart,
 * pass prediction, favorites, and (coming) alerts + quick logging, all on
 * the shared Rust `SatelliteApi`. */
@Composable
private fun SatellitesEntryCard(onClick: () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.SatelliteAlt, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Column {
                    Text("Satellites", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Live sky chart, passes, and favorites",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
        }
    }
}

/** Entry point into the Propagation Check (map port Phase D) — watches
 * RBN/PSK Reporter while the operator CQs, showing live spots and a map +
 * azimuthal view driven by the shared Rust `PropagationApi`. */
@Composable
private fun PropagationCheckEntryCard(onClick: () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.SettingsInputAntenna, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Column {
                    Text("Propagation Check", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Watch RBN and PSK Reporter while you CQ — map, azimuthal, and band stats",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Entry point into Another Morse Trainer — connect the user's AMT account to
 * show the Morse practice streak and practice days on Home. */
@Composable
private fun AmtEntryCard(onClick: () -> Unit) {
    val connected = (LocalContext.current.applicationContext as CwApp).amtApi.hasSession()
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.School, contentDescription = null, tint = AmtPractice)
                Column {
                    Text("Another Morse Trainer", style = MaterialTheme.typography.titleMedium)
                    Text(
                        if (connected) "Connected — Morse practice streak on Home" else "Show your Morse practice streak",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Entry point into the Keyboard Rows settings — the logger accessory rows
 * (numbers / prefix hot keys / commands) configuration (CAR-290). */
@Composable
private fun KeyboardRowsEntryCard(onClick: () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.Keyboard, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Column {
                    Text("Keyboard Rows", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Logger accessory rows — numbers, prefix keys, commands",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Entry point into the Debug Log — an in-app diagnostics sink, mirroring
 * iOS's in-app log surfaces since users can't attach a debugger. */
@Composable
private fun DebugLogEntryCard(onClick: () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.BugReport, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Column {
                    Text("Debug Log", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "App diagnostics — copy or clear",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun QrzCredentialsCard() {
    val app = LocalContext.current.applicationContext as CwApp
    var hasCreds by remember { mutableStateOf(app.qrzApi.hasCredentials()) }
    var username by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }

    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("QRZ callbook", style = MaterialTheme.typography.titleMedium)
            Text(
                if (hasCreds) {
                    "QRZ credentials are saved. Spots show operator names from QRZ."
                } else {
                    "Add your QRZ XML-subscription login to enrich spots with operator names."
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (hasCreds) {
                OutlinedButton(
                    onClick = {
                        app.qrzApi.clearCredentials()
                        hasCreds = false
                        username = ""
                        password = ""
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Remove QRZ credentials")
                }
            } else {
                OutlinedTextField(
                    value = username,
                    onValueChange = { username = it },
                    label = { Text("QRZ username") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("QRZ password") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    onClick = {
                        app.qrzApi.setCredentials(username.trim(), password)
                        hasCreds = true
                    },
                    enabled = username.isNotBlank() && password.isNotBlank(),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Save QRZ login")
                }
            }
        }
    }
}

@Composable
private fun ServerSettingsCard(currentUrl: String, busy: Boolean, onSave: (String) -> Unit) {
    var url by rememberSaveable(currentUrl) { mutableStateOf(currentUrl) }

    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Activities server", style = MaterialTheme.typography.titleMedium)
            Text(
                "The server used for clubs and sign-in. Change this to point at a staging or local dev server.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = url,
                onValueChange = { url = it },
                label = { Text("Server URL") },
                singleLine = true,
                enabled = !busy,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = { onSave(url) },
                enabled = !busy && url.isNotBlank() && url != currentUrl,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Save server")
            }
        }
    }
}

@Composable
private fun SignedIn(accountId: String?, busy: Boolean, onSignOut: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Signed in", style = MaterialTheme.typography.titleMedium)
            Text(
                "Account ${accountId ?: "—"}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    OutlinedButton(onClick = onSignOut, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
        Text("Sign out")
    }
}

@Composable
private fun PendingVerification(callsign: String?, onCancel: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                Spacer(Modifier.size(12.dp))
                Text(
                    "Waiting for ${callsign ?: "the link"}…",
                    style = MaterialTheme.typography.titleMedium,
                )
            }
            Text(
                "Open the magic link we emailed you. This screen finishes automatically.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    OutlinedButton(onClick = onCancel, modifier = Modifier.fillMaxWidth()) {
        Text("Cancel")
    }
}

@Composable
private fun SignInForm(busy: Boolean, onSend: (String, String?) -> Unit) {
    var callsign by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }

    Text(
        "Sign in with your callsign. We'll email a magic link to verify it.",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    OutlinedTextField(
        value = callsign,
        onValueChange = { callsign = it },
        label = { Text("Callsign") },
        singleLine = true,
        enabled = !busy,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
        modifier = Modifier.fillMaxWidth(),
    )
    OutlinedTextField(
        value = email,
        onValueChange = { email = it },
        label = { Text("Email (optional)") },
        singleLine = true,
        enabled = !busy,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(4.dp))
    Button(
        onClick = { onSend(callsign, email) },
        enabled = !busy && callsign.isNotBlank(),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text("Send magic link")
    }
}
