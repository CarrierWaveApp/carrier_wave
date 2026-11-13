package app.carrierwave.android.ui.clubs

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.carrierwave.android.util.AppLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.AuthApi
import uniffi.cw_ffi.ClubsApi
import uniffi.cw_ffi.FfiCallsignLocation
import uniffi.cw_ffi.FfiClubActivityItem
import uniffi.cw_ffi.FfiClubMember
import uniffi.cw_ffi.FfiClubMemberFilter
import uniffi.cw_ffi.FieldStore
import uniffi.cw_ffi.QrzApi

/**
 * One club's detail: members (cached locally, enriched by a detail sync), the
 * activity feed (paged from the server), and the operator's own editable member
 * number. All network work goes through the shared Rust [ClubsApi]. Member map
 * pins start from grid centroids and are refined in the background via
 * [QrzApi.locate] (mirrors iOS `ClubMapView`).
 */
class ClubDetailViewModel(
    private val store: FieldStore,
    private val clubsApi: ClubsApi,
    private val auth: AuthApi,
    private val qrzApi: QrzApi,
    private val clubId: String,
    val myCallsign: String,
) : ViewModel() {

    data class State(
        val members: List<FfiClubMember> = emptyList(),
        val activity: List<FfiClubActivityItem> = emptyList(),
        val hasMoreActivity: Boolean = false,
        val syncing: Boolean = false,
        val loadingActivity: Boolean = false,
        val message: String? = null,
        /** Precise coordinates keyed by uppercase callsign, from [QrzApi.locate].
         * Empty until refinement completes; grid centroids are used as the
         * fallback wherever a callsign has no entry here. */
        val refinedLocations: Map<String, FfiCallsignLocation> = emptyMap(),
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    private var activityCursor: String? = null

    /** Uppercase callsign set refinement last ran for; guards [refineLocations]
     * against firing twice back-to-back when [loadMembers] and [syncDetails]
     * both resolve to the same roster on screen open. */
    private var refinedFor: Set<String>? = null

    init {
        loadMembers()
        syncDetails()
    }

    private fun loadMembers() {
        viewModelScope.launch {
            val members = withContext(Dispatchers.IO) {
                store.fetchClubMembers(FfiClubMemberFilter(clubId, null), PAGE, 0L)
            }
            _state.update { it.copy(members = members) }
            refineLocations(members)
        }
    }

    /** Fetch the full member list (roles/grids) from the server, then reload. */
    fun syncDetails() {
        viewModelScope.launch {
            if (!auth.hasSession()) return@launch
            _state.update { it.copy(syncing = true) }
            try {
                // Async UniFFI future + blocking SQLCipher writes — keep off Main
                // (futures are polled on the caller's dispatcher) to avoid an ANR.
                val members = withContext(Dispatchers.IO) {
                    val bearer = auth.validAccessToken()
                    clubsApi.syncClubDetails(bearer, clubId)
                    store.fetchClubMembers(FfiClubMemberFilter(clubId, null), PAGE, 0L)
                }
                _state.update { it.copy(syncing = false, members = members) }
                refineLocations(members)
            } catch (e: Exception) {
                _state.update { it.copy(syncing = false, message = e.message ?: "Couldn't load members") }
            }
        }
    }

    /**
     * Grid-first render already happened via [_state]'s `members`; this
     * refines pins with precise coordinates from [QrzApi.locate] once
     * resolved. Best-effort — a failure or empty result leaves the existing
     * grid-centroid pins untouched (mirrors iOS `ClubMapView.loadMemberLocations`).
     */
    private fun refineLocations(members: List<FfiClubMember>) {
        if (members.isEmpty()) return
        val callsigns = members.map { it.callsign.uppercase() }.toSet()
        if (callsigns == refinedFor) return
        refinedFor = callsigns
        viewModelScope.launch {
            try {
                // Async UniFFI future — keep off Main per the uniffi-dispatcher rule.
                val located = withContext(Dispatchers.IO) {
                    qrzApi.locate(members.map { it.callsign })
                }
                if (located.isEmpty()) return@launch
                val byCallsign = located.associateBy { it.callsign.uppercase() }
                _state.update { it.copy(refinedLocations = it.refinedLocations + byCallsign) }
            } catch (e: Exception) {
                AppLog.add(AppLog.Level.ERROR, "Club map: member location refinement failed: ${e.message}")
            }
        }
    }

    /** Load the next page of the activity feed (or the first page when reset). */
    fun loadMoreActivity(reset: Boolean = false) {
        viewModelScope.launch {
            if (!auth.hasSession()) {
                _state.update { it.copy(message = "Sign in to view club activity.") }
                return@launch
            }
            if (reset) activityCursor = null
            _state.update { it.copy(loadingActivity = true, message = null) }
            try {
                // Network + async UniFFI poll — keep off the Main dispatcher.
                val page = withContext(Dispatchers.IO) {
                    val bearer = auth.validAccessToken()
                    clubsApi.fetchActivity(bearer, clubId, activityCursor, ACTIVITY_PAGE)
                }
                activityCursor = page.nextCursor
                _state.update {
                    it.copy(
                        loadingActivity = false,
                        activity = if (reset) page.items else it.activity + page.items,
                        hasMoreActivity = page.hasMore,
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(loadingActivity = false, message = e.message ?: "Couldn't load activity") }
            }
        }
    }

    /** Set or clear the operator's own member number for this club (local-only). */
    fun setMyNumber(number: String?) {
        viewModelScope.launch {
            withContext(Dispatchers.IO) {
                store.setClubMemberNumber(clubId, myCallsign, number?.ifBlank { null })
                store.fetchClubMembers(FfiClubMemberFilter(clubId, null), PAGE, 0L)
            }.let { members -> _state.update { it.copy(members = members) } }
        }
    }

    companion object {
        private const val PAGE = 1000L
        private const val ACTIVITY_PAGE = 20L
    }
}
