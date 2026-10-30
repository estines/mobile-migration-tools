package com.mstack.features.login.impl.storage

import com.mstack.features.login.api.domain.AccountType
import com.mstack.features.login.api.domain.LoginFlowType
import com.mstack.features.login.api.domain.UserSession
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class InMemoryKeyValueStore : KeyValueStore {
    private val strings = mutableMapOf<String, String>()
    private val booleans = mutableMapOf<String, Boolean>()
    private val longs = mutableMapOf<String, Long>()

    override fun getString(key: String, defValue: String?): String? = strings[key] ?: defValue
    override fun putString(key: String, value: String?) {
        if (value != null) strings[key] = value else strings.remove(key)
    }

    override fun getBoolean(key: String, defValue: Boolean): Boolean = booleans[key] ?: defValue
    override fun putBoolean(key: String, value: Boolean) { booleans[key] = value }

    override fun getLong(key: String, defValue: Long): Long = longs[key] ?: defValue
    override fun putLong(key: String, value: Long) { longs[key] = value }

    override fun remove(key: String) {
        strings.remove(key)
        booleans.remove(key)
        longs.remove(key)
    }

    override fun clear() {
        strings.clear()
        booleans.clear()
        longs.clear()
    }

    override fun contains(key: String): Boolean =
        strings.containsKey(key) || booleans.containsKey(key) || longs.containsKey(key)
}

class SyncedLoginStorageProxyTest {

    private lateinit var legacyStore: InMemoryKeyValueStore
    private lateinit var targetStore: InMemoryKeyValueStore
    private lateinit var proxy: SyncedLoginStorageProxy

    @BeforeTest
    fun setUp() {
        legacyStore = InMemoryKeyValueStore()
        targetStore = InMemoryKeyValueStore()
        proxy = SyncedLoginStorageProxy(legacyStore = legacyStore, targetStore = targetStore)
    }

    @Test
    fun legacyWrite_booleanTrue_readsThroughAsPvdAndBackfillsTarget() {
        legacyStore.putBoolean(SyncedLoginStorageProxy.LEGACY_KEY_LOGIN_TYPE_BOOL, true)

        val flow = proxy.getLoginFlowType()
        assertEquals(LoginFlowType.PVD, flow)

        // Target store must be backfilled
        assertEquals("PVD", targetStore.getString(SyncedLoginStorageProxy.KEY_LOGIN_FLOW_TYPE))
    }

    @Test
    fun legacyWrite_booleanFalse_readsThroughAsMfAndBackfillsTarget() {
        legacyStore.putBoolean(SyncedLoginStorageProxy.LEGACY_KEY_LOGIN_TYPE_BOOL, false)

        val flow = proxy.getLoginFlowType()
        assertEquals(LoginFlowType.MF, flow)

        assertEquals("MF", targetStore.getString(SyncedLoginStorageProxy.KEY_LOGIN_FLOW_TYPE))
    }

    @Test
    fun targetWrite_dualWritesToLegacyAndTarget() {
        proxy.saveLoginFlowType(LoginFlowType.PVD)

        // Target store has modern key
        assertEquals("PVD", targetStore.getString(SyncedLoginStorageProxy.KEY_LOGIN_FLOW_TYPE))
        // Legacy store has legacy flow string and boolean
        assertEquals("PVD", legacyStore.getString(SyncedLoginStorageProxy.LEGACY_KEY_FLOW_STRING))
        assertTrue(legacyStore.getBoolean(SyncedLoginStorageProxy.LEGACY_KEY_LOGIN_TYPE_BOOL))
    }

    @Test
    fun accountType_bidirectionalParity() {
        proxy.saveAccountType(AccountType.INDIVIDUAL)
        assertEquals(AccountType.INDIVIDUAL, proxy.getAccountType())
        assertEquals("INDIVIDUAL", legacyStore.getString("accountType"))
        assertEquals("INDIVIDUAL", targetStore.getString(SyncedLoginStorageProxy.KEY_ACCOUNT_TYPE))
    }

    @Test
    fun userSession_dualWriteAndReadThrough() {
        val session = UserSession(
            customerId = "CUST-999",
            username = "testuser",
            authToken = "jwt.token.here",
            refreshToken = "refresh.token.here",
            expiresAt = 1893456000000L
        )

        proxy.saveUserSession(session)

        val retrieved = proxy.getUserSession()
        assertNotNull(retrieved)
        assertEquals("CUST-999", retrieved.customerId)
        assertEquals("testuser", retrieved.username)
        assertEquals("jwt.token.here", retrieved.authToken)
        assertEquals(1893456000000L, retrieved.expiresAt)

        // Parity verification on legacy keys
        assertEquals("CUST-999", legacyStore.getString(SyncedLoginStorageProxy.LEGACY_KEY_CUSTOMER_ID))
        assertEquals("jwt.token.here", legacyStore.getString(SyncedLoginStorageProxy.LEGACY_KEY_TOKEN))

        proxy.clearSession()
        assertNull(proxy.getUserSession())
        assertNull(legacyStore.getString(SyncedLoginStorageProxy.LEGACY_KEY_TOKEN))
        assertNull(targetStore.getString(SyncedLoginStorageProxy.KEY_AUTH_TOKEN))
    }
}
