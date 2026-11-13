package app.carrierwave.android.ui.sessions

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Forest
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Park
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Piano
import androidx.compose.material.icons.filled.Radio
import androidx.compose.material.icons.filled.SettingsInputAntenna
import androidx.compose.material.icons.filled.Signpost
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.Instant
import java.time.ZoneId
import uniffi.cw_ffi.FfiActiveStation
import uniffi.cw_ffi.FfiEquipmentItem
import uniffi.cw_ffi.FfiParkRollup

/**
 * The Android session-start wizard — a single scrolling form styled to mirror the
 * iOS `SessionStartSheet`: icon-led section headers, an operator "hero" row, a
 * segmented mode picker with FT8/FT4 band pills, program chips, inline gear
 * pickers backed by owned inventory, a "More Options" disclosure for the
 * secondary sections, and a pinned Start action carrying the disabled reason.
 *
 * Every computed value comes from the shared Rust [SessionWizardViewModel];
 * [stationsProvider] supplies the current live spots for the free-frequency
 * planner when the operator taps "Suggest".
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun SessionWizardScreen(
    vm: SessionWizardViewModel,
    stationsProvider: () -> List<FfiActiveStation>,
    onDismiss: () -> Unit,
) {
    val ui by vm.ui.collectAsStateWithLifecycle()

    LaunchedEffect(ui.started) {
        if (ui.started) onDismiss()
    }

    // Pre-populate the wizard the way iOS does on open: suggest a working
    // frequency (re-runs on mode change) and pick a nearby park once POTA is
    // selected and a grid is known. Both no-op if the operator has typed a value.
    LaunchedEffect(ui.mode) { vm.autoSuggestFrequencyIfNeeded(stationsProvider()) }
    LaunchedEffect(ui.programs, ui.grid) { vm.autoPickParkIfNeeded() }

    val startLabel = when (ui.operationType) {
        SessionWizardViewModel.OperationType.ACTIVATION -> "Start Activation"
        SessionWizardViewModel.OperationType.CONTEST -> "Start Contest"
        SessionWizardViewModel.OperationType.CASUAL -> "Start Session"
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(navTitle(ui.operationType)) },
                navigationIcon = {
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Filled.Close, contentDescription = "Cancel")
                    }
                },
            )
        },
        bottomBar = { StartBar(ui, startLabel, vm::start) },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            OperationTypePicker(ui, vm)
            OperatorSection(ui, vm)
            RadioSection(ui, vm, stationsProvider)
            if (ui.showsPrograms) ProgramsSection(ui, vm)
            if (ui.showsTota) TotaSection(ui, vm)
            if (ui.showsContest) ContestSection(ui, vm)
            GearSection(ui, vm)
            MoreOptions {
                StationSection(ui, vm)
                PeopleSection(ui, vm)
                PackChecklistSection(ui, vm)
                NotesSection(ui, vm)
            }

            ui.error?.let { message ->
                Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

private fun navTitle(type: SessionWizardViewModel.OperationType): String = when (type) {
    SessionWizardViewModel.OperationType.ACTIVATION -> "Activate"
    SessionWizardViewModel.OperationType.CONTEST -> "Contest"
    SessionWizardViewModel.OperationType.CASUAL -> "Casual Session"
}

// --- Shared chrome ---------------------------------------------------------

/** A card section with an iOS-style icon-led header (tinted icon + title). */
@Composable
private fun WizardSection(title: String, icon: ImageVector, content: @Composable () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.width(20.dp),
                )
                Text(title, style = MaterialTheme.typography.titleSmall)
            }
            content()
        }
    }
}

/** The pinned bottom action: disabled reason line + full-width Start button. */
@Composable
private fun StartBar(ui: SessionWizardViewModel.UiState, label: String, onStart: () -> Unit) {
    Surface(tonalElevation = 3.dp, color = MaterialTheme.colorScheme.surface) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            ui.disabledReason?.let { reason ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(
                        Icons.Filled.Info,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.secondary,
                        modifier = Modifier.width(18.dp),
                    )
                    Text(reason, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.secondary)
                }
            }
            Button(
                onClick = onStart,
                enabled = ui.canStart,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (ui.starting) {
                    CircularProgressIndicator(Modifier.padding(end = 8.dp), strokeWidth = 2.dp)
                }
                Text(if (ui.starting) "Starting…" else label)
            }
        }
    }
}

