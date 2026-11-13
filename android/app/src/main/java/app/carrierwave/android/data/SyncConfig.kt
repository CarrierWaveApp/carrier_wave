package app.carrierwave.android.data

import android.content.Context
import android.util.Base64
import app.carrierwave.android.auth.AndroidSecureStore

/**
 * Client state for Carrier Wave Sync (the E2E-encrypted sync server).
 *
 * The 32-byte data key — recovered from the passphrase escrow — lives in the
 * Keystore-backed [AndroidSecureStore]; sync is "enabled" exactly when a key is
 * present. The pull cursor (`high_water` from the last run) and last-sync time
 * are plain prefs. The cursor is per-server: pointing the app at a different
 * activities server resets it to 0 so a stale sequence can't skip pulls.
 */
object SyncConfig {
    private const val PREFS = "cw"
    private const val KEY_LAST_SEQ = "sync_last_seq"
    private const val KEY_LAST_AT = "sync_last_at"
    private const val KEY_SERVER = "sync_server_url"
    private const val KEY_SEEDED_SERVER = "sync_seeded_server"
    private const val SECURE_KEY_DATA_KEY = "cw.sync.data_key"

    /**
     * The data key is scoped per server (like the cursor and seeded flag): a
     * key recovered from one server's escrow must never be silently reused
     * against another, or a server switch uploads blobs the new server's
     * escrow can't decrypt. Legacy unscoped keys are intentionally ignored.
     */
    fun dataKey(context: Context, serverUrl: String): ByteArray? =
        AndroidSecureStore(context).get(secureKeyFor(serverUrl))
            ?.let { Base64.decode(it, Base64.NO_WRAP) }

    fun storeDataKey(context: Context, serverUrl: String, key: ByteArray) {
        AndroidSecureStore(context).set(secureKeyFor(serverUrl), Base64.encodeToString(key, Base64.NO_WRAP))
    }

    fun clearDataKey(context: Context, serverUrl: String) {
        AndroidSecureStore(context).delete(secureKeyFor(serverUrl))
        // Sweep the legacy unscoped slot too.
        AndroidSecureStore(context).delete(SECURE_KEY_DATA_KEY)
        prefs(context).edit()
            .remove(KEY_LAST_SEQ)
            .remove(KEY_LAST_AT)
            .remove(KEY_SERVER)
            .remove(KEY_SEEDED_SERVER)
            .apply()
    }

    /**
     * Whether [serverUrl] has ever completed a sync pass from this install.
     * Dirty flags are cleared by pushes to *any* server, so the first pass
     * against a new server must re-mark the whole log (staging → prod switch)
     * or the new server never receives the existing QSOs.
     */
    fun isSeeded(context: Context, serverUrl: String): Boolean =
        prefs(context).getString(KEY_SEEDED_SERVER, null) == serverUrl

    fun markSeeded(context: Context, serverUrl: String) {
        prefs(context).edit().putString(KEY_SEEDED_SERVER, serverUrl).apply()
    }

    /** The pull cursor for [serverUrl]; 0 when unset or the server changed. */
    fun lastSeq(context: Context, serverUrl: String): Long {
        val p = prefs(context)
        if (p.getString(KEY_SERVER, null) != serverUrl) return 0L
        return p.getLong(KEY_LAST_SEQ, 0L)
    }

    fun storeCursor(context: Context, serverUrl: String, seq: Long, atSeconds: Long) {
        prefs(context).edit()
            .putString(KEY_SERVER, serverUrl)
            .putLong(KEY_LAST_SEQ, seq)
            .putLong(KEY_LAST_AT, atSeconds)
            .apply()
    }

    /** Unix seconds of the last successful run, or null. */
    fun lastSyncAt(context: Context): Long? =
        prefs(context).getLong(KEY_LAST_AT, 0L).takeIf { it > 0L }

    private fun secureKeyFor(serverUrl: String) = "$SECURE_KEY_DATA_KEY.$serverUrl"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
