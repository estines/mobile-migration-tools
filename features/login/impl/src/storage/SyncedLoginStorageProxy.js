const { LoginFlowType, AccountType } = require("../../../api");

/**
 * In-Memory KeyValueStore implementation for unit testing and non-Android environments.
 */
class InMemoryKeyValueStore {
  constructor() {
    this.map = new Map();
  }

  getString(key, defVal = null) {
    return this.map.has(key) ? String(this.map.get(key)) : defVal;
  }

  putString(key, value) {
    if (value === null || value === undefined) {
      this.map.delete(key);
    } else {
      this.map.set(key, String(value));
    }
  }

  getBoolean(key, defVal = false) {
    return this.map.has(key) ? Boolean(this.map.get(key)) : defVal;
  }

  putBoolean(key, value) {
    this.map.set(key, Boolean(value));
  }

  getLong(key, defVal = 0) {
    return this.map.has(key) ? Number(this.map.get(key)) : defVal;
  }

  putLong(key, value) {
    this.map.set(key, Number(value));
  }

  remove(key) {
    this.map.delete(key);
  }

  clear() {
    this.map.clear();
  }

  contains(key) {
    return this.map.has(key);
  }
}

/**
 * Read-Through / Dual-Write Storage Proxy.
 * Bridges legacy storage (SharedPreferences / NSUserDefaults) and modern target storage (DataStore / Room).
 */
class SyncedLoginStorageProxy {
  static KEY_LOGIN_FLOW_TYPE = "mstack.login.flow_type";
  static KEY_ACCOUNT_TYPE = "mstack.login.account_type";
  static KEY_CUSTOMER_ID = "mstack.login.customer_id";
  static KEY_USERNAME = "mstack.login.username";
  static KEY_AUTH_TOKEN = "mstack.login.auth_token";
  static KEY_REFRESH_TOKEN = "mstack.login.refresh_token";
  static KEY_EXPIRES_AT = "mstack.login.expires_at";

  static LEGACY_KEY_LOGIN_TYPE_BOOL = "loginType"; // true = PVD, false = MF
  static LEGACY_KEY_FLOW_STRING = "flow_type";
  static LEGACY_KEY_CUSTOMER_ID = "customerId";
  static LEGACY_KEY_USERNAME = "pref_user_name";
  static LEGACY_KEY_TOKEN = "access_token";
  static LEGACY_KEY_REFRESH = "refresh_token";
  static LEGACY_KEY_EXPIRES = "token_expires_at";

  constructor(legacyStore = new InMemoryKeyValueStore(), targetStore = new InMemoryKeyValueStore()) {
    this.legacyStore = legacyStore;
    this.targetStore = targetStore;
  }

  getLoginFlowType() {
    // 1. Check target store
    const targetVal = this.targetStore.getString(SyncedLoginStorageProxy.KEY_LOGIN_FLOW_TYPE);
    if (targetVal && LoginFlowType[targetVal]) {
      return targetVal;
    }

    // 2. Read-through legacy string key
    const legacyVal = this.legacyStore.getString(SyncedLoginStorageProxy.LEGACY_KEY_FLOW_STRING);
    if (legacyVal && LoginFlowType[legacyVal]) {
      this.targetStore.putString(SyncedLoginStorageProxy.KEY_LOGIN_FLOW_TYPE, legacyVal);
      return legacyVal;
    }

    // 3. Read-through legacy boolean key
    if (this.legacyStore.contains(SyncedLoginStorageProxy.LEGACY_KEY_LOGIN_TYPE_BOOL)) {
      const isPvd = this.legacyStore.getBoolean(SyncedLoginStorageProxy.LEGACY_KEY_LOGIN_TYPE_BOOL, false);
      const resolved = isPvd ? LoginFlowType.PVD : LoginFlowType.MF;
      this.targetStore.putString(SyncedLoginStorageProxy.KEY_LOGIN_FLOW_TYPE, resolved);
      return resolved;
    }

    return null;
  }

  saveLoginFlowType(type) {
    if (!type || !LoginFlowType[type]) {
      throw new Error(`Invalid LoginFlowType: ${type}`);
    }
    // Dual-write: target store modern key
    this.targetStore.putString(SyncedLoginStorageProxy.KEY_LOGIN_FLOW_TYPE, type);
    // Dual-write: legacy store string key
    this.legacyStore.putString(SyncedLoginStorageProxy.LEGACY_KEY_FLOW_STRING, type);
    // Dual-write: legacy store boolean key for compatibility
    this.legacyStore.putBoolean(SyncedLoginStorageProxy.LEGACY_KEY_LOGIN_TYPE_BOOL, type === LoginFlowType.PVD);
  }

  getAccountType() {
    const targetVal = this.targetStore.getString(SyncedLoginStorageProxy.KEY_ACCOUNT_TYPE);
    if (targetVal && AccountType[targetVal]) return targetVal;

    const legacyVal = this.legacyStore.getString("accountType");
    if (legacyVal && AccountType[legacyVal]) {
      this.targetStore.putString(SyncedLoginStorageProxy.KEY_ACCOUNT_TYPE, legacyVal);
      return legacyVal;
    }
    return null;
  }

