package app.carrierwave.android.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import app.carrierwave.android.ui.common.cwMessage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.AmtApi
import uniffi.cw_ffi.FfiAmtAccount
import uniffi.cw_ffi.FfiAmtSignInOutcome
import uniffi.cw_ffi.FfiAmtStats
import java.time.LocalDate

/**
 * Drives the Another Morse Trainer settings screen. All protocol logic (PKCE,
 * the 2 s poll, token rotation, the offline snapshot) lives in the shared Rust
 * [AmtApi]; this view model sequences the calls and exposes UI state, and pokes
 * [CwApp.amtChanged] so the Home screen picks up the new streak.
 */
class AmtViewModel(private val app: CwApp) : ViewModel() {

    private val amt: AmtApi get() = app.amtApi

    data class State(
        val signedIn: Boolean = false,
        val account: FfiAmtAccount? = null,
        val stats: FfiAmtStats? = null,
        /** Email of an in-flight sign-in (link sent, not yet confirmed). */
        val pendingEmail: String? = null,
        val busy: Boolean = false,
        val refreshing: Boolean = false,
        val message: String? = null,
        val isError: Boolean = false,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    /** The in-flight start+poll coroutine, so [cancel] can actually stop it. */
    private var signInJob: Job? = null

    init {
        viewModelScope.launch {
            _state.value = snapshot()
            // A link was sent before the app was closed — keep waiting for it.
            if (!_state.value.signedIn && _state.value.pendingEmail != null) poll()
        }
    }

    private suspend fun snapshot(
        busy: Boolean = false,
        refreshing: Boolean = false,
        message: String? = null,
        isError: Boolean = false,
    ): State = withContext(Dispatchers.IO) {
        State(
            signedIn = amt.hasSession(),
            account = amt.account(),
            stats = amt.cachedStats(),
            pendingEmail = amt.pendingEmail(),
            busy = busy,
            refreshing = refreshing,
            message = message,
            isError = isError,
        )
    }

    /** Ask AMT to email a sign-in link, then poll until Confirm is pressed. */
    fun sendLink(email: String) {
        val address = email.trim()
        if (!address.contains('@')) {
            _state.update { it.copy(message = "Enter the email of your AMT account.", isError = true) }
            return
        }
        signInJob?.cancel()
        signInJob = viewModelScope.launch {
            _state.value = snapshot(busy = true)
            try {
                withContext(Dispatchers.IO) { amt.startSignIn(address) }
                _state.value = snapshot(busy = true, message = "Check your email and press Confirm…")
                poll()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.value = snapshot(message = "Couldn't send the link: ${e.cwMessage()}", isError = true)
            }
        }
    }

    private suspend fun poll() {
        _state.update { it.copy(busy = true) }
        try {
            // Links live 15 minutes; poll a little past that.
            val outcome = withContext(Dispatchers.IO) { amt.pollForCompletion(POLL_TIMEOUT_SECS) }
            when (outcome) {
                FfiAmtSignInOutcome.SIGNED_IN -> {
                    _state.value = snapshot(message = "Connected.")
                    app.amtChanged.tryEmit(Unit)
                    refreshStats()
                }
                FfiAmtSignInOutcome.TIMED_OUT -> {
                    withContext(Dispatchers.IO) { amt.cancelPendingSignIn() }
                    _state.value = snapshot(
                        message = "We didn't see the link confirmed in time. Send a new one to try again.",
                        isError = true,
                    )
                }
                FfiAmtSignInOutcome.LINK_EXPIRED -> _state.value = snapshot(
                    message = "That link expired or was already used. Send a new one to try again.",
                    isError = true,
                )
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.value = snapshot(message = "Sign-in failed: ${e.cwMessage()}", isError = true)
        }
    }

    fun cancel() {
        signInJob?.cancel()
        signInJob = null
        viewModelScope.launch {
            withContext(Dispatchers.IO) { amt.cancelPendingSignIn() }
            _state.value = snapshot()
        }
    }

    /** Fetch `/v1/me/stats` now (one refresh-and-retry on 401 happens in Rust). */
    fun refreshStats() {
        if (_state.value.refreshing) return
        viewModelScope.launch {
            _state.update { it.copy(refreshing = true, message = null, isError = false) }
            try {
                withContext(Dispatchers.IO) { amt.refreshStats(LocalDate.now().toString()) }
                _state.value = snapshot(message = "Updated.")
            } catch (e: Exception) {
                // A dead session (user removed Carrier Wave in AMT) is already
                // cleared Rust-side; snapshot() reflects the sign-out.
                _state.value = snapshot(message = e.cwMessage(), isError = true)
            }
            app.amtChanged.tryEmit(Unit)
        }
    }

    fun signOut() {
        signInJob?.cancel()
        signInJob = null
        viewModelScope.launch {
            _state.update { it.copy(busy = true) }
            try {
                withContext(Dispatchers.IO) { amt.signOut() }
            } catch (_: Exception) {
                // Local state is cleared regardless; a network failure is non-fatal.
            }
            _state.value = snapshot(message = "Signed out.")
            app.amtChanged.tryEmit(Unit)
        }
    }

    companion object {
        private const val POLL_TIMEOUT_SECS: UInt = 960u // 16 minutes

        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                AmtViewModel(app)
            }
        }
    }
}
