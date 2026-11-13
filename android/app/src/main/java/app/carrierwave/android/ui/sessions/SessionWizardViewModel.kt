package app.carrierwave.android.ui.sessions

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.lifecycle.viewmodel.CreationExtras.Key
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import app.carrierwave.android.CwApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.ContestApi
import uniffi.cw_ffi.FfiActiveStation
import uniffi.cw_ffi.FfiContestDefinition
import uniffi.cw_ffi.FfiContestSummary
import uniffi.cw_ffi.FfiCreateSessionInput
import uniffi.cw_ffi.FfiEquipmentItem
import uniffi.cw_ffi.FfiEquipmentItemFilter
import uniffi.cw_ffi.FfiEquipmentSort
import uniffi.cw_ffi.FfiGearReminder
import uniffi.cw_ffi.FfiLoadout
import uniffi.cw_ffi.FfiParkRollup
import uniffi.cw_ffi.FfiPotaPark
import uniffi.cw_ffi.FfiWizardDefaults
import uniffi.cw_ffi.FfiWizardTotaInput
import uniffi.cw_ffi.FieldStore
import uniffi.cw_ffi.SessionWizardApi

/**
 * Drives the Android session-start wizard. All computation — assembly, defaults,
 * frequency/park suggestions — is delegated to the shared Rust [SessionWizardApi];
 * this holds only UI state and marshals the FFI calls onto [Dispatchers.IO]
 * (store-touching UniFFI calls block, so they must stay off the main thread).
 */