/** A labelled row of single-select chips (value to display label). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChipRow(
    label: String,
    options: List<Pair<String, String>>,
    selected: String?,
    onSelect: (String) -> Unit,
) {
    Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.secondary)
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { (value, display) ->
            FilterChip(
                selected = selected == value,
                onClick = { onSelect(value) },
                label = { Text(display) },
            )
        }
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onToggle: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Switch(checked = checked, onCheckedChange = { onToggle() })
    }
}

/** Hint text shown under a suggestion field. */
@Composable
private fun Hint(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.secondary)
}

// --- Operation type + operator ---------------------------------------------

@Composable
private fun OperationTypePicker(ui: SessionWizardViewModel.UiState, vm: SessionWizardViewModel) {
    val types = SessionWizardViewModel.OperationType.entries
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        types.forEachIndexed { index, type ->
            SegmentedButton(
                selected = ui.operationType == type,
                onClick = { vm.setOperationType(type) },
                shape = SegmentedButtonDefaults.itemShape(index = index, count = types.size),
                label = { Text(type.name.lowercase().replaceFirstChar { it.uppercase() }) },
            )
        }
    }
}

@Composable
private fun OperatorSection(ui: SessionWizardViewModel.UiState, vm: SessionWizardViewModel) {
    WizardSection("Operator", Icons.Filled.Person) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top,
        ) {
            OutlinedTextField(
                value = ui.callsign,
                onValueChange = vm::setCallsign,
                label = { Text("Callsign") },
                singleLine = true,
                isError = ui.callsign.isBlank(),
                textStyle = TextStyle(
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                    fontSize = 22.sp,
                ),
                modifier = Modifier.weight(1f),
            )
            OutlinedTextField(
                value = ui.grid,
                onValueChange = vm::setGrid,
                label = { Text("Grid") },
                singleLine = true,
                textStyle = TextStyle(fontFamily = FontFamily.Monospace),
                modifier = Modifier.width(120.dp),
            )
        }
    }
}

