package app.carrierwave.android.ui.logbook

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import app.carrierwave.android.data.LogbookRepository
import app.carrierwave.android.ui.common.cwMessage
import app.carrierwave.android.util.AppLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.AdifApi
import uniffi.cw_ffi.FfiAdifImportOptions
import uniffi.cw_ffi.FfiAdifImportResult
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FfiQueryAnalysis
import uniffi.cw_ffi.MapApi
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

data class LogbookUiState(
    val queryAnalysis: FfiQueryAnalysis? = null,
    val queryError: String? = null,
    /** True while a filter is applied — drives the empty-state copy. */
    val filtered: Boolean = false,
    /** QSO currently open in the editor sheet (null = sheet closed). */
    val editingQso: FfiQso? = null,
    /** True while an ADIF file import is running (disables the menu item). */
    val importing: Boolean = false,
    /** Summary of the last ADIF import, shown in an "Import Complete" dialog. */
    val importResult: String? = null,
    /** Why the last ADIF import failed, shown in an "Import Failed" dialog. */
    val importError: String? = null,
)

/**
 * The Logbook tab: every QSO, searchable. Mirrors the iOS Logbook (`logs`) tab.
 *
 * Reads the shared newest-first snapshot from [LogbookRepository] when unfiltered,
 * and swaps in filtered results from the shared query DSL while a filter is active
 * — without disturbing the shared snapshot that Home/Logger observe.
 *
 * Also hosts the ADIF file import (the iOS Logs-toolbar `ADIFImportModifier`):
 * the file picker hands a content URI to [importAdif], which reads the bytes and
 * runs the shared Rust importer ([AdifApi.importAdif]) — parsing, multi-op
 * filtering, dedup against the whole logbook and the insert all happen in Rust,
 * so Android and iOS agree on what counts as a duplicate.
 */
