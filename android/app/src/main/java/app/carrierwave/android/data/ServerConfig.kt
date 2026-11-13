package app.carrierwave.android.data

import android.content.Context

/**
 * Persists the activities-server base URL the app connects to (clubs + OAuth).
 *
 * Defaults to production; configurable from the Account screen so the app can
 * point at a staging or local dev server. Mirrors the iOS app's
 * `ActivitiesClient` base-URL configuration.
 */
object ServerConfig {
    /** Production activities server. */
    const val DEFAULT_BASE_URL = "https://activities.carrierwave.app"

    private const val PREFS = "cw"
    private const val KEY = "activities_base_url"

    /** The configured base URL, or the production default if unset. */
    fun baseUrl(context: Context): String {
        val stored = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
        return stored?.takeIf { it.isNotBlank() } ?: DEFAULT_BASE_URL
    }

    /** Persist a new base URL (normalized). */
    fun setBaseUrl(context: Context, url: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY, normalize(url))
            .apply()
    }

    /** Trim, ensure an `http(s)` scheme, and drop any trailing slash. */
    fun normalize(url: String): String {
        var value = url.trim()
        if (value.isEmpty()) return DEFAULT_BASE_URL
        if (!value.startsWith("http://") && !value.startsWith("https://")) {
            value = "https://$value"
        }
        return value.trimEnd('/')
    }
}
