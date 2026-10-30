const test = require("node:test");
const assert = require("node:assert/strict");
const { LoginFlowType, AccountType } = require("../features/login/api");
const { InMemoryKeyValueStore, SyncedLoginStorageProxy } = require("../features/login/impl");

test("Sub-Step 1.2: SyncedLoginStorageProxy Read-Through & Dual-Write Parity", async (t) => {
  await t.test("Legacy boolean write (loginType=true) reads through as PVD and backfills target store", () => {
    const legacy = new InMemoryKeyValueStore();
    const target = new InMemoryKeyValueStore();
    const proxy = new SyncedLoginStorageProxy(legacy, target);

    // Legacy writes boolean
    legacy.putBoolean(SyncedLoginStorageProxy.LEGACY_KEY_LOGIN_TYPE_BOOL, true);

    // Proxy reads through
    const resolved = proxy.getLoginFlowType();
    assert.equal(resolved, LoginFlowType.PVD);

    // Target store must be automatically backfilled
    assert.equal(target.getString(SyncedLoginStorageProxy.KEY_LOGIN_FLOW_TYPE), "PVD");
  });

  await t.test("Legacy boolean write (loginType=false) reads through as MF and backfills target store", () => {
    const legacy = new InMemoryKeyValueStore();
    const target = new InMemoryKeyValueStore();
    const proxy = new SyncedLoginStorageProxy(legacy, target);

    legacy.putBoolean(SyncedLoginStorageProxy.LEGACY_KEY_LOGIN_TYPE_BOOL, false);

    const resolved = proxy.getLoginFlowType();
    assert.equal(resolved, LoginFlowType.MF);
    assert.equal(target.getString(SyncedLoginStorageProxy.KEY_LOGIN_FLOW_TYPE), "MF");
  });

  await t.test("Target saveLoginFlowType dual-writes to target and legacy stores (including legacy boolean)", () => {
    const legacy = new InMemoryKeyValueStore();
    const target = new InMemoryKeyValueStore();
    const proxy = new SyncedLoginStorageProxy(legacy, target);

    proxy.saveLoginFlowType(LoginFlowType.PVD);

    // Modern target key
    assert.equal(target.getString(SyncedLoginStorageProxy.KEY_LOGIN_FLOW_TYPE), "PVD");
    // Legacy flow string key
    assert.equal(legacy.getString(SyncedLoginStorageProxy.LEGACY_KEY_FLOW_STRING), "PVD");
    // Legacy boolean key (true for PVD)
    assert.equal(legacy.getBoolean(SyncedLoginStorageProxy.LEGACY_KEY_LOGIN_TYPE_BOOL), true);

    // Switch to MF
    proxy.saveLoginFlowType(LoginFlowType.MF);
    assert.equal(target.getString(SyncedLoginStorageProxy.KEY_LOGIN_FLOW_TYPE), "MF");
    assert.equal(legacy.getString(SyncedLoginStorageProxy.LEGACY_KEY_FLOW_STRING), "MF");
    assert.equal(legacy.getBoolean(SyncedLoginStorageProxy.LEGACY_KEY_LOGIN_TYPE_BOOL), false);
  });

  await t.test("AccountType bidirectional parity and read-through", () => {
    const legacy = new InMemoryKeyValueStore();
    const target = new InMemoryKeyValueStore();
    const proxy = new SyncedLoginStorageProxy(legacy, target);

    proxy.saveAccountType(AccountType.INDIVIDUAL);
    assert.equal(proxy.getAccountType(), AccountType.INDIVIDUAL);
    assert.equal(legacy.getString("accountType"), "INDIVIDUAL");
    assert.equal(target.getString(SyncedLoginStorageProxy.KEY_ACCOUNT_TYPE), "INDIVIDUAL");

    // Clear and verify read-through from legacy
    target.clear();
    assert.equal(proxy.getAccountType(), AccountType.INDIVIDUAL);
    assert.equal(target.getString(SyncedLoginStorageProxy.KEY_ACCOUNT_TYPE), "INDIVIDUAL");
  });

  await t.test("UserSession dual-write, read-through and clear parity", () => {
    const legacy = new InMemoryKeyValueStore();
    const target = new InMemoryKeyValueStore();
    const proxy = new SyncedLoginStorageProxy(legacy, target);

    const session = {
      customerId: "CUST-12345",
      username: "somchai.t",
      authToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummy",
      refreshToken: "refresh.secret.key",
      expiresAt: 1793456789000
    };

    proxy.saveUserSession(session);

    // Check retrieved session via proxy
    const retrieved = proxy.getUserSession();
    assert.ok(retrieved);
    assert.equal(retrieved.customerId, "CUST-12345");
    assert.equal(retrieved.username, "somchai.t");
    assert.equal(retrieved.authToken, session.authToken);
    assert.equal(retrieved.refreshToken, session.refreshToken);
    assert.equal(retrieved.expiresAt, session.expiresAt);

    // Check legacy store contains the expected keys for legacy code
    assert.equal(legacy.getString(SyncedLoginStorageProxy.LEGACY_KEY_CUSTOMER_ID), "CUST-12345");
    assert.equal(legacy.getString(SyncedLoginStorageProxy.LEGACY_KEY_USERNAME), "somchai.t");
    assert.equal(legacy.getString(SyncedLoginStorageProxy.LEGACY_KEY_TOKEN), session.authToken);
    assert.equal(legacy.getString(SyncedLoginStorageProxy.LEGACY_KEY_REFRESH), session.refreshToken);

    // Test clearSession: both legacy and target must be wiped
    proxy.clearSession();
    assert.equal(proxy.getUserSession(), null);
    assert.equal(legacy.getString(SyncedLoginStorageProxy.LEGACY_KEY_CUSTOMER_ID), null);
    assert.equal(target.getString(SyncedLoginStorageProxy.KEY_CUSTOMER_ID), null);
  });
});
