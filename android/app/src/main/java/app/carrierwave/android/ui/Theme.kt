package app.carrierwave.android.ui

import android.app.Activity
import android.content.Context
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Another Morse Trainer practice days / streak. A fixed purple rather than a
 * scheme role: the activity grid shades QSO days with `primary`, and purple is
 * the one hue none of the six schemes use for `primary` or `tertiary`, so
 * practice stays distinguishable in every theme (mirrors the iOS
 * `ActivityGridColors.amtPractice`).
 */
val AmtPractice = Color(0xFF9D6BFF)

/** The stock dark "instrument" look — green-on-charcoal, the original scheme. */
private val Instrument = darkColorScheme(
    primary = Color(0xFF4CAF83),
    onPrimary = Color(0xFF003821),
    primaryContainer = Color(0xFF0F3D2B),
    onPrimaryContainer = Color(0xFFA6F2CC),
    secondaryContainer = Color(0xFF2E3B36),
    onSecondaryContainer = Color(0xFFCFE9DC),
    tertiary = Color(0xFF82AAFF),
    surface = Color(0xFF1C1C1E),
    onSurface = Color(0xFFE6E6E8),
    surfaceVariant = Color(0xFF2C2C2E),
    onSurfaceVariant = Color(0xFFBFBFC4),
    background = Color(0xFF121214),
    onBackground = Color(0xFFE6E6E8),
    error = Color(0xFFCF6679),
    outline = Color(0xFF5A5A5E),
)

/** Nixie-tube orange glow on warm near-black; brass tertiary. */
private val Nixie = darkColorScheme(
    primary = Color(0xFFFF9F45),
    onPrimary = Color(0xFF3A1D00),
    primaryContainer = Color(0xFF4A2A08),
    onPrimaryContainer = Color(0xFFFFDCBB),
    secondaryContainer = Color(0xFF3B322A),
    onSecondaryContainer = Color(0xFFEADDCB),
    tertiary = Color(0xFFE8C87A),
    surface = Color(0xFF1E1A16),
    onSurface = Color(0xFFEFE6DA),
    surfaceVariant = Color(0xFF2B241E),
    onSurfaceVariant = Color(0xFFC9BCAC),
    background = Color(0xFF141210),
    onBackground = Color(0xFFEFE6DA),
    error = Color(0xFFFF6B5E),
    outline = Color(0xFF5E4B38),
)

/** SDR spectrogram colormap: cold noise-floor navy, signal cyan, peak yellow. */
private val Waterfall = darkColorScheme(
    primary = Color(0xFF3EDBF0),
    onPrimary = Color(0xFF00252C),
    primaryContainer = Color(0xFF0A3A44),
    onPrimaryContainer = Color(0xFFA8F0FA),
    secondaryContainer = Color(0xFF223056),
    onSecondaryContainer = Color(0xFFC9D6F2),
    tertiary = Color(0xFFFFD166),
    surface = Color(0xFF111A30),
    onSurface = Color(0xFFE2E8F5),
    surfaceVariant = Color(0xFF1B2745),
    onSurfaceVariant = Color(0xFFA9B4CE),
    background = Color(0xFF0A1020),
    onBackground = Color(0xFFE2E8F5),
    error = Color(0xFFFF5C7A),
    outline = Color(0xFF3D4A6B),
)

/** Collins S-Line vibes: warm instrument gray, cream panels, dial-pointer red.
 * The one light scheme — doubles as the sunlight-readable field option. */
private val Boatanchor = lightColorScheme(
    primary = Color(0xFF3D5A50),
    onPrimary = Color(0xFFF5F1E8),
    primaryContainer = Color(0xFFC5D6CD),
    onPrimaryContainer = Color(0xFF16261F),
    secondaryContainer = Color(0xFFDDD5C6),
    onSecondaryContainer = Color(0xFF3A342A),
    tertiary = Color(0xFFB3382E),
    surface = Color(0xFFF5F1E8),
    onSurface = Color(0xFF2A2721),
    surfaceVariant = Color(0xFFDDD5C6),
    onSurfaceVariant = Color(0xFF5A5344),
    background = Color(0xFFECE7DE),
    onBackground = Color(0xFF2A2721),
    error = Color(0xFF9A2B22),
    outline = Color(0xFF8A8272),
)

/** Monochrome P1-phosphor CRT: every level a brightness of one green; amber
 * (the "second phosphor") for errors so they still pop. */
