package app.carrierwave.android.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * One row in the logger keyboard accessory stack, mirroring the iOS
 * `KeyboardRowKind` (minus the CW keyer row — no CW bridge on Android yet).
 */
enum class KeyboardRow(val id: String, val label: String) {
    NUMBERS("numbers", "Numbers & Symbols"),
    PREFIXES("prefixes", "Prefixes"),
    COMMANDS("commands", "Commands"),
    ;

    companion object {
        val defaultOrder = listOf(NUMBERS, PREFIXES, COMMANDS)

        fun fromId(id: String): KeyboardRow? = entries.firstOrNull { it.id == id }
    }
}

/** User-configurable state of the accessory rows (CAR-290). */
data class KeyboardRowsState(
    val order: List<KeyboardRow> = KeyboardRow.defaultOrder,
    val numbersEnabled: Boolean = true,
    val prefixesEnabled: Boolean = true,
    val commandsEnabled: Boolean = true,
    /** "suggested" (position-local, from shared Rust) or "custom". */
    val prefixMode: String = MODE_SUGGESTED,
    val customPrefixes: List<String> = emptyList(),
) {
    companion object {
        const val MODE_SUGGESTED = "suggested"
        const val MODE_CUSTOM = "custom"
    }
}

/**
 * SharedPreferences-backed keyboard-rows config with a reactive
 * [StateFlow], following the `ThemeConfig` pattern.
 */
object LoggerKeyboardConfig {
    private const val PREFS = "cw"
    private const val KEY_ORDER = "keyboard_row_order"
    private const val KEY_NUMBERS = "keyboard_row_numbers_enabled"
    private const val KEY_PREFIXES = "prefix_row_enabled"
    private const val KEY_COMMANDS = "command_row_enabled"
    private const val KEY_PREFIX_MODE = "prefix_row_mode"
    private const val KEY_PREFIX_CUSTOM = "prefix_row_custom"

    private val _state = MutableStateFlow(KeyboardRowsState())
    val state: StateFlow<KeyboardRowsState> = _state.asStateFlow()

    fun load(context: Context) {
        val prefs = prefs(context)
        val order = (prefs.getString(KEY_ORDER, null) ?: "")
            .split(",")
            .mapNotNull(KeyboardRow::fromId)
            .let { parsed -> parsed + KeyboardRow.defaultOrder.filter { it !in parsed } }
        _state.value = KeyboardRowsState(
            order = order,
            numbersEnabled = prefs.getBoolean(KEY_NUMBERS, true),
            prefixesEnabled = prefs.getBoolean(KEY_PREFIXES, true),
            commandsEnabled = prefs.getBoolean(KEY_COMMANDS, true),
            prefixMode = prefs.getString(KEY_PREFIX_MODE, null) ?: KeyboardRowsState.MODE_SUGGESTED,
            customPrefixes = (prefs.getString(KEY_PREFIX_CUSTOM, null) ?: "")
                .split(",")
                .filter { it.isNotEmpty() },
        )
    }

    fun update(context: Context, transform: (KeyboardRowsState) -> KeyboardRowsState) {
        val next = transform(_state.value)
        prefs(context).edit()
            .putString(KEY_ORDER, next.order.joinToString(",") { it.id })
            .putBoolean(KEY_NUMBERS, next.numbersEnabled)
            .putBoolean(KEY_PREFIXES, next.prefixesEnabled)
            .putBoolean(KEY_COMMANDS, next.commandsEnabled)
            .putString(KEY_PREFIX_MODE, next.prefixMode)
            .putString(KEY_PREFIX_CUSTOM, next.customPrefixes.joinToString(","))
            .apply()
        _state.value = next
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

/** Smart-replace helper for prefix hot keys, mirroring iOS `CallsignPrefixer`. */
object CallsignPrefixer {
    /**
     * If [text] starts with any known prefix, swap it for [prefix] keeping the
     * suffix; otherwise prepend. Result is uppercased (callsign entry).
     */
    fun apply(prefix: String, text: String, knownPrefixes: List<String>): String {
        val upper = text.uppercase()
        for (known in knownPrefixes.sortedByDescending { it.length }) {
            if (known != prefix && upper.startsWith(known)) {
                return prefix + upper.removePrefix(known)
            }
        }
        if (upper.startsWith(prefix)) {
            return upper
        }
        return prefix + upper
    }
}
