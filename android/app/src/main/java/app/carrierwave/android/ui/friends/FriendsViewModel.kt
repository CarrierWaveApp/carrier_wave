package app.carrierwave.android.ui.friends

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.AuthApi
import uniffi.cw_ffi.FfiFeedItem
import uniffi.cw_ffi.FfiFriendship
import uniffi.cw_ffi.FfiFriendshipFilter
import uniffi.cw_ffi.FfiUserSearchResult
import uniffi.cw_ffi.FieldStore
import uniffi.cw_ffi.FriendsApi

/**
 * Friends tab backed by the shared store. Reads the cached social graph locally
 * and refreshes it through the Rust [FriendsApi] (which fetches, parses, and
 * reconciles the `friendship` cache) using the bearer from [AuthApi]. The
 * activity feed is fetched on demand and not persisted.
 *
 * Mirrors iOS `FriendsSyncService` + `ActivityView`.
 */
class FriendsViewModel(private val app: CwApp) : ViewModel() {

    // Read the shared clients lazily so a server change (which rebuilds them)
    // takes effect without recreating this ViewModel.
    private val store: FieldStore get() = app.store
    private val friendsApi: FriendsApi get() = app.friendsApi
    private val auth: AuthApi get() = app.authApi

    data class State(
        val friends: List<FfiFriendship> = emptyList(),
        val incoming: List<FfiFriendship> = emptyList(),
        val outgoing: List<FfiFriendship> = emptyList(),
        val searchResults: List<FfiUserSearchResult> = emptyList(),
        val feed: List<FfiFeedItem> = emptyList(),
        val signedIn: Boolean = false,
        val syncing: Boolean = false,
        val searching: Boolean = false,
        val message: String? = null,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    init {
        load()
        // If the app-launch auto-sync is still in flight, surface it here and
        // reload once it lands.
        if (app.friendsSyncInFlight != null) sync()
    }

    /** Reload the cached friendships from the local store (no network). */
    fun load() {
        viewModelScope.launch {
            val rows = fetchFriendships()
            _state.update { applyRows(it, rows).copy(signedIn = auth.hasSession()) }
        }
    }

    /** Pull fresh friends + requests from the server, reconcile, then reload + load feed. */
    fun sync() {
        viewModelScope.launch {
            if (!auth.hasSession()) {
                _state.update { it.copy(message = "Sign in on the More tab to use Friends.") }
                return@launch
            }
            _state.update { it.copy(syncing = true, message = null) }
            try {
                // Shared app-scope sync (single-flight, runs on IO): leaving
                // this screen cancels only the await, not the sync itself.
                val summary = app.syncFriendsShared().await()
                val rows = fetchFriendships()
                _state.update {
                    applyRows(it, rows).copy(
                        syncing = false,
                        signedIn = true,
                        message = "${summary.friendCount} friends, " +
                            "${summary.incomingRequestCount} pending.",
                    )
                }
                loadFeed()
            } catch (e: Exception) {
                _state.update { it.copy(syncing = false, message = e.message ?: "Sync failed") }
            }
        }
    }

    /** Search registered users by callsign (server, ≥2 chars). */
    fun search(query: String) {
        viewModelScope.launch {
            if (query.length < 2 || !auth.hasSession()) {
                _state.update { it.copy(searchResults = emptyList()) }
                return@launch
            }
            _state.update { it.copy(searching = true) }
            try {
                val results = withContext(Dispatchers.IO) {
                    friendsApi.searchUsers(auth.validAccessToken(), query)
                }
                _state.update { it.copy(searching = false, searchResults = results) }
            } catch (e: Exception) {
                _state.update { it.copy(searching = false, message = e.message ?: "Search failed") }
            }
        }
    }

    fun sendRequest(userId: String) = act { bearer -> friendsApi.sendRequest(bearer, userId) }

    fun acceptRequest(requestId: String) = act { bearer -> friendsApi.acceptRequest(bearer, requestId) }

    fun declineRequest(requestId: String) = act { bearer -> friendsApi.declineRequest(bearer, requestId) }

    fun removeFriend(friendshipId: String) = act { bearer -> friendsApi.removeFriend(bearer, friendshipId) }

    /** Run a friends mutation on IO with the bearer, then re-sync to reflect it. */
    private fun act(block: suspend (bearer: String) -> Unit) {
        viewModelScope.launch {
            if (!auth.hasSession()) return@launch
            try {
                withContext(Dispatchers.IO) { block(auth.validAccessToken()) }
                _state.update { it.copy(searchResults = emptyList()) }
                sync()
            } catch (e: Exception) {
                _state.update { it.copy(message = e.message ?: "Action failed") }
            }
        }
    }

    private fun loadFeed() {
        viewModelScope.launch {
            if (!auth.hasSession()) return@launch
            try {
                val page = withContext(Dispatchers.IO) {
                    friendsApi.fetchFeed(auth.validAccessToken(), "friends", null, FEED_PAGE)
                }
                _state.update { it.copy(feed = page.items) }
            } catch (_: Exception) {
                // Feed is best-effort; a failure shouldn't surface as an error.
            }
        }
    }

    private fun applyRows(state: State, rows: List<FfiFriendship>): State {
        val accepted = rows.filter { it.status == STATUS_ACCEPTED }
        val pending = rows.filter { it.status == STATUS_PENDING }
        return state.copy(
            friends = accepted,
            incoming = pending.filter { !it.isOutgoing },
            outgoing = pending.filter { it.isOutgoing },
        )
    }

    private suspend fun fetchFriendships(): List<FfiFriendship> = withContext(Dispatchers.IO) {
        store.fetchFriendships(FfiFriendshipFilter(null), PAGE, 0L)
    }

    companion object {
        private const val PAGE = 1000L
        private const val FEED_PAGE = 50L
        private const val STATUS_ACCEPTED = "accepted"
        private const val STATUS_PENDING = "pending"

        fun factory() = viewModelFactory {
            initializer {
                FriendsViewModel(this[APPLICATION_KEY] as CwApp)
            }
        }
    }
}
