package app.carrierwave.android.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import uniffi.cw_ffi.SecureStore

/**
 * Host-side [SecureStore] for the Rust [uniffi.cw_ffi.AuthApi]: small OAuth
 * secrets (the rotating refresh token, the in-flight PKCE verifier) stored in
 * an [EncryptedSharedPreferences] file whose master key lives in the Android
 * Keystore. The Rust core drives the OAuth protocol and calls back into this for
 * persistence — the iOS equivalent is the Keychain-backed store.
 */
class AndroidSecureStore(context: Context) : SecureStore {

    private val prefs: SharedPreferences

    init {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        prefs = EncryptedSharedPreferences.create(
            context,
            "cw_secure",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    override fun `get`(key: String): String? = prefs.getString(key, null)

    override fun `set`(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }

    override fun delete(key: String) {
        prefs.edit().remove(key).apply()
    }
}
