package app.carrierwave.android.ui.clubs

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
import uniffi.cw_ffi.FfiClub
import uniffi.cw_ffi.FfiClubFilter
import uniffi.cw_ffi.FieldStore

/**
 * Clubs list backed by the shared store. Reads the cached clubs locally and
 * refreshes them through the Rust [ClubsApi] (which fetches, parses, and
 * reconciles the cache) using the bearer from [AuthApi].
 */
class ClubsViewModel(private val app: CwApp) : ViewModel() {

    // Read the shared clients lazily so a server change (which rebuilds them)
    // takes effect without recreating this ViewModel.
    private val store: FieldStore get() = app.store
    private val auth: AuthApi get() = app.authApi

    data class State(
        val clubs: List<FfiClub> = emptyList(),
        val signedIn: Boolean = false,
        val syncing: Boolean = false,
        val message: String? = null,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    init {
        load()
        // If the app-launch auto-sync is still in flight, surface it here and
        // reload once it lands.
        if (app.clubsSyncInFlight != null) sync()
    }

    /** Reload the cached clubs from the local store (no network). */
    fun load() {
        viewModelScope.launch {
            val clubs = fetchClubs()
            _state.update { it.copy(clubs = clubs, signedIn = auth.hasSession()) }
        }
    }

    /** Pull fresh clubs + membership from the server, then reload the cache. */
    fun sync() {
        viewModelScope.launch {
            if (!auth.hasSession()) {
                _state.update { it.copy(message = "Sign in on the Account tab to sync your clubs.") }
                return@launch
            }
            _state.update { it.copy(syncing = true, message = null) }
            try {
                // Shared app-scope sync (single-flight, runs on IO): leaving
                // this screen cancels only the await, not the sync itself.
                val summary = app.syncClubsShared().await()
                _state.update {
                    it.copy(
                        syncing = false,
                        clubs = fetchClubs(),
                        signedIn = true,
                        message = if (summary.clubsChanged || summary.membershipChanged) {
                            "Synced ${summary.clubCount} clubs."
                        } else {
                            "Already up to date."
                        },
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(syncing = false, message = e.message ?: "Sync failed") }
            }
        }
    }

    private suspend fun fetchClubs(): List<FfiClub> = withContext(Dispatchers.IO) {
        store.fetchClubs(FfiClubFilter(null), PAGE, 0L)
    }

    companion object {
        private const val PAGE = 1000L

        fun factory() = viewModelFactory {
            initializer {
                ClubsViewModel(this[APPLICATION_KEY] as CwApp)
            }
        }
    }
}