class SessionWizardViewModel(
    private val wizard: SessionWizardApi,
    private val store: FieldStore,
    private val contestApi: ContestApi,
    defaultCallsign: String,
    defaultGrid: String,
) : ViewModel() {

    /** The three iOS wizard variants — Activation shows programs, Contest shows
     * the contest picker, Casual is the bare form. */
    enum class OperationType { ACTIVATION, CASUAL, CONTEST }

    /** Callsign suffix options, resolved to the string Rust joins (`effectiveSuffix`). */
    enum class SuffixKind(val label: String, val resolved: String) {
        NONE("None", ""),
        PORTABLE("/P", "P"),
        MOBILE("/M", "M"),
        MARITIME("/MM", "MM"),
        AERONAUTICAL("/AM", "AM"),
        CUSTOM("Custom", ""),
    }

    data class UiState(
        val operationType: OperationType = OperationType.ACTIVATION,
        val callsign: String = "",
        val grid: String = "",
        val mode: String = "CW",
        val frequency: String = "",
        val power: String = "",
        val programs: Set<String> = emptySet(),
        val contests: List<FfiContestSummary> = emptyList(),
        val selectedContestId: String? = null,
        val contestDefinition: FfiContestDefinition? = null,
        val contestCategory: String? = null,
        val contestPower: String? = null,
        val contestBands: String? = null,
        val parkRef: String = "",
        val sotaRef: String = "",
        val wwffRef: String = "",
        val radio: String = "",
        val antenna: String = "",
        val key: String = "",
        val mic: String = "",
        val radioItemId: String? = null,
        val loadouts: List<FfiLoadout> = emptyList(),
        val selectedLoadoutId: String? = null,
        /** Owned equipment, used to populate the inline gear pickers by category. */
        val inventory: List<FfiEquipmentItem> = emptyList(),
        val notes: String = "",
        // Station / callsign construction.
        val callsignPrefix: String = "",
        val suffix: SuffixKind = SuffixKind.NONE,
        val customSuffix: String = "",
        val isClubStation: Boolean = false,
        val clubCallsign: String = "",
        // People (multi-op + attendees).
        val operators: List<String> = emptyList(),
        val operatorInput: String = "",
        val attendees: String = "",
        // AoA mission reference.
        val missionRef: String = "",
        // TOTA.
        val totaLat: String = "",
        val totaLon: String = "",
        val totaCategory: String? = null,
        val totaPef: String = "",
        val totaWinterOverride: Boolean? = null,
        val totaWithPets: Boolean = false,
        val totaWithKids: Boolean = false,
        val totaWinlink: Boolean = false,
        val totaAprs: Boolean = false,
        val totaVarac: Boolean = false,
        val totaAdaptive: Boolean = false,
        val ruckWeight: String = "",
        // Pack checklist.
        val radioConnector: String? = null,
        val antennaConnector: String? = null,
        val reminders: List<FfiGearReminder> = emptyList(),
        val checkedReminders: Set<String> = emptySet(),
        val prefixHint: String? = null,
        val frequencyHint: String? = null,
        val parkHint: String? = null,
        /** Resolved park record for the current reference (name/location enrichment). */
        val parkDetail: FfiPotaPark? = null,
        /** This operator's activity at the current park (activations / hunter QSOs). */
        val parkRollup: FfiParkRollup? = null,
        // Auto-fill bookkeeping — mirrors the iOS wizard so an auto-suggested
        // value is replaceable but a value the operator typed is never clobbered.
        val autoFilledFrequency: String? = null,
        val frequencyOverridden: Boolean = false,
        val autoFilledPark: String? = null,
        val starting: Boolean = false,
        val started: Boolean = false,
        val error: String? = null,
    ) {
        /** Why the Start button is disabled, or null when the session is ready to
         * launch. Mirrors the iOS `SessionStartSheet` validation so the pinned
         * action can show the same one-line reason. */
        val disabledReason: String?
            get() = when {
                callsign.trim().length < 3 -> "Enter your callsign"
                isClubStation && clubCallsign.isBlank() -> "Enter a club callsign"
                showsPrograms && "pota" in programs && parkRef.isBlank() -> "POTA needs a park reference"
                showsPrograms && "sota" in programs && sotaRef.isBlank() -> "SOTA needs a summit reference"
                showsPrograms && "wwff" in programs && wwffRef.isBlank() -> "WWFF needs a reference"
                showsPrograms && "aoa" in programs && missionRef.isBlank() -> "AoA needs a mission reference"
                showsContest && selectedContestId == null -> "Select a contest"
                else -> null
            }
        val canStart: Boolean get() = disabledReason == null && !starting
        val isCw: Boolean get() = mode == "CW"
        val isPhone: Boolean get() = mode in PHONE_MODES
        val showsPrograms: Boolean get() = operationType == OperationType.ACTIVATION
        val showsContest: Boolean get() = operationType == OperationType.CONTEST
        val showsTota: Boolean get() = showsPrograms && "tota" in programs
        val showsAoa: Boolean get() = showsPrograms && "aoa" in programs
        val powerClasses: List<String>
            get() = contestDefinition?.categories?.firstOrNull { it.id == contestCategory }?.powerClasses.orEmpty()
        val effectiveSuffix: String
            get() = if (suffix == SuffixKind.CUSTOM) customSuffix.trim().uppercase() else suffix.resolved
        /** QRP is derived from wattage (matches the shared `tota_qrp` rule). */
        val totaQrp: Boolean get() = power.toLongOrNull()?.let { it <= 10 } ?: false
    }

    private val _ui = MutableStateFlow(
        UiState(callsign = defaultCallsign, grid = defaultGrid),
    )
    val ui: StateFlow<UiState> = _ui.asStateFlow()

    init {
        prefillFromDefaults()
        loadLoadouts()
        loadInventory()
        loadContests()
        refreshReminders()
    }

    fun setOperationType(type: OperationType) = _ui.update {
        // Programs only apply to Activation; drop them when leaving it.
        it.copy(operationType = type, programs = if (type == OperationType.ACTIVATION) it.programs else emptySet())
    }

    fun selectContest(id: String) = viewModelScope.launch {
        val definition = withContext(Dispatchers.IO) {
            runCatching { contestApi.definition(id) }.getOrNull()
        }
        _ui.update {
            it.copy(
                selectedContestId = id,
                contestDefinition = definition,
                contestCategory = definition?.categories?.firstOrNull()?.id,
                contestPower = null,
                contestBands = definition?.bands?.firstOrNull(),
            )
        }
    }

    fun setContestCategory(id: String) = _ui.update { it.copy(contestCategory = id, contestPower = null) }
    fun setContestPower(value: String) = _ui.update { it.copy(contestPower = value) }
    fun setContestBands(value: String) = _ui.update { it.copy(contestBands = value) }

    // --- Field setters ------------------------------------------------------

    fun setCallsign(value: String) = _ui.update { it.copy(callsign = value) }
    fun setGrid(value: String) = _ui.update { it.copy(grid = value) }
    fun setFrequency(value: String) = _ui.update {
        // A value the operator typed retires the auto-suggestion so we stop
        // re-picking; clearing the field re-arms it.
        it.copy(
            frequency = value,
            frequencyHint = null,
            frequencyOverridden = value.isNotBlank() && value != it.autoFilledFrequency,
            autoFilledFrequency = if (value == it.autoFilledFrequency) it.autoFilledFrequency else null,
        )
    }

    /** Tap a band pill (FT8/FT4) — jumps to the calling frequency for that band. */
    fun setDigitalFrequency(mhz: Double) = _ui.update {
        it.copy(frequency = formatMhz(mhz), frequencyHint = null)
    }
    fun setPower(value: String) = _ui.update { it.copy(power = value) }
    fun setParkRef(value: String) {
        _ui.update { it.copy(parkRef = value, parkHint = null) }
        refreshParkDetails()
    }
    fun setSotaRef(value: String) = _ui.update { it.copy(sotaRef = value) }
    fun setWwffRef(value: String) = _ui.update { it.copy(wwffRef = value) }
    fun setRadio(value: String) = _ui.update { it.copy(radio = value, radioItemId = null, selectedLoadoutId = null) }
    fun setMic(value: String) = _ui.update { it.copy(mic = value) }

    /** Pick a radio from owned inventory — carries the item id so the session
     * links to the equipment record (matches the iOS component picker). */
    fun pickRadio(item: FfiEquipmentItem?) {
        _ui.update {
            it.copy(radio = item?.displayName().orEmpty(), radioItemId = item?.id, selectedLoadoutId = null)
        }
    }

    fun pickAntenna(item: FfiEquipmentItem?) = setAntenna(item?.displayName().orEmpty())
    fun pickKey(item: FfiEquipmentItem?) = setKey(item?.displayName().orEmpty())
    fun pickMic(item: FfiEquipmentItem?) = setMic(item?.displayName().orEmpty())

    fun setAntenna(value: String) {
        _ui.update { it.copy(antenna = value, selectedLoadoutId = null) }
        refreshReminders()
    }

    fun setKey(value: String) {
        _ui.update { it.copy(key = value) }
        refreshReminders()
    }
    fun setNotes(value: String) = _ui.update { it.copy(notes = value) }

    fun setMode(value: String) {
        // Mirror the wizard's mode-gated gear: drop the irrelevant slot's value
        // from view so the UI matches what Rust will keep. Leaving FT8/FT4 for a
        // free-form mode drops the fixed digital dial so the suggestion re-picks.
        _ui.update {
            val leavingDigital = it.mode in DIGITAL_MODES && value !in DIGITAL_MODES
            it.copy(
                mode = value,
                key = if (value == "CW") it.key else "",
                mic = if (value in PHONE_MODES) it.mic else "",
                frequency = if (leavingDigital) "" else it.frequency,
                frequencyOverridden = if (leavingDigital) false else it.frequencyOverridden,
                autoFilledFrequency = if (leavingDigital) null else it.autoFilledFrequency,
            )
        }
        refreshReminders()
    }

    // --- Station / people / AoA / TOTA setters ------------------------------

    fun setCallsignPrefix(value: String) = _ui.update { it.copy(callsignPrefix = value, prefixHint = null) }
    fun setSuffix(kind: SessionWizardViewModel.SuffixKind) = _ui.update { it.copy(suffix = kind) }
    fun setCustomSuffix(value: String) = _ui.update { it.copy(customSuffix = value) }
    fun toggleClubStation() = _ui.update { it.copy(isClubStation = !it.isClubStation) }
    fun setClubCallsign(value: String) = _ui.update { it.copy(clubCallsign = value) }
    fun setOperatorInput(value: String) = _ui.update { it.copy(operatorInput = value) }
    fun removeOperator(call: String) = _ui.update { it.copy(operators = it.operators - call) }
    fun setAttendees(value: String) = _ui.update { it.copy(attendees = value) }
    fun setMissionRef(value: String) = _ui.update { it.copy(missionRef = value) }
    fun setTotaLat(value: String) = _ui.update { it.copy(totaLat = value) }
    fun setTotaLon(value: String) = _ui.update { it.copy(totaLon = value) }
    fun setTotaCategory(value: String) = _ui.update {
        it.copy(totaCategory = if (it.totaCategory == value) null else value)
    }
    fun setTotaPef(value: String) = _ui.update { it.copy(totaPef = value) }
    fun setWinterOverride(value: Boolean?) = _ui.update { it.copy(totaWinterOverride = value) }
    fun setRuckWeight(value: String) = _ui.update { it.copy(ruckWeight = value) }
    fun toggleTotaPets() = _ui.update { it.copy(totaWithPets = !it.totaWithPets) }
    fun toggleTotaKids() = _ui.update { it.copy(totaWithKids = !it.totaWithKids) }
    fun toggleTotaWinlink() = _ui.update { it.copy(totaWinlink = !it.totaWinlink) }
    fun toggleTotaAprs() = _ui.update { it.copy(totaAprs = !it.totaAprs) }
    fun toggleTotaVarac() = _ui.update { it.copy(totaVarac = !it.totaVarac) }
    fun toggleTotaAdaptive() = _ui.update { it.copy(totaAdaptive = !it.totaAdaptive) }

    fun addOperator() = _ui.update {
        val call = it.operatorInput.trim().uppercase()
        if (call.isEmpty() || call in it.operators) {
            it.copy(operatorInput = "")
        } else {
            it.copy(operators = it.operators + call, operatorInput = "")
        }
    }

    /** Effective TOTA winter flag for display — override, else Rust auto-detect. */
    fun totaWinterEffective(): Boolean {
        val state = _ui.value
        return wizard.totaEffectiveWinter(state.totaWinterOverride, state.totaLat.toDoubleOrNull(), nowEpochSeconds())
    }

    /** Suggest the operator's prefix from the current grid (DXCC entity). */
    fun suggestPrefix() = viewModelScope.launch {
        val grid = _ui.value.grid
        if (grid.isBlank()) return@launch
        val entity = withContext(Dispatchers.IO) {
            runCatching { wizard.nearestPrefixForGrid(grid) }.getOrNull()
        }
        if (entity != null) {
            _ui.update { it.copy(prefixHint = "${entity.name} (${entity.prefix})") }
        }
    }

    fun setRadioConnector(value: String?) {
        _ui.update { it.copy(radioConnector = value) }
        refreshReminders()
    }

    fun setAntennaConnector(value: String?) {
        _ui.update { it.copy(antennaConnector = value) }
        refreshReminders()
    }

    fun toggleReminder(id: String) = _ui.update {
        it.copy(checkedReminders = if (id in it.checkedReminders) it.checkedReminders - id else it.checkedReminders + id)
    }

    /** Recompute the pack checklist from the shared Rust engine (pure, fast). */
    private fun refreshReminders() {
        val state = _ui.value
        val list = wizard.packChecklist(
            state.radioConnector,
            state.antennaConnector,
            state.mode,
            state.antenna.isNotBlank(),
            state.key.isNotBlank(),
        )
        val validIds = list.mapTo(HashSet()) { it.id }
        _ui.update { it.copy(reminders = list, checkedReminders = it.checkedReminders intersect validIds) }
    }

    fun toggleProgram(slug: String) = _ui.update {
        val next = it.programs.toMutableSet()
        if (!next.add(slug)) next.remove(slug)
        it.copy(programs = next)
    }

    fun applyLoadout(loadout: FfiLoadout) {
        _ui.update {
            it.copy(
                radio = loadout.radio.orEmpty(),
                antenna = loadout.antenna.orEmpty(),
                key = loadout.key.orEmpty(),
                mic = loadout.mic.orEmpty(),
                radioItemId = loadout.radioItemId,
                selectedLoadoutId = loadout.id,
            )
        }
        refreshReminders()
    }

    fun dismissError() = _ui.update { it.copy(error = null) }

    // --- Suggestions (shared Rust) -----------------------------------------

    /** Ask Rust for a clear frequency, feeding it the current live spots. */
    fun suggestFrequency(stations: List<FfiActiveStation>) = viewModelScope.launch {
        val state = _ui.value
        val band = bandForMhz(parseFreqMhz(state.frequency)) ?: DEFAULT_BAND
        val suggestion = withContext(Dispatchers.IO) {
            wizard.suggestFrequency(band, state.mode, LICENSE, stations, nowEpochSeconds())
        }
        val mhz = suggestion.frequencyMhz
        if (mhz != null) {
            val formatted = formatMhz(mhz)
            _ui.update {
                it.copy(
                    frequency = formatted,
                    frequencyHint = suggestion.reason,
                    autoFilledFrequency = formatted,
                    frequencyOverridden = false,
                )
            }
        } else {
            _ui.update { it.copy(frequencyHint = "No clear frequency found") }
        }
    }

    /** Auto-suggest a working frequency on open / mode change, unless the operator
     * has typed their own or is on a digital mode (which uses band pills). */
    fun autoSuggestFrequencyIfNeeded(stations: List<FfiActiveStation>) {
        val state = _ui.value
        if (state.frequencyOverridden || state.mode in DIGITAL_MODES) return
        if (state.frequency.isNotBlank() && state.frequency != state.autoFilledFrequency) return
        suggestFrequency(stations)
    }

    /** Auto-pick a nearby park on open / when POTA is selected, unless the
     * operator has entered their own reference. */
    fun autoPickParkIfNeeded() {
        val state = _ui.value
        if (!state.showsPrograms || "pota" !in state.programs) return
        val current = state.parkRef.trim()
        if (current.isNotEmpty() && current != state.autoFilledPark) return
        if (state.grid.isBlank()) return
        suggestPark()
    }

    /** Ask Rust for the best nearby park for the current grid (POTA prefill). */
    fun suggestPark() = viewModelScope.launch {
        val grid = _ui.value.grid
        if (grid.isBlank()) return@launch
        val park = withContext(Dispatchers.IO) {
            wizard.suggestPark(grid, PARK_LIMIT, PARK_MAX_KM, PARK_HISTORY)
        }
        if (park != null) {
            _ui.update {
                it.copy(
                    parkRef = park.reference,
                    parkHint = "${park.distanceKm.toInt()} km away",
                    autoFilledPark = park.reference,
                )
            }
            refreshParkDetails()
        } else {
            _ui.update { it.copy(parkHint = "No parks within range") }
        }
    }

    /** Pick a band from the selector — suggests a clear in-band frequency for the
     * current mode (free-form modes; digital modes use the fixed dial instead). */
    fun selectBand(band: String, stations: List<FfiActiveStation>) = viewModelScope.launch {
        val state = _ui.value
        val suggestion = withContext(Dispatchers.IO) {
            wizard.suggestFrequency(band, state.mode, LICENSE, stations, nowEpochSeconds())
        }
        val mhz = suggestion.frequencyMhz
        if (mhz != null) {
            val formatted = formatMhz(mhz)
            _ui.update {
                it.copy(
                    frequency = formatted,
                    frequencyHint = suggestion.reason,
                    autoFilledFrequency = formatted,
                    frequencyOverridden = false,
                )
            }
        } else {
            _ui.update { it.copy(frequencyHint = "No clear frequency on $band") }
        }
    }

    // --- Start --------------------------------------------------------------

    fun start() = viewModelScope.launch {
        if (!_ui.value.canStart) return@launch
        _ui.update { it.copy(starting = true, error = null) }
        val state = _ui.value
        val result = withContext(Dispatchers.IO) {
            runCatching {
                val session = wizard.createSession(state.toCreateInput())
                // Notes aren't part of assembly (iOS appends them post-start too).
                val notes = state.notes.trim()
                if (notes.isNotEmpty()) {
                    store.upsertLoggingSession(session.copy(notes = notes))
                }
                wizard.saveWizardDefaults(state.toDefaults())
            }
        }
        result.fold(
            onSuccess = { _ui.update { it.copy(started = true, starting = false) } },
            onFailure = { err ->
                _ui.update { it.copy(starting = false, error = err.message ?: "Failed to start session") }
            },
        )
    }

    // --- Private ------------------------------------------------------------

    private fun prefillFromDefaults() = viewModelScope.launch {
        val defaults = withContext(Dispatchers.IO) { runCatching { wizard.wizardDefaults() }.getOrNull() }
        val savedPrograms = defaults?.programs.orEmpty()
        _ui.update { current ->
            current.copy(
                mode = defaults?.mode ?: current.mode,
                power = current.power.ifBlank { defaults?.power.orEmpty() },
                grid = current.grid.ifBlank { defaults?.grid.orEmpty() },
                radio = current.radio.ifBlank { defaults?.radio.orEmpty() },
                antenna = current.antenna.ifBlank { defaults?.antenna.orEmpty() },
                key = current.key.ifBlank { defaults?.key.orEmpty() },
                mic = current.mic.ifBlank { defaults?.mic.orEmpty() },
                // Prefer a saved program set; otherwise default to POTA for a new
                // activator (matches iOS, which seeds ["pota"]).
                programs = when {
                    current.programs.isNotEmpty() -> current.programs
                    savedPrograms.isNotEmpty() -> savedPrograms.toSet()
                    else -> setOf("pota")
                },
                parkRef = current.parkRef.ifBlank { defaults?.parkReference.orEmpty() },
            )
        }
        refreshParkDetails()
    }

    /** Resolve the current park reference to its record (name/location) plus this
     * operator's activity rollup (activations / hunter QSOs) for enrichment. */
    private fun refreshParkDetails() = viewModelScope.launch {
        val ref = _ui.value.parkRef.trim().uppercase()
        if (ref.isBlank()) {
            _ui.update { it.copy(parkDetail = null, parkRollup = null) }
            return@launch
        }
        val (park, rollup) = withContext(Dispatchers.IO) {
            val park = runCatching { store.fetchPotaPark(ref) }.getOrNull()
            // Only scan the log once we have a real park (avoids a full rollup
            // per keystroke). Empty query = all parks; match by reference.
            val rollup = if (park != null) {
                runCatching { store.qsoParkRollup("").firstOrNull { it.park.equals(ref, ignoreCase = true) } }.getOrNull()
            } else {
                null
            }
            park to rollup
        }
        // Apply only if the reference hasn't changed while the lookup ran.
        _ui.update { if (it.parkRef.trim().uppercase() == ref) it.copy(parkDetail = park, parkRollup = rollup) else it }
    }

    private fun loadLoadouts() = viewModelScope.launch {
        val loadouts = withContext(Dispatchers.IO) {
            runCatching { store.fetchLoadouts(LOADOUT_LIMIT, 0L) }.getOrDefault(emptyList())
        }
        _ui.update { it.copy(loadouts = loadouts) }
    }

    private fun loadInventory() = viewModelScope.launch {
        val filter = FfiEquipmentItemFilter(
            categoryRawValue = null,
            isRetired = false,
            sort = FfiEquipmentSort.NAME_ASC,
        )
        val items = withContext(Dispatchers.IO) {
            runCatching { store.fetchEquipmentItems(filter, INVENTORY_LIMIT, 0L) }.getOrDefault(emptyList())
        }
        _ui.update { it.copy(inventory = items) }
    }

    private fun loadContests() = viewModelScope.launch {
        val contests = withContext(Dispatchers.IO) {
            runCatching { contestApi.summaries() }.getOrDefault(emptyList())
        }.filter { it.isActive }.sortedBy { it.displayName }
        _ui.update { it.copy(contests = contests) }
    }

    private fun UiState.toCreateInput() = FfiCreateSessionInput(
        baseCallsign = callsign,
        callsignPrefix = callsignPrefix,
        suffix = effectiveSuffix,
        isClubStation = isClubStation,
        clubCallsignInput = clubCallsign,
        mode = mode,
        frequencyMhz = parseFreqMhz(frequency),
        // Programs are an Activation-only concept.
        programs = if (showsPrograms) programs.toList() else emptyList(),
        parkReference = if (showsPrograms) parkRef.ifBlank { null } else null,
        sotaReference = if (showsPrograms) sotaRef.ifBlank { null } else null,
        missionReference = if (showsPrograms) missionRef.ifBlank { null } else null,
        wwffReference = if (showsPrograms) wwffRef.ifBlank { null } else null,
        myGrid = grid.ifBlank { null },
        power = power.toLongOrNull(),
        myRig = radio.ifBlank { null },
        myAntenna = antenna.ifBlank { null },
        selectedKey = key.ifBlank { null },
        selectedMic = mic.ifBlank { null },
        extraEquipment = null,
        attendees = attendees.ifBlank { null },
        isRove = false,
        contestId = if (showsContest) selectedContestId else null,
        contestCategory = if (showsContest) contestCategory else null,
        contestOverlayCategory = null,
        contestPower = if (showsContest) contestPower else null,
        contestBands = if (showsContest) contestBands else null,
        contestOperator = null,
        operatorCallsigns = operators,
        radioItemId = radioItemId,
        tota = if (showsTota) totaInput() else null,
    )

    /** The TOTA payload (`FfiWizardTotaInput`) — direct field copies; QRP is the
     * shared `<= 10 W` rule, winter override maps `true/false/null → 1/0/null`. */
    private fun UiState.totaInput() = FfiWizardTotaInput(
        activationLatitude = totaLat.toDoubleOrNull(),
        activationLongitude = totaLon.toDoubleOrNull(),
        qrpActivation = totaQrp,
        withPets = totaWithPets,
        withKids = totaWithKids,
        winlinkSent = totaWinlink,
        aprsSent = totaAprs,
        varacSent = totaVarac,
        adaptiveSport = totaAdaptive,
        ruckWeightPounds = ruckWeight.toDoubleOrNull(),
        totaCategoryRawValue = totaCategory,
        personalEffortFactor = totaPef.toLongOrNull()?.takeIf { it > 0 },
        winterActivationOverride = totaWinterOverride?.let { if (it) 1L else 0L },
    )

    private fun UiState.toDefaults() = FfiWizardDefaults(
        mode = mode,
        power = power.ifBlank { null },
        grid = grid.ifBlank { null },
        radio = radio.ifBlank { null },
        antenna = antenna.ifBlank { null },
        key = key.ifBlank { null },
        mic = mic.ifBlank { null },
        programs = programs.toList(),
        parkReference = parkRef.ifBlank { null },
        contestId = null,
    )

    companion object {
        val PHONE_MODES = setOf("SSB", "USB", "LSB", "AM", "FM")
        val DIGITAL_MODES = setOf("FT8", "FT4")
        val MODES = listOf("CW", "SSB", "FT8", "FT4", "RTTY", "AM", "FM")
        private const val DEFAULT_BAND = "20m"
        private const val LICENSE = "General"
        private const val LOADOUT_LIMIT = 50L
        private const val INVENTORY_LIMIT = 200L
        private const val PARK_LIMIT = 10u
        private const val PARK_MAX_KM = 16.0
        private const val PARK_HISTORY = 400L

        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                SessionWizardViewModel(
                    app.sessionWizardApi,
                    app.store,
                    app.contestApi,
                    app.userCallsign,
                    app.userHomeGrid,
                )
            }
        }
    }
}