private val Phosphor = darkColorScheme(
    primary = Color(0xFF33FF66),
    onPrimary = Color(0xFF00230C),
    primaryContainer = Color(0xFF0A3A1A),
    onPrimaryContainer = Color(0xFFA8FFC2),
    secondaryContainer = Color(0xFF122116),
    onSecondaryContainer = Color(0xFFB8E8C6),
    tertiary = Color(0xFFA8FFC2),
    surface = Color(0xFF0B140D),
    onSurface = Color(0xFFC8F5D4),
    surfaceVariant = Color(0xFF122116),
    onSurfaceVariant = Color(0xFF6FA37E),
    background = Color(0xFF060B07),
    onBackground = Color(0xFFC8F5D4),
    error = Color(0xFFFFB000),
    outline = Color(0xFF2E5C3D),
)

/** Vaporwave dusk — named for greyline propagation, the sunset DX window.
 * Hot magenta and VHS cyan on deep violet. */
private val GreyLine = darkColorScheme(
    primary = Color(0xFFFF6EC7),
    onPrimary = Color(0xFF3D0026),
    primaryContainer = Color(0xFF551146),
    onPrimaryContainer = Color(0xFFFFD6EE),
    secondaryContainer = Color(0xFF3A2A6B),
    onSecondaryContainer = Color(0xFFDCD2F5),
    tertiary = Color(0xFF5EEAD4),
    surface = Color(0xFF1F1740),
    onSurface = Color(0xFFF0E9FF),
    surfaceVariant = Color(0xFF2C2158),
    onSurfaceVariant = Color(0xFFB9ACD9),
    background = Color(0xFF16102B),
    onBackground = Color(0xFFF0E9FF),
    error = Color(0xFFFF8FA3),
    outline = Color(0xFF6C5B9E),
)

/**
 * The selectable app themes. [id] is the persisted key — never change one, or
 * existing installs fall back to [INSTRUMENT] on next launch.
 */
enum class CwThemeChoice(
    val id: String,
    val displayName: String,
    val tagline: String,
    val scheme: ColorScheme,
    val isLight: Boolean = false,
) {
    INSTRUMENT("instrument", "Instrument", "Green-on-charcoal station default", Instrument),
    NIXIE("nixie", "Nixie", "Warm tube glow and brass", Nixie),
    WATERFALL("waterfall", "Waterfall", "Noise floor blue, signal cyan, peak yellow", Waterfall),
    BOATANCHOR("boatanchor", "Boatanchor", "Cream panels and a red dial pointer — light", Boatanchor, isLight = true),
    PHOSPHOR("phosphor", "Phosphor", "Monochrome green CRT terminal", Phosphor),
    GREY_LINE("greyline", "Grey Line", "Vaporwave dusk on the terminator", GreyLine),
    ;

    companion object {
        fun fromId(id: String?): CwThemeChoice =
            entries.firstOrNull { it.id == id } ?: INSTRUMENT
    }
}

/**
 * Persisted theme selection, following the [app.carrierwave.android.data.SyncConfig]
 * prefs pattern plus a [StateFlow] so the whole tree recomposes on change.
 */
object ThemeConfig {
    private const val PREFS = "cw"
    private const val KEY_THEME = "theme_choice"

    private val _choice = MutableStateFlow(CwThemeChoice.INSTRUMENT)
    val choice: StateFlow<CwThemeChoice> = _choice.asStateFlow()

    /** Idempotent; [CwTheme] calls it so the saved theme applies before first frame. */
    fun load(context: Context) {
        _choice.value = CwThemeChoice.fromId(prefs(context).getString(KEY_THEME, null))
    }

    fun set(context: Context, choice: CwThemeChoice) {
        prefs(context).edit().putString(KEY_THEME, choice.id).apply()
        _choice.value = choice
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

@Composable
fun CwTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    remember { ThemeConfig.load(context) }
    val choice by ThemeConfig.choice.collectAsState()

    // Themes ignore the system light/dark setting by design (the instrument
    // look), so steer the status-bar icon contrast off the chosen scheme.
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            (view.context as? Activity)?.window?.let { window ->
                WindowCompat.getInsetsController(window, view)
                    .isAppearanceLightStatusBars = choice.isLight
            }
        }
    }

    MaterialTheme(
        colorScheme = choice.scheme,
        typography = Typography(),
        content = content,
    )
}