// --- Radio -----------------------------------------------------------------

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RadioSection(
    ui: SessionWizardViewModel.UiState,
    vm: SessionWizardViewModel,
    stationsProvider: () -> List<FfiActiveStation>,
) {
    WizardSection("Radio", Icons.Filled.Radio) {
        // Mode picker — segmented control mirroring the iOS mode selector.
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            SessionWizardViewModel.MODES.forEachIndexed { index, mode ->
                SegmentedButton(
                    selected = ui.mode == mode,
                    onClick = { vm.setMode(mode) },
                    shape = SegmentedButtonDefaults.itemShape(index = index, count = SessionWizardViewModel.MODES.size),
                    label = { Text(mode, style = MaterialTheme.typography.labelSmall) },
                )
            }
        }
        if (ui.mode in DIGITAL_MODES) {
            // Digital modes tune to fixed dials — band pills, not the scope.
            BandSelector(ui, vm, stationsProvider)
            parseFreqMhz(ui.frequency)?.let { mhz ->
                Text(
                    "${formatMhz(mhz)} MHz",
                    style = MaterialTheme.typography.titleMedium,
                    fontFamily = FontFamily.Monospace,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            ui.frequencyHint?.let { Hint(it) }
        } else {
            // Free-form modes get the interactive scroll-to-tune scope (shared
            // band-plan logic lives in Rust `cw_domain::frequency_scope`).
            val stations = remember { stationsProvider() }
            FrequencyScopeField(
                frequency = ui.frequency,
                onFrequency = vm::setFrequency,
                mode = ui.mode,
                stations = stations,
                determining = false,
            )
        }
    }
}

/**
 * Band selector — a row of band chips. On a digital mode a chip jumps to the
 * fixed FT8/FT4 dial; on a free-form mode it asks the planner for a clear
 * frequency in that band. The chip for the current frequency's band is selected.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BandSelector(
    ui: SessionWizardViewModel.UiState,
    vm: SessionWizardViewModel,
    stationsProvider: () -> List<FfiActiveStation>,
) {
    val digital = ui.mode in DIGITAL_MODES
    val selectedBand = bandForMhz(parseFreqMhz(ui.frequency))
    Text("Band", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.secondary)
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        HF_BANDS.forEach { band ->
            if (digital) {
                val dial = digitalDialMhz(ui.mode, band) ?: return@forEach
                FilterChip(
                    selected = selectedBand == band,
                    onClick = { vm.setDigitalFrequency(dial) },
                    label = { Text(band) },
                )
            } else {
                FilterChip(
                    selected = selectedBand == band,
                    onClick = { vm.selectBand(band, stationsProvider()) },
                    label = { Text(band) },
                )
            }
        }
    }
}

// --- Programs --------------------------------------------------------------

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProgramsSection(ui: SessionWizardViewModel.UiState, vm: SessionWizardViewModel) {
    WizardSection("Programs", Icons.Filled.Signpost) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PROGRAMS.forEach { (slug, label, icon) ->
                FilterChip(
                    selected = slug in ui.programs,
                    onClick = { vm.toggleProgram(slug) },
                    label = { Text(label) },
                    leadingIcon = { Icon(icon, contentDescription = null, modifier = Modifier.width(18.dp)) },
                )
            }
        }
        if ("pota" in ui.programs) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = ui.parkRef,
                    onValueChange = vm::setParkRef,
                    label = { Text("Park (US-1234)") },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                OutlinedButton(onClick = vm::suggestPark) { Text("Nearby") }
            }
            ui.parkDetail?.let { park ->
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(park.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                    val location = listOfNotNull(
                        park.locationDesc.takeIf { it.isNotBlank() },
                        park.grid?.takeIf { it.isNotBlank() },
                    ).joinToString(" · ")
                    if (location.isNotBlank()) {
                        Text(
                            location,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.secondary,
                        )
                    }
                    Text(
                        parkStats(ui.parkRollup),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            ui.parkHint?.let { Hint(it) }
        }
        if ("sota" in ui.programs) {
            OutlinedTextField(
                value = ui.sotaRef,
                onValueChange = vm::setSotaRef,
                label = { Text("Summit (W6/CT-225)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if ("wwff" in ui.programs) {
            OutlinedTextField(
                value = ui.wwffRef,
                onValueChange = vm::setWwffRef,
                label = { Text("WWFF (KFF-1234)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (ui.showsAoa) {
            OutlinedTextField(
                value = ui.missionRef,
                onValueChange = vm::setMissionRef,
                label = { Text("AoA mission") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

// --- TOTA ------------------------------------------------------------------

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun TotaSection(ui: SessionWizardViewModel.UiState, vm: SessionWizardViewModel) {
    WizardSection("TOTA", Icons.Filled.GridView) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = ui.totaLat,
                onValueChange = vm::setTotaLat,
                label = { Text("Latitude") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                modifier = Modifier.weight(1f),
            )
            OutlinedTextField(
                value = ui.totaLon,
                onValueChange = vm::setTotaLon,
                label = { Text("Longitude") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                modifier = Modifier.weight(1f),
            )
        }
        ChipRow(
            "Category",
            listOf("standard" to "Standard", "mobile" to "Mobile"),
            ui.totaCategory,
            vm::setTotaCategory,
        )
        OutlinedTextField(
            value = ui.totaPef,
            onValueChange = vm::setTotaPef,
            label = { Text("Personal Effort Factor (1–10)") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = ui.ruckWeight,
            onValueChange = vm::setRuckWeight,
            label = { Text("Ruck weight (lb)") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.fillMaxWidth(),
        )
        // QRP + winter are derived by the shared Rust rules (display only).
        Text(
            "QRP: ${if (ui.totaQrp) "yes (≤10 W)" else "no"} · Winter: ${if (vm.totaWinterEffective()) "yes" else "no"}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.secondary,
        )
        ChipRow(
            "Winter override",
            listOf("auto" to "Auto", "yes" to "Winter", "no" to "Not winter"),
            when (ui.totaWinterOverride) { null -> "auto"; true -> "yes"; false -> "no" },
        ) { choice -> vm.setWinterOverride(when (choice) { "yes" -> true; "no" -> false; else -> null }) }
        ToggleRow("Pets", ui.totaWithPets, vm::toggleTotaPets)
        ToggleRow("Kids", ui.totaWithKids, vm::toggleTotaKids)
        ToggleRow("Winlink sent", ui.totaWinlink, vm::toggleTotaWinlink)
        ToggleRow("APRS sent", ui.totaAprs, vm::toggleTotaAprs)
        ToggleRow("VarAC sent", ui.totaVarac, vm::toggleTotaVarac)
        ToggleRow("Adaptive sport", ui.totaAdaptive, vm::toggleTotaAdaptive)
    }
}

// --- Contest ---------------------------------------------------------------

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ContestSection(ui: SessionWizardViewModel.UiState, vm: SessionWizardViewModel) {
    WizardSection("Contest", Icons.Filled.EmojiEvents) {
        if (ui.contests.isEmpty()) {
            Text(
                "No contest definitions cached. Sync contests from More → External Data.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.secondary,
            )
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ui.contests.forEach { contest ->
                FilterChip(
                    selected = ui.selectedContestId == contest.id,
                    onClick = { vm.selectContest(contest.id) },
                    label = { Text(contest.displayName) },
                )
            }
        }
        val definition = ui.contestDefinition
        if (definition != null) {
            ChipRow("Category", definition.categories.map { it.id to it.label }, ui.contestCategory) {
                vm.setContestCategory(it)
            }
            if (ui.powerClasses.isNotEmpty()) {
                ChipRow("Power", ui.powerClasses.map { it to it }, ui.contestPower, vm::setContestPower)
            }
            if (definition.bands.isNotEmpty()) {
                ChipRow("Band", (listOf("ALL") + definition.bands).map { it to it }, ui.contestBands) {
                    vm.setContestBands(it)
                }
            }
        }
    }
}

// --- Gear ------------------------------------------------------------------

@Composable
private fun GearSection(ui: SessionWizardViewModel.UiState, vm: SessionWizardViewModel) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    WizardSection("Gear", Icons.Filled.Build) {
        LoadoutSelector(ui, vm)
        if (expanded) {
            GearSlotField(
                label = "Radio",
                icon = Icons.Filled.Radio,
                value = ui.radio,
                options = ui.inventory.forCategory("radio"),
                onType = vm::setRadio,
                onPick = vm::pickRadio,
                onClear = { vm.pickRadio(null) },
            )
            GearSlotField(
                label = "Antenna",
                icon = Icons.Filled.SettingsInputAntenna,
                value = ui.antenna,
                options = ui.inventory.forCategory("antenna"),
                onType = vm::setAntenna,
                onPick = vm::pickAntenna,
                onClear = { vm.pickAntenna(null) },
            )
            if (ui.isCw) {
                GearSlotField(
                    label = "Key",
                    icon = Icons.Filled.Piano,
                    value = ui.key,
                    options = ui.inventory.forCategory("key"),
                    onType = vm::setKey,
                    onPick = vm::pickKey,
                    onClear = { vm.pickKey(null) },
                )
            }
            if (ui.isPhone) {
                GearSlotField(
                    label = "Mic",
                    icon = Icons.Filled.Mic,
                    value = ui.mic,
                    options = ui.inventory.forCategory("microphone"),
                    onType = vm::setMic,
                    onPick = vm::pickMic,
                    onClear = { vm.pickMic(null) },
                )
            }
            GearDisclosureRow("Hide items", Icons.Filled.ExpandLess) { expanded = false }
        } else {
            GearDisclosureRow(gearSummary(ui), Icons.Filled.ExpandMore) { expanded = true }
        }
        OutlinedTextField(
            value = ui.power,
            onValueChange = vm::setPower,
            label = { Text("Power (W)") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** The four equipment slot names in order, quiet-joined (matches iOS gearNames). */
private fun gearSummary(ui: SessionWizardViewModel.UiState): String {
    val parts = listOf(ui.radio, ui.antenna, ui.key, ui.mic).filter { it.isNotBlank() }
    return if (parts.isEmpty()) "No gear selected" else parts.joinToString(" · ")
}

/**
 * The loadout pull-down — the primary gear control. Shows the active loadout,
 * or "Custom" once gear is edited, or "No loadout". Picking one applies its
 * gear. When nothing is saved it degrades to a read-only "No loadout" field.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LoadoutSelector(ui: SessionWizardViewModel.UiState, vm: SessionWizardViewModel) {
    val selected = ui.loadouts.firstOrNull { it.id == ui.selectedLoadoutId }
    val hasGear = ui.radio.isNotBlank() || ui.antenna.isNotBlank() || ui.key.isNotBlank() || ui.mic.isNotBlank()
    val title = selected?.name ?: if (hasGear) "Custom" else "No loadout"
    if (ui.loadouts.isEmpty()) {
        OutlinedTextField(
            value = title,
            onValueChange = {},
            readOnly = true,
            enabled = false,
            label = { Text("Loadout") },
            modifier = Modifier.fillMaxWidth(),
        )
        return
    }
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = title,
            onValueChange = {},
            readOnly = true,
            label = { Text("Loadout") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                .fillMaxWidth(),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            ui.loadouts.forEach { loadout ->
                DropdownMenuItem(
                    text = { Text(loadout.name) },
                    onClick = {
                        vm.applyLoadout(loadout)
                        expanded = false
                    },
                    trailingIcon = if (loadout.id == ui.selectedLoadoutId) {
                        { Icon(Icons.Filled.Check, contentDescription = null) }
                    } else {
                        null
                    },
                )
            }
        }
    }
}

/** A tappable summary/collapse row with a trailing chevron. */
@Composable
private fun GearDisclosureRow(text: String, icon: ImageVector, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.secondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
    }
}

