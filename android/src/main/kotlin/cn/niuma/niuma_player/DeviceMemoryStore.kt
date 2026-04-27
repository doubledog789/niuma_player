package cn.niuma.niuma_player

import android.content.Context

/**
 * Persistent "this device needs IJK" memory, keyed by device fingerprint.
 *
 * Storage strategy:
 *   - SharedPreferences file `niuma_player.device_memory`
 *   - Key  : `niuma_player.ijk_needed.<fingerprint>`
 *   - Value: Long expiresAt epoch-ms; sentinel [NO_EXPIRY] (`Long.MIN_VALUE`)
 *           means "never expires"
 *
 * The TTL/expiry policy itself lives on the Dart side — this class is a
 * dumb key-value store. Dart fetches the raw expiresAt, compares with its
 * own injectable clock, and calls [unset] when an entry has expired. That
 * keeps existing test fakes (which mock `now()`) working without having to
 * shuffle a clock through MethodChannel.
 */
internal class DeviceMemoryStore(private val context: Context) {

    private fun prefs() = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun key(fingerprint: String) = "$KEY_PREFIX$fingerprint"

    /// Returns null if the fingerprint isn't marked. Otherwise returns the
    /// stored expiresAt — [NO_EXPIRY] means "no expiry".
    fun get(fingerprint: String): Long? {
        val k = key(fingerprint)
        val p = prefs()
        if (!p.contains(k)) return null
        return p.getLong(k, NO_EXPIRY)
    }

    fun set(fingerprint: String, expiresAt: Long) {
        prefs().edit().putLong(key(fingerprint), expiresAt).apply()
    }

    fun unset(fingerprint: String) {
        prefs().edit().remove(key(fingerprint)).apply()
    }

    /// Removes every niuma_player memory entry. Useful for app-level
    /// "clear cache" flows.
    fun clear() {
        val p = prefs()
        val toRemove = p.all.keys.filter { it.startsWith(KEY_PREFIX) }
        if (toRemove.isEmpty()) return
        val editor = p.edit()
        for (k in toRemove) editor.remove(k)
        editor.apply()
    }

    companion object {
        private const val PREFS_NAME = "niuma_player.device_memory"
        private const val KEY_PREFIX = "niuma_player.ijk_needed."

        /// Sentinel for "no expiry". Picked so any legitimate epoch-ms value
        /// (positive long, including far-future) is unambiguously distinct.
        const val NO_EXPIRY: Long = Long.MIN_VALUE
    }
}