/** The label shown for an owned equipment item — the operator's nickname if set,
 * otherwise the catalog product name. */
internal fun FfiEquipmentItem.displayName(): String =
    nickname?.takeIf { it.isNotBlank() } ?: catalogName

/** Parse a frequency field into MHz. Accepts MHz ("14.062") or kHz ("14062"). */
internal fun parseFreqMhz(text: String): Double? {
    val value = text.trim().replace(",", "").toDoubleOrNull() ?: return null
    if (value <= 0.0) return null
    // Values that look like kHz (>= 1000) are converted to MHz.
    return if (value >= 1000.0) value / 1000.0 else value
}

internal fun formatMhz(mhz: Double): String = "%.3f".format(mhz)

/** Unix seconds now — passed to the planner so it can drop stale spots. */
internal fun nowEpochSeconds(): Long = System.currentTimeMillis() / 1000L

/** Coarse HF band for a frequency (MHz) — enough to scope the frequency pick. */
internal fun bandForMhz(mhz: Double?): String? {
    val f = mhz ?: return null
    return when {
        f in 1.8..2.0 -> "160m"
        f in 3.5..4.0 -> "80m"
        f in 5.3..5.5 -> "60m"
        f in 7.0..7.3 -> "40m"
        f in 10.1..10.15 -> "30m"
        f in 14.0..14.35 -> "20m"
        f in 18.06..18.17 -> "17m"
        f in 21.0..21.45 -> "15m"
        f in 24.89..24.99 -> "12m"
        f in 28.0..29.7 -> "10m"
        f in 50.0..54.0 -> "6m"
        else -> null
    }
}
