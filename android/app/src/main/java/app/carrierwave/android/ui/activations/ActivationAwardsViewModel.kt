package app.carrierwave.android.ui.activations

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import app.carrierwave.android.ui.common.cwMessage
import app.carrierwave.android.util.AppLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.FfiPotaAwards
import uniffi.cw_ffi.FieldStore

/** A tiered POTA award's progress toward its next threshold (null tier label = maxed out). */
data class AwardTierProgress(
    val title: String,
    val current: Long,
    val nextThreshold: Long?,
    val currentTierLabel: String?,
    val nextTierLabel: String?,
) {
    val completed: Boolean get() = nextThreshold == null
    val fraction: Float
        get() = nextThreshold?.let { (current.toFloat() / it.toFloat()).coerceIn(0f, 1f) } ?: 1f
}

data class ActivationAwardsUiState(
    val loaded: Boolean = false,
    val awards: FfiPotaAwards? = null,
    val error: String? = null,
)

/**
 * POTA activator awards, the Android analog of iOS `POTAAwardsView`. Reads the
 * fully-computed [FfiPotaAwards] from the shared Rust store
 * ([FieldStore.potaAwards], empty query = all park QSOs), then derives tiered
 * progress client-side from the same tier ladders iOS's `POTARules` uses. No new
 * Rust surface — the store already ports `POTAAwardsActor`.
 */
class ActivationAwardsViewModel(
    private val store: FieldStore,
) : ViewModel() {

    private val _ui = MutableStateFlow(ActivationAwardsUiState())
    val ui: StateFlow<ActivationAwardsUiState> = _ui.asStateFlow()

    init {
        refresh()
    }

    fun refresh() = viewModelScope.launch {
        val result = withContext(Dispatchers.IO) {
            runCatching { store.potaAwards("") }
        }
        result
            .onSuccess { awards -> _ui.update { it.copy(loaded = true, awards = awards, error = null) } }
            .onFailure { err ->
                AppLog.add(AppLog.Level.ERROR, "pota awards load failed: ${err.cwMessage()}")
                _ui.update { it.copy(loaded = true, error = err.cwMessage()) }
            }
    }

    companion object {
        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                ActivationAwardsViewModel(app.store)
            }
        }
    }
}

/**
 * POTA award tier ladders, ported from iOS `POTARules` (`POTAAwards.swift`).
 * Each ladder is `(label, threshold)` ascending; the DX/repeat-offender/P2P
 * ladders are generated to comfortably exceed the current count so a "next
 * tier" always exists until the fixed ceiling.
 */
object PotaAwardTiers {

    private val uniqueParks = listOf(
        "Bronze" to 10L, "Silver" to 15L, "Gold" to 25L, "Platinum" to 50L, "Sapphire" to 75L,
        "Arizona Agave" to 100L, "Carolina Reaper" to 150L, "Diamond" to 200L, "Emerald" to 300L,
        "Fantasy" to 400L, "Giant Panda" to 500L, "Hornbill" to 750L, "Iron Horse" to 1_000L,
        "Jade" to 1_500L, "Komodo" to 2_000L, "Lemur" to 3_000L, "Mastodon" to 4_000L,
        "Narwhal" to 5_000L, "Osprey" to 7_500L, "Phoenix" to 10_000L, "Quetzal" to 12_500L,
        "Rhino" to 15_000L, "Sasquatch" to 17_500L, "Tasmanian Devil" to 20_000L,
    )

    private val repeatOffenderBase = listOf(
        "Oasis" to 20L, "Homestead" to 30L, "Haven" to 40L, "Sanctuary" to 50L, "Fortress" to 60L,
        "Citadel" to 70L, "Stronghold" to 80L, "Castle" to 90L, "Eagle's Nest" to 100L,
    )

    private val rover = listOf(
        "Warthog" to 5L, "Cheetah" to 10L, "Gazelle" to 15L, "Mustang" to 20L, "Falcon" to 25L,
        "Lion" to 30L,
    )

    fun roverProgress(count: Long) = tierProgress("Rover (parks in one day)", count, rover)

    fun uniqueParksProgress(count: Long): AwardTierProgress {
        val extra = if (count > 20_000L) {
            generateSequence(25_000L) { it + 5_000L }
                .takeWhile { it <= count + 5_000L }
                .map { "$it Parks" to it }
                .toList()
        } else {
            emptyList()
        }
        return tierProgress("Unique Parks Activated", count, uniqueParks + extra)
    }

    fun dxEntitiesProgress(count: Long): AwardTierProgress {
        val tiers = generateSequence(5L) { it + 5L }
            .takeWhile { it <= maxOf(count + 5L, 25L) }
            .map { "$it DX Entities" to it }
            .toList()
        return tierProgress("DX Entities Activated", count, tiers)
    }

    fun repeatOffenderProgress(count: Long): AwardTierProgress {
        val extra = if (count > 100L) {
            generateSequence(120L) { it + 20L }.takeWhile { it <= count + 20L }.map { "$it Activations" to it }.toList()
        } else {
            emptyList()
        }
        return tierProgress("Repeat Offender (one park)", count, repeatOffenderBase + extra)
    }

    fun parkToParkProgress(count: Long): AwardTierProgress {
        val tiers = generateSequence(50L) { it + 50L }
            .takeWhile { it <= maxOf(count + 50L, 250L) }
            .map { "$it P2P QSOs" to it }
            .toList()
        return tierProgress("Park to Park QSOs", count, tiers)
    }

    private fun tierProgress(title: String, count: Long, tiers: List<Pair<String, Long>>): AwardTierProgress {
        val current = tiers.lastOrNull { it.second <= count }
        val next = tiers.firstOrNull { it.second > count }
        return AwardTierProgress(
            title = title,
            current = count,
            nextThreshold = next?.second,
            currentTierLabel = current?.first,
            nextTierLabel = next?.first,
        )
    }
}