@OptIn(FlowPreview::class)
class LogbookViewModel(
    private val repo: LogbookRepository,
    val mapApi: MapApi,
    private val adifApi: AdifApi,
    /** The operator's current callsign, read at import time (profile edits apply). */
    private val myCallsign: () -> String,
) : ViewModel() {

    val homeGrid: String = repo.homeGrid

    private val _ui = MutableStateFlow(LogbookUiState())
    val ui: StateFlow<LogbookUiState> = _ui.asStateFlow()

    // null = show the shared snapshot; non-null = show filtered results.
    private val _filteredResults = MutableStateFlow<List<FfiQso>?>(null)

    /** The QSOs currently displayed: filtered results when active, else the snapshot. */
    val qsos: StateFlow<List<FfiQso>> =
        combine(repo.qsos, _filteredResults) { all, filtered -> filtered ?: all }
            .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    val loading: StateFlow<Boolean> = repo.loading

    private val queryChannel = MutableSharedFlow<String>(extraBufferCapacity = 1)

    init {
        viewModelScope.launch { repo.refresh() }
        launchQueryHandling()
    }

    fun onQueryChange(text: String) {
        lastQuery = text
        queryChannel.tryEmit(text)
    }

    /** The most recent raw filter text — re-run after an edit to keep filtered results fresh. */
    private var lastQuery: String = ""

    // ── Inline QSO editing (shared QsoEditSheet) ────────────────
    fun editQso(qso: FfiQso) = _ui.update { it.copy(editingQso = qso) }

    fun dismissEditor() = _ui.update { it.copy(editingQso = null) }

    fun updateQso(qso: FfiQso) = viewModelScope.launch {
        repo.update(qso)
            .onSuccess {
                _ui.update { it.copy(editingQso = null) }
                refilter()
            }
            .onFailure { err -> _ui.update { it.copy(queryError = err.cwMessage()) } }
    }

    /** Sync-safe soft delete (isHidden + dirty upsert), mirroring iOS. */
    fun deleteQso(qso: FfiQso) = viewModelScope.launch {
        repo.softDelete(qso)
            .onSuccess {
                _ui.update { it.copy(editingQso = null) }
                refilter()
            }
            .onFailure { err -> _ui.update { it.copy(queryError = err.cwMessage()) } }
    }

    /** Re-run the active filter so an edit/delete is reflected in filtered results
     *  (the unfiltered snapshot already refreshed inside the repo write). */
    private fun refilter() {
        if (_ui.value.filtered && lastQuery.isNotBlank()) queryChannel.tryEmit(lastQuery)
    }

    // ── ADIF file import ─────────────────────────────────────────────

    /**
     * Import the ADIF file at [uri] (a document picked with `OpenDocument`).
     * Reads the bytes and runs [AdifApi.importAdif] on [Dispatchers.IO]; the
     * repository's store observer refreshes the shared snapshot once the Rust
     * side commits, so no explicit refresh is needed. Upload markers are off:
     * Android has no QRZ/POTA upload credentials yet (every logger path passes
     * `uploadQrz = false`). [context] is the hosting Activity.
     */
    fun importAdif(context: Context, uri: Uri) = viewModelScope.launch {
        if (_ui.value.importing) return@launch
        _ui.update { it.copy(importing = true, importResult = null, importError = null) }
        val resolver = context.applicationContext.contentResolver
        runCatching {
            withContext(Dispatchers.IO) {
                val name = displayName(resolver, uri)
                val bytes = resolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: throw IllegalStateException("Could not open the selected file.")
                val result = adifApi.importAdif(
                    decodeAdif(bytes),
                    FfiAdifImportOptions(myCallsign = myCallsign(), uploadQrz = false, uploadPota = false),
                )
                name to result
            }
        }.onSuccess { (name, result) ->
            AppLog.add(
                AppLog.Level.INFO,
                "ADIF import $name: ${result.imported} imported, ${result.duplicates} duplicates, ${result.errors} errors",
            )
            _ui.update { it.copy(importing = false, importResult = formatImportResult(name, result)) }
            refilter()
        }.onFailure { err ->
            AppLog.add(AppLog.Level.ERROR, "ADIF import failed: ${err.cwMessage()}")
            _ui.update { it.copy(importing = false, importError = err.cwMessage()) }
        }
    }

    fun dismissImportMessage() = _ui.update { it.copy(importResult = null, importError = null) }

    private fun displayName(resolver: ContentResolver, uri: Uri): String {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) cursor.getString(idx)?.let { return it }
            }
        }
        return uri.lastPathSegment ?: "ADIF file"
    }

    /**
     * ADIF is ASCII by spec but older loggers write Latin-1 names/QTHs. Decode
     * strictly as UTF-8 first (iOS requires UTF-8), falling back to ISO-8859-1
     * instead of failing the whole file on one stray byte.
     */
    private fun decodeAdif(bytes: ByteArray): String =
        try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString()
        } catch (_: CharacterCodingException) {
            String(bytes, Charsets.ISO_8859_1)
        }

    /** Same wording as the iOS `ADIFImportModifier.formatResult`. */
    private fun formatImportResult(name: String, result: FfiAdifImportResult): String {
        val parts = mutableListOf("${result.imported} imported")
        if (result.duplicates > 0u) parts += "${result.duplicates} duplicates skipped"
        if (result.errors > 0u) parts += "${result.errors} errors"
        return "$name: ${parts.joinToString(", ")}"
    }

    private fun launchQueryHandling() = viewModelScope.launch {
        queryChannel.debounce(300).collectLatest { raw ->
            if (raw.isBlank()) {
                _filteredResults.update { null }
                _ui.update { it.copy(queryAnalysis = null, queryError = null, filtered = false) }
                return@collectLatest
            }
            // Analyze (for the cost/warning chips) and fetch the filtered rows.
            repo.analyze(raw)
                .onSuccess { analysis -> _ui.update { it.copy(queryError = null, queryAnalysis = analysis) } }
                .onFailure { err ->
                    _ui.update { it.copy(queryError = err.cwMessage(), queryAnalysis = null) }
                }
            repo.queryQsos(raw)
                .onSuccess { rows ->
                    _filteredResults.update { rows }
                    _ui.update { it.copy(filtered = true) }
                }
                .onFailure { err ->
                    _filteredResults.update { emptyList() }
                    _ui.update { it.copy(queryError = err.cwMessage(), filtered = true) }
                }
        }
    }

    companion object {
        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                LogbookViewModel(app.repository, app.mapApi, app.adifApi) { app.userCallsign }
            }
        }
    }
}