/**
 * An editable gear slot: type a custom value or pick one of the operator's owned
 * items from the dropdown. Mirrors the iOS inline component menu.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GearSlotField(
    label: String,
    icon: ImageVector,
    value: String,
    options: List<FfiEquipmentItem>,
    onType: (String) -> Unit,
    onPick: (FfiEquipmentItem) -> Unit,
    onClear: () -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = value,
            onValueChange = onType,
            label = { Text(label) },
            singleLine = true,
            leadingIcon = { Icon(icon, contentDescription = null) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .menuAnchor(MenuAnchorType.PrimaryEditable)
                .fillMaxWidth(),
        )
        if (options.isNotEmpty() || value.isNotBlank()) {
            ExposedDropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false },
            ) {
                if (value.isNotBlank()) {
                    DropdownMenuItem(
                        text = { Text("None") },
                        onClick = {
                            onClear()
                            expanded = false
                        },
                    )
                }
                options.forEach { item ->
                    DropdownMenuItem(
                        text = { Text(item.displayName()) },
                        onClick = {
                            onPick(item)
                            expanded = false
                        },
                    )
                }
            }
        }
    }
}

// --- More Options (secondary sections) -------------------------------------

@Composable
private fun MoreOptions(content: @Composable () -> Unit) {
    // `remember` (not rememberSaveable) so the wizard always opens collapsed.
    var expanded by remember { mutableStateOf(false) }
    Card(
        onClick = { expanded = !expanded },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(
                Icons.Filled.MoreHoriz,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.width(20.dp),
            )
            Column(Modifier.weight(1f)) {
                Text("More Options", style = MaterialTheme.typography.titleSmall)
                Text(
                    "Station · People · Pack Checklist · Notes",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.secondary,
                )
            }
            Icon(
                if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.secondary,
            )
        }
    }
    AnimatedVisibility(visible = expanded) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            content()
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StationSection(ui: SessionWizardViewModel.UiState, vm: SessionWizardViewModel) {
    WizardSection("Station", Icons.Filled.Radio) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Club station", Modifier.weight(1f))
            Switch(checked = ui.isClubStation, onCheckedChange = { vm.toggleClubStation() })
        }
        if (ui.isClubStation) {
            OutlinedTextField(
                value = ui.clubCallsign,
                onValueChange = vm::setClubCallsign,
                label = { Text("Club callsign") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = ui.callsignPrefix,
                onValueChange = vm::setCallsignPrefix,
                label = { Text("Prefix") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            OutlinedButton(onClick = vm::suggestPrefix) { Text("From grid") }
        }
        ui.prefixHint?.let { Hint(it) }
        ChipRow(
            "Suffix",
            SessionWizardViewModel.SuffixKind.entries.map { it.name to it.label },
            ui.suffix.name,
        ) { name -> vm.setSuffix(SessionWizardViewModel.SuffixKind.valueOf(name)) }
        if (ui.suffix == SessionWizardViewModel.SuffixKind.CUSTOM) {
            OutlinedTextField(
                value = ui.customSuffix,
                onValueChange = vm::setCustomSuffix,
                label = { Text("Custom suffix") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun PeopleSection(ui: SessionWizardViewModel.UiState, vm: SessionWizardViewModel) {
    WizardSection("People", Icons.Filled.Groups) {
        if (ui.operators.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ui.operators.forEach { call ->
                    InputChip(
                        selected = false,
                        onClick = { vm.removeOperator(call) },
                        label = { Text(call) },
                        trailingIcon = { Icon(Icons.Filled.Close, contentDescription = "Remove $call") },
                    )
                }
            }
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = ui.operatorInput,
                onValueChange = vm::setOperatorInput,
                label = { Text("Add operator") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            OutlinedButton(onClick = vm::addOperator) { Text("Add") }
        }
        OutlinedTextField(
            value = ui.attendees,
            onValueChange = vm::setAttendees,
            label = { Text("Attendees") },
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PackChecklistSection(ui: SessionWizardViewModel.UiState, vm: SessionWizardViewModel) {
    val checkedCount = ui.checkedReminders.size
    val title = "Pack Checklist" + if (ui.reminders.isNotEmpty()) " ($checkedCount/${ui.reminders.size})" else ""
    WizardSection(title, Icons.Filled.Checklist) {
        ChipRow("Radio connector", connectorOptions(), ui.radioConnector, vm::setRadioConnector)
        ChipRow("Antenna connector", connectorOptions(), ui.antennaConnector, vm::setAntennaConnector)
        ui.reminders.forEach { reminder ->
            val checked = reminder.id in ui.checkedReminders
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Checkbox(checked = checked, onCheckedChange = { vm.toggleReminder(reminder.id) })
                Text(reminder.text, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
private fun NotesSection(ui: SessionWizardViewModel.UiState, vm: SessionWizardViewModel) {
    WizardSection("Notes", Icons.Filled.Description) {
        OutlinedTextField(
            value = ui.notes,
            onValueChange = vm::setNotes,
            label = { Text("Session notes") },
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

// --- Static tables ---------------------------------------------------------

private val PROGRAMS: List<Triple<String, String, ImageVector>> = listOf(
    Triple("pota", "POTA", Icons.Filled.Park),
    Triple("sota", "SOTA", Icons.Filled.Terrain),
    Triple("wwff", "WWFF", Icons.Filled.Forest),
    Triple("aoa", "AoA", Icons.Filled.Visibility),
    Triple("tota", "TOTA", Icons.Filled.GridView),
)

/** Connector chip options: (value, label). */
private fun connectorOptions(): List<Pair<String, String>> =
    listOf("BNC" to "BNC", "SO-239" to "SO-239", "SMA" to "SMA", "N-Type" to "N-Type")