  saveAccountType(type) {
    this.targetStore.putString(SyncedLoginStorageProxy.KEY_ACCOUNT_TYPE, type || null);
    this.legacyStore.putString("accountType", type || null);
  }

  getCustomerId() {
    const targetVal = this.targetStore.getString(SyncedLoginStorageProxy.KEY_CUSTOMER_ID);
    if (targetVal) return targetVal;

    const legacyVal = this.legacyStore.getString(SyncedLoginStorageProxy.LEGACY_KEY_CUSTOMER_ID);
    if (legacyVal) {
      this.targetStore.putString(SyncedLoginStorageProxy.KEY_CUSTOMER_ID, legacyVal);
      return legacyVal;
    }
    return null;
  }

  saveCustomerId(customerId) {
    this.targetStore.putString(SyncedLoginStorageProxy.KEY_CUSTOMER_ID, customerId || null);
    this.legacyStore.putString(SyncedLoginStorageProxy.LEGACY_KEY_CUSTOMER_ID, customerId || null);
  }

  getUsername() {
    const targetVal = this.targetStore.getString(SyncedLoginStorageProxy.KEY_USERNAME);
    if (targetVal) return targetVal;

    const legacyVal = this.legacyStore.getString(SyncedLoginStorageProxy.LEGACY_KEY_USERNAME);
    if (legacyVal) {
      this.targetStore.putString(SyncedLoginStorageProxy.KEY_USERNAME, legacyVal);
      return legacyVal;
    }
    return null;
  }

  saveUsername(username) {
    this.targetStore.putString(SyncedLoginStorageProxy.KEY_USERNAME, username || null);
    this.legacyStore.putString(SyncedLoginStorageProxy.LEGACY_KEY_USERNAME, username || null);
  }

  getAuthToken() {
    const targetVal = this.targetStore.getString(SyncedLoginStorageProxy.KEY_AUTH_TOKEN);
    if (targetVal) return targetVal;

    const legacyVal = this.legacyStore.getString(SyncedLoginStorageProxy.LEGACY_KEY_TOKEN);
    if (legacyVal) {
      this.targetStore.putString(SyncedLoginStorageProxy.KEY_AUTH_TOKEN, legacyVal);
      return legacyVal;
    }
    return null;
  }

  saveAuthToken(token) {
    this.targetStore.putString(SyncedLoginStorageProxy.KEY_AUTH_TOKEN, token || null);
    this.legacyStore.putString(SyncedLoginStorageProxy.LEGACY_KEY_TOKEN, token || null);
  }

  getUserSession() {
    const customerId = this.getCustomerId();
    if (!customerId) return null;

    return {
      customerId,
      username: this.getUsername() || "",
      authToken: this.getAuthToken() || "",
      refreshToken: this.legacyStore.getString(SyncedLoginStorageProxy.LEGACY_KEY_REFRESH) || "",
      expiresAt: this.targetStore.getLong(SyncedLoginStorageProxy.KEY_EXPIRES_AT, 0)
    };
  }

  saveUserSession(session) {
    if (!session || !session.customerId) {
      throw new Error("Invalid session: customerId required");
    }
    this.saveCustomerId(session.customerId);
    this.saveUsername(session.username);
    this.saveAuthToken(session.authToken);
    this.targetStore.putString(SyncedLoginStorageProxy.KEY_REFRESH_TOKEN, session.refreshToken || "");
    this.legacyStore.putString(SyncedLoginStorageProxy.LEGACY_KEY_REFRESH, session.refreshToken || "");
    this.targetStore.putLong(SyncedLoginStorageProxy.KEY_EXPIRES_AT, session.expiresAt || 0);
    this.legacyStore.putLong(SyncedLoginStorageProxy.LEGACY_KEY_EXPIRES, session.expiresAt || 0);
  }

  clearSession() {
    this.targetStore.remove(SyncedLoginStorageProxy.KEY_CUSTOMER_ID);
    this.targetStore.remove(SyncedLoginStorageProxy.KEY_USERNAME);
    this.targetStore.remove(SyncedLoginStorageProxy.KEY_AUTH_TOKEN);
    this.targetStore.remove(SyncedLoginStorageProxy.KEY_REFRESH_TOKEN);
    this.targetStore.remove(SyncedLoginStorageProxy.KEY_EXPIRES_AT);

    this.legacyStore.remove(SyncedLoginStorageProxy.LEGACY_KEY_CUSTOMER_ID);
    this.legacyStore.remove(SyncedLoginStorageProxy.LEGACY_KEY_USERNAME);
    this.legacyStore.remove(SyncedLoginStorageProxy.LEGACY_KEY_TOKEN);
    this.legacyStore.remove(SyncedLoginStorageProxy.LEGACY_KEY_REFRESH);
    this.legacyStore.remove(SyncedLoginStorageProxy.LEGACY_KEY_EXPIRES);
  }
}

module.exports = {
  InMemoryKeyValueStore,
  SyncedLoginStorageProxy
};
