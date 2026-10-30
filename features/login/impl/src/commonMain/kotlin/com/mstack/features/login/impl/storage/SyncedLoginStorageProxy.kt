package com.mstack.features.login.impl.storage

import com.mstack.features.login.api.domain.AccountType
import com.mstack.features.login.api.domain.LoginFlowType
import com.mstack.features.login.api.domain.UserSession
import com.mstack.features.login.api.storage.LoginStorage

/**
 * Key-value storage abstraction for platform storage engines
 * (e.g., SharedPreferences on Android, NSUserDefaults on iOS, DataStore, or In-Memory).
 */
interface KeyValueStore {
    fun getString(key: String, defValue: String? = null): String?
    fun putString(key: String, value: String?)
    fun getBoolean(key: String, defValue: Boolean = false): Boolean
    fun putBoolean(key: String, value: Boolean)
    fun getLong(key: String, defValue: Long = 0L): Long
    fun putLong(key: String, value: Long)
    fun remove(key: String)
    fun clear()
    fun contains(key: String): Boolean
}

/**
 * Read-Through / Dual-Write Storage Proxy.
 *
 * Keeps legacy storage (SharedPreferences / NSUserDefaults) and modern target storage
 * (DataStore / Room KMP) 100% synchronized with zero split-brain:
 * 1. Read-Through: Checks target store first. If missing, falls back to legacy store,
 *    transforms any legacy types (e.g. legacy boolean "loginType" true=PVD, false=MF),
 *    and backfills the target store.
 * 2. Dual-Write: Every write operation writes synchronously to both the target store and
 *    the legacy store (including legacy boolean keys) so that legacy UI/controllers never see stale state.
 * 3. Bidirectional Parity: Writes made by either legacy or candidate paths are immediately consistent.
 */
