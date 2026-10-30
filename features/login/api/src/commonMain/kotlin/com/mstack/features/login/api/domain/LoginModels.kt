package com.mstack.features.login.api.domain

import kotlinx.serialization.Serializable

@Serializable
enum class LoginFlowType {
    PVD,
    MF,
    ODD
}

@Serializable
enum class AccountType {
    INDIVIDUAL,
    JOINT,
    JURISTIC
}

@Serializable
data class UserSession(
    val customerId: String,
    val username: String,
    val authToken: String,
    val refreshToken: String,
    val expiresAt: Long = 0L
)

sealed interface LoginState {
    data object Idle : LoginState
    data object Loading : LoginState
    data class Authenticated(val session: UserSession) : LoginState
    data class Error(val code: String, val message: String) : LoginState
}
