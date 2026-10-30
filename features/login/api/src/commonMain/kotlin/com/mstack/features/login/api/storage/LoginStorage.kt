package com.mstack.features.login.api.storage

import com.mstack.features.login.api.domain.AccountType
import com.mstack.features.login.api.domain.LoginFlowType
import com.mstack.features.login.api.domain.UserSession

/**
 * Pure contract for login session and preference storage.
 * Completely free of Android/iOS platform dependencies (SharedPreferences/NSUserDefaults/DataStore).
 */
interface LoginStorage {
    fun getLoginFlowType(): LoginFlowType?
    fun saveLoginFlowType(type: LoginFlowType)

    fun getAccountType(): AccountType?
    fun saveAccountType(type: AccountType?)

    fun getCustomerId(): String?
    fun saveCustomerId(customerId: String?)

    fun getUsername(): String?
    fun saveUsername(username: String?)

    fun getAuthToken(): String?
    fun saveAuthToken(token: String?)

    fun getRefreshToken(): String?
    fun saveRefreshToken(token: String?)

    fun getUserSession(): UserSession?
    fun saveUserSession(session: UserSession)

    fun clearSession()
}