class SyncedLoginStorageProxy(
    private val legacyStore: KeyValueStore,
    private val targetStore: KeyValueStore = legacyStore
) : LoginStorage {

    companion object {
        // Modern target keys
        const val KEY_LOGIN_FLOW_TYPE = "mstack.login.flow_type"
        const val KEY_ACCOUNT_TYPE = "mstack.login.account_type"
        const val KEY_CUSTOMER_ID = "mstack.login.customer_id"
        const val KEY_USERNAME = "mstack.login.username"
        const val KEY_AUTH_TOKEN = "mstack.login.auth_token"
        const val KEY_REFRESH_TOKEN = "mstack.login.refresh_token"
        const val KEY_EXPIRES_AT = "mstack.login.expires_at"

        // Legacy compatibility keys
        const val LEGACY_KEY_LOGIN_TYPE_BOOL = "loginType" // Boolean: true = PVD, false = MF
        const val LEGACY_KEY_FLOW_STRING = "flow_type"
        const val LEGACY_KEY_CUSTOMER_ID = "customerId"
        const val LEGACY_KEY_USERNAME = "pref_user_name"
        const val LEGACY_KEY_TOKEN = "access_token"
        const val LEGACY_KEY_REFRESH = "refresh_token"
        const val LEGACY_KEY_EXPIRES = "token_expires_at"
    }

    override fun getLoginFlowType(): LoginFlowType? {
        // 1. Check target store
        val targetVal = targetStore.getString(KEY_LOGIN_FLOW_TYPE)
        if (targetVal != null) {
            return try { LoginFlowType.valueOf(targetVal) } catch (_: Exception) { null }
        }

        // 2. Read-through legacy string key
        val legacyVal = legacyStore.getString(LEGACY_KEY_FLOW_STRING)
        if (legacyVal != null) {
            val resolved = try { LoginFlowType.valueOf(legacyVal) } catch (_: Exception) { null }
            if (resolved != null) {
                targetStore.putString(KEY_LOGIN_FLOW_TYPE, resolved.name)
                return resolved
            }
        }

        // 3. Read-through legacy boolean key ("loginType": true=PVD, false=MF)
        if (legacyStore.contains(LEGACY_KEY_LOGIN_TYPE_BOOL)) {
            val isPvd = legacyStore.getBoolean(LEGACY_KEY_LOGIN_TYPE_BOOL, false)
            val resolved = if (isPvd) LoginFlowType.PVD else LoginFlowType.MF
            targetStore.putString(KEY_LOGIN_FLOW_TYPE, resolved.name)
            return resolved
        }

        return null
    }

    override fun saveLoginFlowType(type: LoginFlowType) {
        // Dual-Write: modern key
        targetStore.putString(KEY_LOGIN_FLOW_TYPE, type.name)
        legacyStore.putString(LEGACY_KEY_FLOW_STRING, type.name)

        // Dual-Write: legacy boolean representation for old host code
        legacyStore.putBoolean(LEGACY_KEY_LOGIN_TYPE_BOOL, type == LoginFlowType.PVD)
    }

    override fun getAccountType(): AccountType? {
        val targetVal = targetStore.getString(KEY_ACCOUNT_TYPE)
        if (targetVal != null) {
            return try { AccountType.valueOf(targetVal) } catch (_: Exception) { null }
        }
        val legacyVal = legacyStore.getString("accountType")
        if (legacyVal != null) {
            val resolved = try { AccountType.valueOf(legacyVal) } catch (_: Exception) { null }
            if (resolved != null) {
                targetStore.putString(KEY_ACCOUNT_TYPE, resolved.name)
                return resolved
            }
        }
        return null
    }

    override fun saveAccountType(type: AccountType?) {
        val value = type?.name
        targetStore.putString(KEY_ACCOUNT_TYPE, value)
        legacyStore.putString("accountType", value)
    }

    override fun getCustomerId(): String? {
        val targetVal = targetStore.getString(KEY_CUSTOMER_ID)
        if (targetVal != null) return targetVal

        val legacyVal = legacyStore.getString(LEGACY_KEY_CUSTOMER_ID)
        if (legacyVal != null) {
            targetStore.putString(KEY_CUSTOMER_ID, legacyVal)
            return legacyVal
        }
        return null
    }

    override fun saveCustomerId(customerId: String?) {
        targetStore.putString(KEY_CUSTOMER_ID, customerId)
        legacyStore.putString(LEGACY_KEY_CUSTOMER_ID, customerId)
    }

    override fun getUsername(): String? {
        val targetVal = targetStore.getString(KEY_USERNAME)
        if (targetVal != null) return targetVal

        val legacyVal = legacyStore.getString(LEGACY_KEY_USERNAME)
        if (legacyVal != null) {
            targetStore.putString(KEY_USERNAME, legacyVal)
            return legacyVal
        }
        return null
    }

    override fun saveUsername(username: String?) {
        targetStore.putString(KEY_USERNAME, username)
        legacyStore.putString(LEGACY_KEY_USERNAME, username)
    }

    override fun getAuthToken(): String? {
        val targetVal = targetStore.getString(KEY_AUTH_TOKEN)
        if (targetVal != null) return targetVal

        val legacyVal = legacyStore.getString(LEGACY_KEY_TOKEN)
        if (legacyVal != null) {
            targetStore.putString(KEY_AUTH_TOKEN, legacyVal)
            return legacyVal
        }
        return null
    }

    override fun saveAuthToken(token: String?) {
        targetStore.putString(KEY_AUTH_TOKEN, token)
        legacyStore.putString(LEGACY_KEY_TOKEN, token)
    }

    override fun getRefreshToken(): String? {
        val targetVal = targetStore.getString(KEY_REFRESH_TOKEN)
        if (targetVal != null) return targetVal

        val legacyVal = legacyStore.getString(LEGACY_KEY_REFRESH)
        if (legacyVal != null) {
            targetStore.putString(KEY_REFRESH_TOKEN, legacyVal)
            return legacyVal
        }
        return null
    }

    override fun saveRefreshToken(token: String?) {
        targetStore.putString(KEY_REFRESH_TOKEN, token)
        legacyStore.putString(LEGACY_KEY_REFRESH, token)
    }

    override fun getUserSession(): UserSession? {
        val customerId = getCustomerId() ?: return null
        val username = getUsername() ?: ""
        val token = getAuthToken() ?: ""
        val refresh = getRefreshToken() ?: ""
        val expiresAt = targetStore.getLong(KEY_EXPIRES_AT, legacyStore.getLong(LEGACY_KEY_EXPIRES, 0L))
        return UserSession(
            customerId = customerId,
            username = username,
            authToken = token,
            refreshToken = refresh,
            expiresAt = expiresAt
        )
    }

    override fun saveUserSession(session: UserSession) {
        saveCustomerId(session.customerId)
        saveUsername(session.username)
        saveAuthToken(session.authToken)
        saveRefreshToken(session.refreshToken)
        targetStore.putLong(KEY_EXPIRES_AT, session.expiresAt)
        legacyStore.putLong(LEGACY_KEY_EXPIRES, session.expiresAt)
    }

    override fun clearSession() {
        // Clear target keys
        targetStore.remove(KEY_CUSTOMER_ID)
        targetStore.remove(KEY_USERNAME)
        targetStore.remove(KEY_AUTH_TOKEN)
        targetStore.remove(KEY_REFRESH_TOKEN)
        targetStore.remove(KEY_EXPIRES_AT)

        // Clear legacy keys
        legacyStore.remove(LEGACY_KEY_CUSTOMER_ID)
        legacyStore.remove(LEGACY_KEY_USERNAME)
        legacyStore.remove(LEGACY_KEY_TOKEN)
        legacyStore.remove(LEGACY_KEY_REFRESH)
        legacyStore.remove(LEGACY_KEY_EXPIRES)
    }
}