/** Owned inventory filtered to one gear category (matches iOS category slots). */
private fun List<FfiEquipmentItem>.forCategory(category: String): List<FfiEquipmentItem> =
    filter { it.categoryRawValue == category }

/** One-line park activity summary from the operator's own log. */
private fun parkStats(rollup: FfiParkRollup?): String {
    if (rollup == null || (rollup.activationDays == 0L && rollup.huntQsos == 0L)) {
        return "New park for you — not yet worked"
    }
    val parts = buildList {
        if (rollup.activationDays > 0) add("${rollup.activationDays} activation days")
        if (rollup.huntQsos > 0) add("${rollup.huntQsos} hunter QSOs")
        if (rollup.lastWorked > 0) add("last ${formatEpochDay(rollup.lastWorked)}")
    }
    return parts.joinToString(" · ")
}

private fun formatEpochDay(epochSeconds: Long): String =
    Instant.ofEpochSecond(epochSeconds).atZone(ZoneId.systemDefault()).toLocalDate().toString()

private val DIGITAL_MODES = setOf("FT8", "FT4")

private val HF_BANDS = listOf("160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m")

/** The calling frequency (MHz) for a digital mode on a given band, or null when
 * that mode has no standard allocation there. Mirrors the iOS band-pill map. */
private fun digitalDialMhz(mode: String, band: String): Double? = when (mode) {
    "FT8" -> when (band) {
        "160m" -> 1.840
        "80m" -> 3.573
        "60m" -> 5.357
        "40m" -> 7.074
        "30m" -> 10.136
        "20m" -> 14.074
        "17m" -> 18.100
        "15m" -> 21.074
        "12m" -> 24.915
        "10m" -> 28.074
        "6m" -> 50.313
        else -> null
    }
    "FT4" -> when (band) {
        "80m" -> 3.575
        "40m" -> 7.0475
        "30m" -> 10.140
        "20m" -> 14.080
        "17m" -> 18.104
        "15m" -> 21.140
        "12m" -> 24.919
        "10m" -> 28.180
        "6m" -> 50.318
        else -> null
    }
    else -> null
}
